// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "@glow/testing/TestGCC.sol";
import "forge-std/console.sol";
import {IGCA} from "@glow/interfaces/IGCA.sol";
import {MockGCA} from "@glow/MinerPoolAndGCA/mock/MockGCA.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import "forge-std/StdUtils.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {TestGLOW} from "@glow/testing/TestGLOW.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MerkleProofLib} from "@solady/utils/MerkleProofLib.sol";
import {MockMinerPoolAndGCA} from "@glow/MinerPoolAndGCA/mock/MockMinerPoolAndGCA.sol";
import {MockUSDC} from "@glow/testing/MockUSDC.sol";
import {IMinerPool} from "@glow/interfaces/IMinerPool.sol";
import {BucketSubmission} from "@glow/MinerPoolAndGCA/BucketSubmission.sol";
import {VetoCouncil} from "@glow/VetoCouncil/VetoCouncil.sol";
import {MockGovernance} from "@glow/testing/MockGovernance.sol";
import {IGovernance} from "@glow/interfaces/IGovernance.sol";
import {TestGCC} from "@glow/testing/TestGCC.sol";
import {HalfLife} from "@glow/libraries/HalfLife.sol";
import {GrantsTreasury} from "@glow/GrantsTreasury.sol";
import {Holding, ClaimHoldingArgs, ISafetyDelay, SafetyDelay} from "@glow/SafetyDelay.sol";
import {UnifapV2Factory} from "@unifapv2/UnifapV2Factory.sol";
import {UnifapV2Router} from "@unifapv2/UnifapV2Router.sol";
import {WETH9} from "@glow/UniswapV2/contracts/test/WETH9.sol";
import {TestUSDG} from "@glow/testing/TestUSDG.sol";
import {USDG} from "@glow/USDG.sol";
import {USDGRedemption} from "@glow/USDGRedemption.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

struct AccountWithPK {
    uint256 privateKey;
    address account;
}

contract USDGRedemptionsBaseTest is Test {
    //--------  CONTRACTS ---------//
    UnifapV2Factory public uniswapFactory;
    WETH9 public weth;
    UnifapV2Router public uniswapRouter;
    MockMinerPoolAndGCA public minerPoolAndGCA;
    TestGLOW public glow;
    MockUSDC public usdc;
    TestUSDG public usdg;
    MockUSDC public grc2;
    MockGovernance public governance;
    TestGCC public gcc;
    GrantsTreasury public grantsTreasury;
    SafetyDelay public holdingContract;
    AccountWithPK[10] public accounts;
    USDGRedemption public redemption;
    uint256 public constant WITHDRAW_DELAY = 2 weeks;

    address public WITHDRAW_GUARDIAN = makeAddr("WithdrawGuardian");

    address public mockImpactCatalyst = address(0x1233918293819389128);

    uint256 public constant NOMINATION_DECIMALS = 12;

    //--------  ADDRESSES ---------//
    address public earlyLiquidity = address(0x2);
    address public vestingContract = address(0x3);
    address public vetoCouncilAddress;
    VetoCouncil public vetoCouncil;
    address public grantsTreasuryAddress = address(0x5);
    address public SIMON;
    uint256 public SIMON_PRIVATE_KEY;
    address public OTHER_VETO_1 = address(0x991);
    address public OTHER_VETO_2 = address(0x992);
    address public OTHER_VETO_3 = address(0x993);
    address public OTHER_VETO_4 = address(0x994);
    address public OTHER_VETO_5 = address(0x995);
    address public grantsRecipient = address(0x4123141);

    address public OTHER_GCA = address(0x7);
    address public OTHER_GCA_2 = address(0x8);
    address public OTHER_GCA_3 = address(0x9);
    address public OTHER_GCA_4 = address(0x10);
    address public carbonCreditAuction = address(0x11);
    address public defaultAddressInWithdraw = address(0x555);
    address public bidder1 = address(0x12);
    address public bidder2 = address(0x13);

    address public usdgOwner = address(0xaaa112);
    address public usdcReceiver = address(0xaaa113);

    address[] public startingAgents;

    //--------  CONSTANTS ---------//
    uint256 public constant ONE_WEEK = 7 * uint256(1 days);
    uint256 public ONE_YEAR = 365 * uint256(1 days);

    address public deployer = tx.origin;

    function setUp() public {
        vm.startPrank(deployer);
        uniswapFactory = new UnifapV2Factory();
        weth = new WETH9();
        uniswapRouter = new UnifapV2Router(address(uniswapFactory));
        //Make sure we don't start at 0
        (SIMON, SIMON_PRIVATE_KEY) = _createAccount(9999, type(uint256).max);
        for (uint256 i = 0; i < 10; i++) {
            (address account, uint256 privateKey) = _createAccount(0x44444 + i, type(uint256).max);
            accounts[i] = AccountWithPK(privateKey, account);
        }
        vm.warp(10);

        usdc = new MockUSDC();
        uint256 deployerNonce = vm.getNonce(deployer);
        address precomputedGlow = computeCreateAddress(deployer, deployerNonce);
        address precomputedGCC = computeCreateAddress(deployer, deployerNonce + 8);

        address precomputedGrantsAddress = computeCreateAddress(deployer, deployerNonce + 3);
        address precomputedVetoCouncilAddress = computeCreateAddress(deployer, deployerNonce + 4);
        address precomputedHoldingContractAddress = computeCreateAddress(deployer, deployerNonce + 5);
        address precomputedMinerPoolAndGCAAddress = computeCreateAddress(deployer, deployerNonce + 6);
        address precomputedImpactCatalyst = computeCreateAddress(precomputedGCC, 1); //since gcc deploys impact catalyst after carbon credit auction
        glow = new TestGLOW(
            earlyLiquidity,
            vestingContract,
            precomputedMinerPoolAndGCAAddress,
            precomputedVetoCouncilAddress,
            precomputedGrantsAddress
        ); //deployerNonce
        governance = new MockGovernance({
            gcc: precomputedGCC,
            gca: precomputedMinerPoolAndGCAAddress,
            vetoCouncil: precomputedVetoCouncilAddress,
            grantsTreasury: precomputedGrantsAddress,
            glw: address(glow)
        }); //deployerNonce + 1
        usdg = new TestUSDG({
            _usdc: address(usdc),
            _usdcReceiver: usdcReceiver,
            _glow: precomputedGlow,
            _gcc: precomputedGCC,
            _holdingContract: precomputedHoldingContractAddress,
            _vetoCouncilContract: precomputedVetoCouncilAddress,
            _impactCatalyst: precomputedImpactCatalyst,
            _owner: usdgOwner,
            _univ2Factory: address(uniswapFactory)
        }); //deployerNonce+2
        address[] memory temp = new address[](1);
        temp[0] = OTHER_VETO_1;
        startingAgents.push(address(SIMON));
        startingAgents.push(OTHER_VETO_1);
        startingAgents.push(OTHER_VETO_2);
        startingAgents.push(OTHER_VETO_3);
        startingAgents.push(OTHER_VETO_4);
        startingAgents.push(OTHER_VETO_5);
        grantsTreasury = new GrantsTreasury(address(glow), address(governance)); //deployerNonce + 3
        grantsTreasuryAddress = address(grantsTreasury);
        vetoCouncil = new VetoCouncil(address(governance), address(glow), startingAgents); //deployerNonce + 4
        vetoCouncilAddress = address(vetoCouncil);
        holdingContract = new SafetyDelay(vetoCouncilAddress, precomputedMinerPoolAndGCAAddress); //deployerNonce + 5

        minerPoolAndGCA = new MockMinerPoolAndGCA( //deployerNonce + 6
            temp,
            address(glow),
            address(governance),
            keccak256("requirementsHash"),
            earlyLiquidity,
            address(usdg),
            vetoCouncilAddress,
            address(holdingContract),
            precomputedGCC
        );

        grc2 = new MockUSDC(); //deployerNonce + 7
        gcc = new TestGCC(
            address(minerPoolAndGCA), address(governance), address(glow), address(usdg), address(uniswapRouter)
        ); //deployerNonce + 8

        vm.stopPrank();

        vm.startPrank(usdgOwner);

        usdc.mint(usdgOwner, 100000000 * 1e6);
        usdc.approve(address(usdg), 100000000 * 1e6);
        usdg.swap(usdgOwner, 100000000 * 1e6);
        vm.stopPrank();
        // seedLP(500 ether, 100000000 * 1e6);

        redemption = new USDGRedemption(usdg, IERC20(address(usdc)), WITHDRAW_GUARDIAN);
    }

    function test_USDGRedemption_setUp() public {}

    function _createAccount(uint256 privateKey, uint256 amount)
        internal
        returns (address addr, uint256 signerPrivateKey)
    {
        addr = vm.addr(privateKey);
        vm.deal(addr, amount);
        signerPrivateKey = privateKey;
        return (addr, signerPrivateKey);
    }

    // function seedLP(uint256 amountGCC, uint256 amountUSDG) public {
    //     vm.startPrank(usdgOwner);
    //     gcc.mint(usdgOwner, amountGCC);
    //     gcc.approve(address(uniswapRouter), amountGCC);
    //     usdg.approve(address(uniswapRouter), amountUSDG);
    //     uniswapRouter.addLiquidity(
    //         address(gcc), address(usdg), amountGCC, amountUSDG, amountGCC, amountUSDG, usdgOwner, block.timestamp
    //     );
    //     vm.stopPrank();
    // }

    /* -------------------------------------------------------------------------- */
    /*                              Helper Functions                              */
    /* -------------------------------------------------------------------------- */


    function _topUp(address provider, uint256 amount) internal {
        usdc.mint(provider, amount);
        vm.prank(provider);
        usdc.transfer(address(redemption),amount);
  
    }

    function _activateCircuitBreaker() internal {
        // Assume SIMON (created in Base) is a council member
        vm.prank(SIMON);
        usdg.freezeContract();
        assertTrue(usdg.permanentlyFreezeTransfers(), "circuit breaker not active");
    }

    function _mintUSDG(address to, uint256 amount) internal {
        // Ensure we never mint zero
        if (amount == 0) return;
        usdc.mint(to, amount);
        vm.startPrank(to);
        usdc.approve(address(usdg), amount);
        usdg.swap(to, amount);
        vm.stopPrank();
    }
}

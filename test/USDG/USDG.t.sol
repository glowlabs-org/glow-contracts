// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

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

struct AccountWithPK {
    uint256 privateKey;
    address account;
}

contract USDGTest is Test {
    //--------  CONTRACTS ---------//
    UnifapV2Factory public uniswapFactory;
    WETH9 public weth;
    UnifapV2Router public uniswapRouter;
    MockMinerPoolAndGCA minerPoolAndGCA;
    TestGLOW glow;
    MockUSDC usdc;
    TestUSDG usdg;
    MockUSDC grc2;
    MockGovernance governance;
    TestGCC gcc;
    GrantsTreasury grantsTreasury;
    SafetyDelay holdingContract;
    AccountWithPK[10] accounts;

    address mockImpactCatalyst = address(0x1233918293819389128);

    uint256 constant NOMINATION_DECIMALS = 12;

    //--------  ADDRESSES ---------//
    address earlyLiquidity = address(0x2);
    address vestingContract = address(0x3);
    address vetoCouncilAddress;
    VetoCouncil vetoCouncil;
    address grantsTreasuryAddress = address(0x5);
    address SIMON;
    uint256 SIMON_PRIVATE_KEY;
    address OTHER_VETO_1 = address(0x991);
    address OTHER_VETO_2 = address(0x992);
    address OTHER_VETO_3 = address(0x993);
    address OTHER_VETO_4 = address(0x994);
    address OTHER_VETO_5 = address(0x995);
    address grantsRecipient = address(0x4123141);

    address OTHER_GCA = address(0x7);
    address OTHER_GCA_2 = address(0x8);
    address OTHER_GCA_3 = address(0x9);
    address OTHER_GCA_4 = address(0x10);
    address carbonCreditAuction = address(0x11);
    address defaultAddressInWithdraw = address(0x555);
    address bidder1 = address(0x12);
    address bidder2 = address(0x13);

    address usdgOwner = address(0xaaa112);
    address usdcReceiver = address(0xaaa113);

    address[] startingAgents;

    //--------  CONSTANTS ---------//
    uint256 constant ONE_WEEK = 7 * uint256(1 days);
    uint256 ONE_YEAR = 365 * uint256(1 days);

    address deployer = tx.origin;

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
        address[] memory temp = new address[](0);
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
        // // usdg.setAllowlistedContracts({
        // //     _glow: address(glow),
        // //     _gcc: address(gcc),
        // //     _holdingContract: address(holdingContract),
        // //     _vetoCouncilContract: vetoCouncilAddress,
        // //     _impactCatalyst: mockImpactCatalyst
        // // });
        usdc.mint(usdgOwner, 100000000 * 1e6);
        usdc.approve(address(usdg), 100000000 * 1e6);
        usdg.swap(usdgOwner, 100000000 * 1e6);
        vm.stopPrank();
        seedLP(500 ether, 100000000 * 1e6);
    }

    function test_contractCannotReceiveUSDG() public {
        vm.startPrank(usdgOwner);
        usdc.mint(usdgOwner, 100000000 * 1e6);
        usdc.approve(address(usdg), 100000000 * 1e6);
        usdg.swap(usdgOwner, 100000000 * 1e6);

        vm.expectRevert(USDG.ErrIsContract.selector);
        usdg.transfer(address(this), 1 * 1e6);
        vm.stopPrank();
    }

    function test_contractCannotSwapUSDG_andSendToContract() public {
        address me = address(usdc); // a non-allowlisted contract
        vm.startPrank(me);
        usdc.mint(me, 100000000 * 1e6);
        usdc.approve(address(usdg), 100000000 * 1e6);
        vm.expectRevert(USDG.ErrIsContract.selector);
        usdg.swap(me, 100000000 * 1e6);
        vm.stopPrank();
    }

    function test_EOA_cannotSwap_andSendToContract() public {
        address me = address(usdgOwner); // a non-allowlisted contract
        vm.startPrank(me);
        usdc.mint(me, 100000000 * 1e6);
        usdc.approve(address(usdg), 100000000 * 1e6);
        vm.expectRevert(USDG.ErrIsContract.selector);
        usdg.swap(address(usdc), 100000000 * 1e6);
        vm.stopPrank();
    }

    function test_EOA_canSendAndReceive() public {
        address me = address(usdgOwner); // a non-allowlisted contract
        address other = address(0x123);
        vm.startPrank(me);
        usdc.mint(me, 100000000 * 1e6);
        usdc.approve(address(usdg), 100000000 * 1e6);
        usdg.swap(me, 100000000 * 1e6);
        usdg.transfer(other, 1 * 1e6);
        vm.stopPrank();

        vm.startPrank(other);
        usdg.transfer(me, 1 * 1e6);
        vm.stopPrank();
    }

    function test_swapZeroAmountShouldRevert() public {
        address me = address(usdgOwner); // a non-allowlisted contract
        address other = address(0x123);
        vm.startPrank(me);
        usdc.mint(me, 100000000 * 1e6);
        usdc.approve(address(usdg), 100000000 * 1e6);
        vm.expectRevert(USDG.ErrCannotSwapZero.selector);
        usdg.swap(me, 0);
    }

    function test_freezeContract_shouldWork() public {
        vm.startPrank(OTHER_VETO_1);
        usdg.freezeContract();
        vm.stopPrank();
    }

    function test_freezeContract_notVetoCouncilMember_shouldRevert() public {
        vm.startPrank(usdgOwner);
        vm.expectRevert(USDG.ErrNotVetoCouncilMember.selector);
        usdg.freezeContract();
        vm.stopPrank();
    }

    function test_freezeContract_shouldRevert_allTransfers() public {
        test_freezeContract_shouldWork();
        vm.startPrank(usdgOwner);
        vm.expectRevert(USDG.ErrPermanentlyFrozen.selector);
        usdg.transfer(address(this), 1 * 1e6);
        vm.stopPrank();
    }

    function test_freezeContract_shouldRevert_swap() public {
        test_freezeContract_shouldWork();
        vm.startPrank(usdgOwner);
        usdc.mint(usdgOwner, 100000000 * 1e6);
        usdc.approve(address(usdg), 100000000 * 1e6);
        vm.expectRevert(USDG.ErrPermanentlyFrozen.selector);
        usdg.swap(address(this), 1 * 1e6);
        vm.stopPrank();
    }

    function _createAccount(uint256 privateKey, uint256 amount)
        internal
        returns (address addr, uint256 signerPrivateKey)
    {
        addr = vm.addr(privateKey);
        vm.deal(addr, amount);
        signerPrivateKey = privateKey;
        return (addr, signerPrivateKey);
    }

    function seedLP(uint256 amountGCC, uint256 amountUSDG) public {
        vm.startPrank(usdgOwner);
        gcc.mint(usdgOwner, amountGCC);
        gcc.approve(address(uniswapRouter), amountGCC);
        usdg.approve(address(uniswapRouter), amountUSDG);
        uniswapRouter.addLiquidity(
            address(gcc), address(usdg), amountGCC, amountUSDG, amountGCC, amountUSDG, usdgOwner, block.timestamp
        );
        vm.stopPrank();
    }
}

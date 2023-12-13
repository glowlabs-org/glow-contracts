// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@/testing/TestGCC.sol";
import "forge-std/console.sol";
import {IGCA} from "@/interfaces/IGCA.sol";
import {MockGCA} from "@/MinerPoolAndGCA/mock/MockGCA.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CarbonCreditDutchAuction} from "@/CarbonCreditDutchAuction.sol";
import "forge-std/StdUtils.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {TestGLOW} from "@/testing/TestGLOW.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MerkleProofLib} from "@solady/utils/MerkleProofLib.sol";
import {MockMinerPoolAndGCA} from "@/MinerPoolAndGCA/mock/MockMinerPoolAndGCA.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";
import {IMinerPool} from "@/interfaces/IMinerPool.sol";
import {BucketSubmission} from "@/MinerPoolAndGCA/BucketSubmission.sol";
import {VetoCouncil} from "@/VetoCouncil.sol";
import {MockGovernance} from "@/testing/MockGovernance.sol";
import {IGovernance} from "@/interfaces/IGovernance.sol";
import {TestGCC} from "@/testing/TestGCC.sol";
import {HalfLife} from "@/libraries/HalfLife.sol";
import {GrantsTreasury} from "@/GrantsTreasury.sol";
import {Holding, ClaimHoldingArgs, IHoldingContract, HoldingContract} from "@/HoldingContract.sol";
import {UnifapV2Factory} from "@unifapv2/UnifapV2Factory.sol";
import {UnifapV2Router} from "@unifapv2/UnifapV2Router.sol";
import {WETH9} from "@/UniswapV2/contracts/test/WETH9.sol";
import {TestUSDG} from "@/testing/TestUSDG.sol";
import {USDG} from "@/USDG.sol";

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
    HoldingContract holdingContract;
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

    function setUp() public {
        uniswapFactory = new UnifapV2Factory();
        weth = new WETH9();
        uniswapRouter = new UnifapV2Router(address(uniswapFactory));
        //Make sure we don't start at 0
        governance = new MockGovernance();
        (SIMON, SIMON_PRIVATE_KEY) = _createAccount(9999, type(uint256).max);
        for (uint256 i = 0; i < 10; i++) {
            (address account, uint256 privateKey) = _createAccount(0x44444 + i, type(uint256).max);
            accounts[i] = AccountWithPK(privateKey, account);
        }
        vm.warp(10);
        usdc = new MockUSDC();
        usdg = new TestUSDG({
            _usdc: address(usdc),
            _usdcReceiver: usdcReceiver,
            _owner: usdgOwner,
            _univ2Factory: address(uniswapFactory)
        });

        glow = new TestGLOW(earlyLiquidity,vestingContract);
        address[] memory temp = new address[](0);
        startingAgents.push(address(SIMON));
        startingAgents.push(OTHER_VETO_1);
        startingAgents.push(OTHER_VETO_2);
        startingAgents.push(OTHER_VETO_3);
        startingAgents.push(OTHER_VETO_4);
        startingAgents.push(OTHER_VETO_5);
        grantsTreasury = new GrantsTreasury(address(glow), address(governance));
        grantsTreasuryAddress = address(grantsTreasury);
        vetoCouncil = new VetoCouncil(address(governance), address(glow),startingAgents);
        vetoCouncilAddress = address(vetoCouncil);
        holdingContract = new HoldingContract(vetoCouncilAddress);

        minerPoolAndGCA =
        new MockMinerPoolAndGCA(temp,address(glow),address(governance),keccak256("requirementsHash"),earlyLiquidity,address(usdg),vetoCouncilAddress,address(holdingContract));
        glow.setContractAddresses(address(minerPoolAndGCA), vetoCouncilAddress, grantsTreasuryAddress);
        grc2 = new MockUSDC();
        gcc =
        new TestGCC( address(minerPoolAndGCA), address(governance),address(glow),address(usdg),address(uniswapRouter));
        // governance.setContractAddresses(gcc, gca, vetoCouncil, grantsTreasury, glw);
        governance.setContractAddresses(
            address(gcc), address(minerPoolAndGCA), vetoCouncilAddress, grantsTreasuryAddress, address(glow)
        );

        vm.startPrank(usdgOwner);
        usdg.setAllowlistedContracts({
            _glow: address(glow),
            _gcc: address(gcc),
            _holdingContract: address(holdingContract),
            _vetoCouncilContract: vetoCouncilAddress,
            _impactCatalyst: mockImpactCatalyst
        });
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

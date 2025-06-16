// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "@/testing/TestGCC.sol";
import "forge-std/console.sol";
import {IGCA} from "@/interfaces/IGCA.sol";
import {MockGCA} from "@/MinerPoolAndGCA/mock/MockGCA.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import "forge-std/StdUtils.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {TestGLOW} from "@/testing/TestGLOW.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MerkleProofLib} from "@solady/utils/MerkleProofLib.sol";
import {MockMinerPoolAndGCA} from "@/MinerPoolAndGCA/mock/MockMinerPoolAndGCA.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";
import {IMinerPool} from "@/interfaces/IMinerPool.sol";
import {BucketSubmission} from "@/MinerPoolAndGCA/BucketSubmission.sol";
import {VetoCouncil} from "@/VetoCouncil/VetoCouncil.sol";
import {MockGovernance} from "@/testing/MockGovernance.sol";
import {IGovernance} from "@/interfaces/IGovernance.sol";
import {TestGCC} from "@/testing/TestGCC.sol";
import {HalfLife} from "@/libraries/HalfLife.sol";
import {GrantsTreasury} from "@/GrantsTreasury.sol";
import {Holding, ClaimHoldingArgs, ISafetyDelay, SafetyDelay} from "@/SafetyDelay.sol";
import {UnifapV2Factory} from "@unifapv2/UnifapV2Factory.sol";
import {UnifapV2Router} from "@unifapv2/UnifapV2Router.sol";
import {WETH9} from "@/UniswapV2/contracts/test/WETH9.sol";
import {TestUSDGGuardedLaunchV2 as TestUSDG} from "@/testing/TestUSDGV2.GuardedLaunch.sol";
import {USDG} from "@/USDG.sol";
import {USDGGuardedLaunchV2} from "@/GuardedLaunchV2/USDG.GuardedLaunchV2.sol";

struct AccountWithPK {
    uint256 privateKey;
    address account;
}

contract USDGGuardedLaunchV2Test is Test {
    //--------  CONTRACTS ---------//
    UnifapV2Factory public uniswapFactory;
    WETH9 public weth;
    UnifapV2Router public uniswapRouter;
    MockMinerPoolAndGCA internal minerPoolAndGCA;
    TestGLOW internal glow;
    MockUSDC internal usdc;
    TestUSDG internal usdg;
    MockUSDC internal grc2;
    MockGovernance internal governance;
    TestGCC internal gcc;
    GrantsTreasury internal grantsTreasury;
    SafetyDelay internal holdingContract;
    AccountWithPK[10] internal accounts;

    address mockImpactCatalyst = address(0x1233918293819389128);

    uint256 constant USDG_TO_SEND_TO_MIGRATION_CONTRACT = 10000000 ether;

    uint256 constant NOMINATION_DECIMALS = 12;

    //--------  ADDRESSES ---------//
    address internal earlyLiquidity = address(0x2);
    address internal vestingContract = address(0x3);
    address internal vetoCouncilAddress;
    VetoCouncil internal vetoCouncil;
    address internal grantsTreasuryAddress = address(0x5);
    address internal SIMON;
    uint256 internal SIMON_PRIVATE_KEY;
    address internal constant OTHER_VETO_1 = address(0x991);
    address internal constant OTHER_VETO_2 = address(0x992);
    address internal constant OTHER_VETO_3 = address(0x993);
    address internal constant OTHER_VETO_4 = address(0x994);
    address internal constant OTHER_VETO_5 = address(0x995);
    address internal grantsRecipient = address(0x4123141);

    address internal constant OTHER_GCA = address(0x7);
    address internal constant OTHER_GCA_2 = address(0x8);
    address internal constant OTHER_GCA_3 = address(0x9);
    address internal constant OTHER_GCA_4 = address(0x10);
    address internal carbonCreditAuction = address(0x11);
    address internal defaultAddressInWithdraw = address(0x555);
    address internal bidder1 = address(0x12);
    address internal bidder2 = address(0x13);

    address internal usdgOwner = address(0xaaa112);
    address internal usdcReceiver = address(0xaaa113);
    address internal migrationContract = address(0xaaa114);

    address[] public startingAgents;

    //--------  CONSTANTS ---------//
    uint256 internal constant ONE_WEEK = 7 * uint256(1 days);
    uint256 internal constant ONE_YEAR = 365 * uint256(1 days);

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

        address precomputedGrantsAddress = computeCreateAddress(deployer, deployerNonce + 4);
        address precomputedVetoCouncilAddress = computeCreateAddress(deployer, deployerNonce + 5);
        address precomputedHoldingContractAddress = computeCreateAddress(deployer, deployerNonce + 6);
        address precomputedMinerPoolAndGCAAddress = computeCreateAddress(deployer, deployerNonce + 7);
        address precomputedGovernance = computeCreateAddress(deployer, deployerNonce + 2);
        address precomputedUSDG = computeCreateAddress(deployer, deployerNonce + 3);
        glow = new TestGLOW(
            earlyLiquidity,
            vestingContract,
            precomputedMinerPoolAndGCAAddress,
            precomputedVetoCouncilAddress,
            precomputedGrantsAddress
        ); //deployerNonce

        gcc = new TestGCC(
            address(minerPoolAndGCA),
            address(precomputedGovernance),
            address(glow),
            address(precomputedUSDG),
            address(uniswapRouter)
        ); //deployerNonce + 1

        address precomputedImpactCatalyst = computeCreateAddress(address(gcc), 1); //since gcc deploys impact catalyst after carbon credit auction

        governance = new MockGovernance({
            gcc: address(gcc),
            gca: precomputedMinerPoolAndGCAAddress,
            vetoCouncil: precomputedVetoCouncilAddress,
            grantsTreasury: precomputedGrantsAddress,
            glw: address(glow)
        }); //deployerNonce + 2

        address[] memory temp = new address[](0);
        bytes memory migrationContractAndAmountEncoded =
            abi.encode(migrationContract, USDG_TO_SEND_TO_MIGRATION_CONTRACT);
        usdg = new TestUSDG({
            _usdc: address(usdc),
            _usdcReceiver: usdcReceiver,
            _glow: precomputedGlow,
            _gcc: address(gcc),
            _holdingContract: precomputedHoldingContractAddress,
            _vetoCouncilContract: precomputedVetoCouncilAddress,
            _impactCatalyst: precomputedImpactCatalyst,
            _owner: usdgOwner,
            _univ2Factory: address(uniswapFactory),
            _allowlistedMultisigContracts: temp,
            _migrationContractAndAmount: migrationContractAndAmountEncoded
        }); //deployerNonce+3

        startingAgents.push(address(SIMON));
        startingAgents.push(OTHER_VETO_1);
        startingAgents.push(OTHER_VETO_2);
        startingAgents.push(OTHER_VETO_3);
        startingAgents.push(OTHER_VETO_4);
        startingAgents.push(OTHER_VETO_5);
        grantsTreasury = new GrantsTreasury(address(glow), address(governance)); //deployerNonce + 4
        grantsTreasuryAddress = address(grantsTreasury);
        vetoCouncil = new VetoCouncil(address(governance), address(glow), startingAgents); //deployerNonce + 5
        vetoCouncilAddress = address(vetoCouncil);
        holdingContract = new SafetyDelay(vetoCouncilAddress, precomputedMinerPoolAndGCAAddress); //deployerNonce + 6

        minerPoolAndGCA = new MockMinerPoolAndGCA( //deployerNonce + 7
            temp,
            address(glow),
            address(governance),
            keccak256("requirementsHash"),
            earlyLiquidity,
            address(usdg),
            vetoCouncilAddress,
            address(holdingContract),
            address(gcc)
        );

        grc2 = new MockUSDC(); //deployerNonce + 8

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

        usdc.mint(address(usdg), USDG_TO_SEND_TO_MIGRATION_CONTRACT);
    }

    function test_v2_contractCannotReceiveUSDG() public {
        vm.startPrank(usdgOwner);
        usdc.mint(usdgOwner, 100000000 * 1e6);
        usdc.approve(address(usdg), 100000000 * 1e6);
        usdg.swap(usdgOwner, 100000000 * 1e6);

        vm.expectRevert(USDG.ErrIsContract.selector);
        usdg.transfer(address(this), 1 * 1e6);
        vm.stopPrank();
    }

    function test_v2_contractCannotSwapUSDG_andSendToContract() public {
        address me = address(usdc); // a non-allowlisted contract
        vm.startPrank(me);
        usdc.mint(me, 100000000 * 1e6);
        usdc.approve(address(usdg), 100000000 * 1e6);
        vm.expectRevert(USDG.ErrIsContract.selector);
        usdg.swap(me, 100000000 * 1e6);
        vm.stopPrank();
    }

    function test_v2_EOA_cannotSwap_andSendToContract() public {
        address me = address(usdgOwner); // a non-allowlisted contract
        vm.startPrank(me);
        usdc.mint(me, 100000000 * 1e6);
        usdc.approve(address(usdg), 100000000 * 1e6);
        vm.expectRevert(USDG.ErrIsContract.selector);
        usdg.swap(address(usdc), 100000000 * 1e6);
        vm.stopPrank();
    }

    function test_v2_EOA_canSendAndReceive() public {
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

    function test_v2_swapZeroAmountShouldRevert() public {
        address me = address(usdgOwner); // a non-allowlisted contract
        address other = address(0x123);
        vm.startPrank(me);
        usdc.mint(me, 100000000 * 1e6);
        usdc.approve(address(usdg), 100000000 * 1e6);
        vm.expectRevert(USDG.ErrCannotSwapZero.selector);
        usdg.swap(me, 0);
    }

    function test_v2_freezeContract_shouldWork() public {
        vm.startPrank(OTHER_VETO_1);
        usdg.freezeContract();
        vm.stopPrank();
    }

    function test_v2_freezeContract_notVetoCouncilMember_shouldRevert() public {
        vm.startPrank(usdgOwner);
        vm.expectRevert(USDG.ErrNotVetoCouncilMember.selector);
        usdg.freezeContract();
        vm.stopPrank();
    }

    function test_v2_freezeContract_shouldRevert_allTransfers() public {
        test_v2_freezeContract_shouldWork();
        vm.startPrank(usdgOwner);
        vm.expectRevert(USDG.ErrPermanentlyFrozen.selector);
        usdg.transfer(address(this), 1 * 1e6);
        vm.stopPrank();
    }

    function test_v2_freezeContract_shouldRevert_swap() public {
        test_v2_freezeContract_shouldWork();
        vm.startPrank(usdgOwner);
        usdc.mint(usdgOwner, 100000000 * 1e6);
        usdc.approve(address(usdg), 100000000 * 1e6);
        vm.expectRevert(USDG.ErrPermanentlyFrozen.selector);
        usdg.swap(address(this), 1 * 1e6);
        vm.stopPrank();
    }

    function test_v2_migrationContract_shouldReceiveBalance() public {
        uint256 migrationContractBalance = usdg.balanceOf(migrationContract);
        assertEq(
            migrationContractBalance,
            USDG_TO_SEND_TO_MIGRATION_CONTRACT,
            "Migration contract should have the USDG balance"
        );
    }

    function test_v2_depositQueue_shouldSetState() public {
        address me = address(0xffffffffaaaafffff);
        uint256 amountToSend = 100 * 1e6;
        vm.startPrank(migrationContract);
        usdg.transfer(me, amountToSend);
        vm.stopPrank();

        vm.startPrank(me);
        usdg.depositUSDCToWithdrawalQueue(uint192(amountToSend));
        USDGGuardedLaunchV2.USDCWithdrawal memory withdrawal = usdg.usdcWithdrawalQueue(me);
        assertEq(withdrawal.amount, uint192(amountToSend));
        assertEq(withdrawal.expirationTimestamp, uint64(block.timestamp + 2 weeks));
        vm.stopPrank();
        //transfer to
    }

    function testFuzz_tryingToClaimBeforeExpiration_shouldRevert(uint256 timeToWarpForward) public {
        timeToWarpForward = timeToWarpForward % (2 weeks);
        address me = address(0xffffffffaaaafffff);
        uint256 amountToSend = 100 * 1e6;
        vm.startPrank(migrationContract);
        usdg.transfer(me, amountToSend);
        vm.stopPrank();

        vm.startPrank(me);
        usdg.depositUSDCToWithdrawalQueue(uint192(amountToSend));
        USDGGuardedLaunchV2.USDCWithdrawal memory withdrawal = usdg.usdcWithdrawalQueue(me);
        assertEq(withdrawal.amount, uint192(amountToSend));
        assertEq(withdrawal.expirationTimestamp, uint64(block.timestamp + 2 weeks));

        vm.warp(block.timestamp + timeToWarpForward);
        vm.expectRevert(USDGGuardedLaunchV2.ClaimNotAvailableYet.selector);
        usdg.claimUSDCFromWithdrawalQueue();
        vm.stopPrank();
    }

    function testFuzz_tryingToClaimAfterExpirationTimestamp_shouldWork(uint48 timeToWarpForward, uint256 amountToSend)
        public
    {
        if (timeToWarpForward < 2 weeks) {
            timeToWarpForward = 2 weeks;
        }
        address me = address(0xffffffffaaaafffff);
        if (amountToSend == 0) {
            amountToSend = 1;
        }

        amountToSend = amountToSend % (USDG_TO_SEND_TO_MIGRATION_CONTRACT);
        vm.startPrank(migrationContract);
        usdg.transfer(me, uint256(amountToSend));
        vm.stopPrank();

        vm.startPrank(me);
        usdg.depositUSDCToWithdrawalQueue(uint192(amountToSend));
        USDGGuardedLaunchV2.USDCWithdrawal memory withdrawal = usdg.usdcWithdrawalQueue(me);
        assertEq(withdrawal.amount, uint192(amountToSend));
        assertEq(withdrawal.expirationTimestamp, uint64(block.timestamp + 2 weeks));

        vm.warp(block.timestamp + timeToWarpForward);
        usdg.claimUSDCFromWithdrawalQueue();
        vm.stopPrank();

        //Check the balances
        uint256 balance = usdc.balanceOf(me);
        assertEq(balance, amountToSend, "Balance should be the same as the amount sent");

        withdrawal = usdg.usdcWithdrawalQueue(me);
        assertEq(withdrawal.amount, uint192(0), "Amount should be 0");
        assertEq(withdrawal.expirationTimestamp, uint64(0), "Expiration timestamp should be 0");

        //Try to claim again should revert with NoUSDCToClaim

        vm.startPrank(me);
        vm.expectRevert(USDGGuardedLaunchV2.NoUSDCToClaim.selector);
        usdg.claimUSDCFromWithdrawalQueue();
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

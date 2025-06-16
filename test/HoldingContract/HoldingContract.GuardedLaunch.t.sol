// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import "forge-std/console.sol";
import {IGCA} from "@glow/interfaces/IGCA.sol";
import {MockGCA} from "@glow/MinerPoolAndGCA/mock/MockGCA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Governance} from "@glow/Governance.sol";
import {CarbonCreditDescendingPriceAuction} from "@glow/CarbonCreditDescendingPriceAuction.sol";
import "forge-std/StdUtils.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {TestGLOWGuardedLaunch} from "@glow/testing/GuardedLaunch/TestGLOW.GuardedLaunch.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MerkleProofLib} from "@solady/utils/MerkleProofLib.sol";
import {MockMinerPoolAndGCA} from "@glow/MinerPoolAndGCA/mock/MockMinerPoolAndGCA.sol";
import {MockUSDC} from "@glow/testing/MockUSDC.sol";
import {IMinerPool} from "@glow/interfaces/IMinerPool.sol";
import {BucketSubmission} from "@glow/MinerPoolAndGCA/BucketSubmission.sol";
import {VetoCouncil} from "@glow/VetoCouncil/VetoCouncil.sol";
import {Holding, ClaimHoldingArgs, ISafetyDelay, SafetyDelay} from "@glow/SafetyDelay.sol";
import {UnifapV2Factory} from "@unifapv2/UnifapV2Factory.sol";
import {UnifapV2Router} from "@unifapv2/UnifapV2Router.sol";
import {WETH9} from "@glow/UniswapV2/contracts/test/WETH9.sol";
import {TestUSDG} from "@glow/testing/TestUSDG.sol";

struct ClaimLeaf {
    address payoutWallet;
    uint256 glwWeight;
    uint256 grcWeight;
}

contract HoldingContractGuardedLaunchTest is Test {
    //--------  CONTRACTS ---------//
    MockMinerPoolAndGCA minerPoolAndGCA;
    TestGLOWGuardedLaunch glow;
    MockUSDC usdc;

    MockUSDC grc2;
    SafetyDelay holdingContract;
    UnifapV2Factory public uniswapFactory;
    WETH9 public weth;
    UnifapV2Router public uniswapRouter;
    TestUSDG public usdg;

    //--------  ADDRESSES ---------//
    address governance = address(0x1);
    address earlyLiquidity = address(0x2);
    address vestingContract = address(0x3);
    address vetoCouncilAddress;
    VetoCouncil vetoCouncil;
    address grantsTreasuryAddress = address(0x5);
    address SIMON;
    uint256 SIMON_PRIVATE_KEY;

    address VETO_COUNCIL_MEMBER = address(0x7);
    address OTHER_GCA_2 = address(0x8);
    address OTHER_GCA_3 = address(0x9);
    address OTHER_GCA_4 = address(0x10);
    address carbonCreditAuction = address(0x11);
    address defaultAddressInWithdraw;
    uint256 defaultAddressPrivateKey;
    address bidder1 = address(0x12);
    address bidder2 = address(0x13);

    uint256 NINETY_DAYS = uint256(90 days);

    address usdgOwner = address(0xaaa112);
    address usdcReceiver = address(0xaaa113);

    //--------  CONSTANTS ---------//
    uint256 constant ONE_WEEK = 7 * uint256(1 days);

    address deployer = tx.origin;

    function setUp() public {
        //Make sure we don't start at 0
        FakeGCC fakeGCC = new FakeGCC();
        vm.startPrank(deployer);
        (SIMON, SIMON_PRIVATE_KEY) = _createAccount(9999, type(uint256).max);
        vm.warp(10);
        usdc = new MockUSDC();
        uniswapFactory = new UnifapV2Factory();
        weth = new WETH9();
        uniswapRouter = new UnifapV2Router(address(uniswapFactory));
        usdc = new MockUSDC();

        uint256 deployerNonce = vm.getNonce(deployer);
        address precomputedMinerPool = computeCreateAddress(deployer, deployerNonce + 4);
        address precomputedVetoCouncil = computeCreateAddress(deployer, deployerNonce + 2);
        address precomputedHoldingContract = computeCreateAddress(deployer, deployerNonce + 3);
        address precomputedUSDG = computeCreateAddress(deployer, deployerNonce + 1);
        glow = new TestGLOWGuardedLaunch({
            _earlyLiquidityAddress: earlyLiquidity,
            _vestingContract: vestingContract,
            _gcaAndMinerPoolAddress: precomputedMinerPool,
            _vetoCouncilAddress: precomputedVetoCouncil,
            _grantsTreasuryAddress: grantsTreasuryAddress,
            _owner: SIMON,
            _usdg: address(precomputedUSDG),
            _uniswapV2Factory: address(uniswapFactory),
            _gccContract: address(fakeGCC)
        }); //deployerNonce
        usdg = new TestUSDG({
            _usdc: address(usdc),
            _usdcReceiver: usdcReceiver,
            _owner: usdgOwner,
            _univ2Factory: address(uniswapFactory),
            _gcc: address(fakeGCC),
            _glow: address(glow),
            _holdingContract: address(precomputedHoldingContract),
            _vetoCouncilContract: address(precomputedVetoCouncil),
            _impactCatalyst: address(0x1) //doesent matter for this test
        }); //deployerNonce + 1
        (defaultAddressInWithdraw, defaultAddressPrivateKey) = _createAccount(2313141231, type(uint256).max);

        address[] memory temp = new address[](0);
        address[] memory startingAgents = new address[](2);
        startingAgents[0] = address(SIMON);
        startingAgents[1] = address(VETO_COUNCIL_MEMBER);
        vetoCouncil = new VetoCouncil(governance, address(glow), startingAgents); //deployerNonce + 2
        vetoCouncilAddress = address(vetoCouncil);
        holdingContract = new SafetyDelay(vetoCouncilAddress, precomputedMinerPool); //deployerNonce + 3
        minerPoolAndGCA = new MockMinerPoolAndGCA( //deployerNonce + 4
            temp,
            address(glow),
            governance,
            keccak256("requirementsHash"),
            earlyLiquidity,
            address(usdc),
            vetoCouncilAddress,
            address(holdingContract),
            address(fakeGCC)
        );
        vm.stopPrank();
        vm.startPrank(SIMON);
        //TODO: set these addresses
        // glow.setContractAddresses(address(minerPoolAndGCA), vetoCouncilAddress, grantsTreasuryAddress);
        vm.stopPrank();

        grc2 = new MockUSDC();
    }

    //-------- ISSUING REPORTS ---------//
    function addGCA(address newGCA) public {
        address[] memory allGCAs = minerPoolAndGCA.allGcas();
        address[] memory temp = new address[](allGCAs.length + 1);
        for (uint256 i; i < allGCAs.length; ++i) {
            temp[i] = allGCAs[i];
            if (allGCAs[i] == newGCA) {
                return;
            }
        }
        temp[allGCAs.length] = newGCA;
        minerPoolAndGCA.setGCAs(temp);
        allGCAs = minerPoolAndGCA.allGcas();
    }

    function mintToHoldingContract(address token, uint256 amount) public {
        MockUSDC(token).mint(address(holdingContract), amount);
    }

    function test_addHolding_callerNotMinerPool_shouldRevert() public {
        mintToHoldingContract(address(usdc), 1_000_000_000 ether);
        vm.startPrank(address(0xdaaaaaf));
        vm.expectRevert(SafetyDelay.OnlyMinerPoolCanAddHoldings.selector);
        holdingContract.addHolding(SIMON, address(usdc), 10 ether);
        vm.stopPrank();
    }

    function test_claimFromHoldingContract_beforeHoldingExpiration_shouldRevert() public {
        mintToHoldingContract(address(usdc), 1_000_000_000 ether);
        vm.startPrank(address(minerPoolAndGCA));
        holdingContract.addHolding(SIMON, address(usdc), 10 ether);
        vm.stopPrank();

        vm.startPrank(SIMON);
        vm.expectRevert(SafetyDelay.WithdrawalNotReady.selector);
        holdingContract.claimHoldingSingleton(SIMON, address(usdc));
        vm.stopPrank();
    }

    function test_claimFromHoldingContract_claimingAfterExpiration_shoudClaim() public {
        mintToHoldingContract(address(usdc), 1_000_000_000 ether);
        vm.startPrank(address(minerPoolAndGCA));
        holdingContract.addHolding(SIMON, address(usdc), 10 ether);
        vm.stopPrank();

        vm.startPrank(SIMON);
        vm.warp(block.timestamp + ONE_WEEK);
        holdingContract.claimHoldingSingleton(SIMON, address(usdc));
        vm.stopPrank();

        assertEq(usdc.balanceOf(SIMON), 10 ether);
    }

    function test_delayNetwork_callerNotVetoCouncilMember_shouldRevert() public {
        vm.startPrank(address(0xaaaaaaaaadfffffff));
        vm.expectRevert(SafetyDelay.CallerMustBeVetoCouncilMember.selector);
        holdingContract.delayNetwork();
        vm.stopPrank();
    }

    function test_delayNetwork_callerIsVetoCouncilMember_shouldWork() public {
        uint256 originalTimestamp = block.timestamp;
        vm.startPrank(SIMON);
        holdingContract.delayNetwork();
        vm.stopPrank();
        uint256 newTimestamp = holdingContract.minimumWithdrawTimestamp();
        assert(originalTimestamp + holdingContract.VETO_HOLDING_DELAY() == newTimestamp);
    }

    function test_delayNetworkTwice_whileOnCooldown_shouldRevert() public {
        uint256 originalTimestamp = block.timestamp;
        vm.startPrank(SIMON);
        holdingContract.delayNetwork();
        uint256 newTimestamp = holdingContract.minimumWithdrawTimestamp();
        assert(originalTimestamp + holdingContract.VETO_HOLDING_DELAY() == newTimestamp);

        vm.expectRevert(SafetyDelay.DelayStillOnCooldown.selector);
        holdingContract.delayNetwork();

        //warp forward 79 days
        uint256 minimumWaitPeriod = holdingContract.VETO_HOLDING_DELAY() - holdingContract.FIVE_WEEKS() - 1;
        vm.warp(block.timestamp + minimumWaitPeriod);
        vm.expectRevert(SafetyDelay.DelayStillOnCooldown.selector);
        holdingContract.delayNetwork();

        vm.stopPrank();
    }

    function test_delayNetworkTwice_noLongerOnCooldown_shouldWork() public {
        test_delayNetworkTwice_whileOnCooldown_shouldRevert();
        //Warping one more day should work

        vm.startPrank(SIMON);
        vm.warp(block.timestamp + 1);
        holdingContract.delayNetwork();

        vm.stopPrank();
    }

    function test_claimHolding_networkFrozen_lt97Days_shouldRevert() public {
        mintToHoldingContract(address(usdc), 1_000_000_000 ether);
        vm.startPrank(address(minerPoolAndGCA));
        holdingContract.addHolding(SIMON, address(usdc), 10 ether);
        vm.stopPrank();

        uint256 originalTimestamp = block.timestamp;
        vm.startPrank(SIMON);
        holdingContract.delayNetwork();
        uint256 newTimestamp = holdingContract.minimumWithdrawTimestamp();
        assert(originalTimestamp + holdingContract.VETO_HOLDING_DELAY() == newTimestamp);

        //Warp past the expiration on the holding
        vm.warp(block.timestamp + 8 days);
        vm.expectRevert(SafetyDelay.NetworkIsFrozen.selector);
        holdingContract.claimHoldingSingleton(SIMON, address(usdc));
        vm.stopPrank();
    }

    function test_claimHolding_networkFrozen_gt97Days_shouldWork() public {
        mintToHoldingContract(address(usdc), 1_000_000_000 ether);
        vm.startPrank(address(minerPoolAndGCA));
        holdingContract.addHolding(SIMON, address(usdc), 10 ether);
        vm.stopPrank();

        uint256 originalTimestamp = block.timestamp;
        vm.startPrank(SIMON);
        holdingContract.delayNetwork();
        uint256 newTimestamp = holdingContract.minimumWithdrawTimestamp();
        assert(originalTimestamp + holdingContract.VETO_HOLDING_DELAY() == newTimestamp);

        //Warp past the expiration on the holding
        vm.warp(block.timestamp + 97.1 days);
        holdingContract.claimHoldingSingleton(SIMON, address(usdc));
        vm.stopPrank();
    }

    function test_claimHoldingArgs_networkDelay_shouldRevert() public {
        addHolding(address(0x1), 10 ether);
        addHolding(address(0x2), 10 ether);

        ClaimHoldingArgs[] memory args = new ClaimHoldingArgs[](2);
        args[0] = ClaimHoldingArgs({user: address(0x1), token: address(usdc)});
        args[1] = ClaimHoldingArgs({user: address(0x2), token: address(usdc)});

        vm.startPrank(SIMON);
        holdingContract.delayNetwork();
        vm.stopPrank();

        vm.warp(block.timestamp + ONE_WEEK);

        vm.expectRevert(SafetyDelay.NetworkIsFrozen.selector);
        holdingContract.claimHoldings(args);
    }

    function test_claimHoldingArgs_networkDelay_gt97DaysExpiration_shouldClaim() public {
        addHolding(address(0x1), 10 ether);
        addHolding(address(0x2), 10 ether);

        ClaimHoldingArgs[] memory args = new ClaimHoldingArgs[](2);
        args[0] = ClaimHoldingArgs({user: address(0x1), token: address(usdc)});
        args[1] = ClaimHoldingArgs({user: address(0x2), token: address(usdc)});

        vm.startPrank(SIMON);
        holdingContract.delayNetwork();
        vm.stopPrank();

        vm.warp(block.timestamp + 97.1 days);
        holdingContract.claimHoldings(args);
    }

    function testFuzz_claimBefore7Days_shouldAlwaysFail(uint256 secondsToWarp) public {
        vm.assume(secondsToWarp < 7 days);
        addHolding(address(0x1), 10 ether);
        vm.expectRevert(SafetyDelay.WithdrawalNotReady.selector);
        holdingContract.claimHoldingSingleton(address(0x1), address(usdc));
    }

    function testFuzz_claimAfter7Days_shouldAlwaysWork(uint256 secondsToWarp) public {
        vm.assume(secondsToWarp >= 7 days);
        addHolding(address(0x1), 10 ether);
        vm.expectRevert(SafetyDelay.WithdrawalNotReady.selector);
        holdingContract.claimHoldingSingleton(address(0x1), address(usdc));
    }

    function testFuzz_claimBefore97Days_networkFrozen_shouldRevert(uint256 secondsToWarp) public {
        vm.assume(secondsToWarp < 90 days);
        addHolding(address(0x1), 10 ether);
        vm.warp(block.timestamp + 1 weeks);
        vm.startPrank(SIMON);
        holdingContract.delayNetwork();
        vm.stopPrank();
        vm.warp(block.timestamp + secondsToWarp);
        vm.expectRevert(SafetyDelay.NetworkIsFrozen.selector);
        holdingContract.claimHoldingSingleton(address(0x1), address(usdc));
    }

    function testFuzz_claimAfter97Days_networkFrozen_shouldWork(uint32 secondsToWarp) public {
        vm.assume(secondsToWarp > 90 days);
        addHolding(address(0x1), 10 ether);
        vm.warp(block.timestamp + 1 weeks);
        vm.startPrank(SIMON);
        holdingContract.delayNetwork();
        vm.stopPrank();
        vm.warp(block.timestamp + secondsToWarp);
        holdingContract.claimHoldingSingleton(address(0x1), address(usdc));
    }

    function testFuzz_claimHoldingsBefore7Days_shouldAlwaysFail(uint256 secondsToWarp) public {
        vm.assume(secondsToWarp < 7 days);
        addHolding(address(0x1), 10 ether);
        addHolding(address(0x2), 10 ether);
        ClaimHoldingArgs[] memory args = new ClaimHoldingArgs[](2);
        args[0] = ClaimHoldingArgs({user: address(0x1), token: address(usdc)});
        args[1] = ClaimHoldingArgs({user: address(0x2), token: address(usdc)});
        vm.expectRevert(SafetyDelay.WithdrawalNotReady.selector);
        holdingContract.claimHoldings(args);
    }

    function testFuzz_claimHoldingsAfter7Days_shouldAlwaysWork(uint32 secondsToWarp) public {
        vm.assume(secondsToWarp > 7 days);
        addHolding(address(0x1), 10 ether);
        addHolding(address(0x2), 10 ether);
        ClaimHoldingArgs[] memory args = new ClaimHoldingArgs[](2);

        vm.warp(block.timestamp + secondsToWarp);
        args[0] = ClaimHoldingArgs({user: address(0x1), token: address(usdc)});
        args[1] = ClaimHoldingArgs({user: address(0x2), token: address(usdc)});
        holdingContract.claimHoldings(args);
    }

    function testFuzz_claimHoldingsBefore97Days_networkFrozen_shouldRevert(uint32 secondsToWarp) public {
        vm.assume(secondsToWarp < 90 days);
        addHolding(address(0x1), 10 ether);
        addHolding(address(0x2), 10 ether);
        ClaimHoldingArgs[] memory args = new ClaimHoldingArgs[](2);

        args[0] = ClaimHoldingArgs({user: address(0x1), token: address(usdc)});
        args[1] = ClaimHoldingArgs({user: address(0x2), token: address(usdc)});
        vm.warp(block.timestamp + 1 weeks);
        vm.startPrank(SIMON);
        holdingContract.delayNetwork();
        vm.stopPrank();
        vm.warp(block.timestamp + secondsToWarp);
        vm.expectRevert(SafetyDelay.NetworkIsFrozen.selector);
        holdingContract.claimHoldings(args);
    }

    function testFuzz_claimHoldingsAfter97Days_networkFrozen_shouldWork(uint32 secondsToWarp) public {
        vm.assume(secondsToWarp > 90 days);
        addHolding(address(0x1), 10 ether);
        addHolding(address(0x2), 10 ether);
        ClaimHoldingArgs[] memory args = new ClaimHoldingArgs[](2);

        args[0] = ClaimHoldingArgs({user: address(0x1), token: address(usdc)});
        args[1] = ClaimHoldingArgs({user: address(0x2), token: address(usdc)});
        vm.warp(block.timestamp + 1 weeks);
        vm.startPrank(SIMON);
        holdingContract.delayNetwork();
        vm.stopPrank();
        vm.warp(block.timestamp + secondsToWarp);
        holdingContract.claimHoldings(args);
    }

    function test_claimHoldingArgs_oneWeek_shouldClaim() public {
        addHolding(address(0x1), 10 ether);
        addHolding(address(0x2), 10 ether);

        ClaimHoldingArgs[] memory args = new ClaimHoldingArgs[](2);
        args[0] = ClaimHoldingArgs({user: address(0x1), token: address(usdc)});
        args[1] = ClaimHoldingArgs({user: address(0x2), token: address(usdc)});

        vm.expectRevert(SafetyDelay.WithdrawalNotReady.selector);
        holdingContract.claimHoldings(args);

        vm.warp(block.timestamp + ONE_WEEK);

        holdingContract.claimHoldings(args);
    }

    function addHolding(address to, uint192 amount) public {
        mintToHoldingContract(address(usdc), amount);
        vm.startPrank(address(minerPoolAndGCA));
        holdingContract.addHolding(to, address(usdc), amount);
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
}

contract FakeGCC {
    function CARBON_CREDIT_AUCTION() external pure returns (address) {
        return address(0x1);
    }
}

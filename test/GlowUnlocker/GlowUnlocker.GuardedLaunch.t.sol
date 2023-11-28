// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/testing/GuardedLaunch/TestGLOW.GuardedLaunch.sol";
import "forge-std/console.sol";
import {IGlow} from "../../src/interfaces/IGlow.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GlowUnlocker} from "@/GlowUnlocker.sol";
import {UnifapV2Factory} from "@unifapv2/UnifapV2Factory.sol";
import {UnifapV2Router} from "@unifapv2/UnifapV2Router.sol";
import {WETH9} from "@/UniswapV2/contracts/test/WETH9.sol";
import {TestUSDG} from "@/testing/TestUSDG.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";

contract GlowUnlockerGuardedLaunchTest is Test {
    //-------------------- Mock Addresses --------------------
    address public constant SIMON = address(0x11241998);
    uint256 public constant FIVE_YEARS = 365 days * 5;
    address public constant GCA = address(0x1);
    address public constant VETO_COUNCIL = address(0x2);
    address public constant GRANTS_TREASURY = address(0x3);
    address public constant EARLY_LIQUIDITY = address(0x4);
    address public constant VESTING_CONTRACT = address(0x5);
    GlowUnlocker public disperser;
    address[] public addresses;
    uint256[] public amounts;
    uint160 addressOffset = 100;
    address usdgOwner = address(0xaaa112);
    address usdcReceiver = address(0xaaa113);
    address mockVestingAddress = address(0xaaa114);
    //Make 10 addresses that each get 5 million,
    //and 4 addresses that each get 10 million

    //-------------------- Contracts --------------------
    TestGLOW public glw;
    TestUSDG public usdg;
    MockUSDC public usdc;
    UnifapV2Factory public uniswapFactory;
    WETH9 public weth;
    UnifapV2Router public uniswapRouter;

    //-------------------- Setup --------------------
    function setUp() public {
        //Create contracts
        uniswapFactory = new UnifapV2Factory();
        weth = new WETH9();
        uniswapRouter = new UnifapV2Router(address(uniswapFactory));

        usdc = new MockUSDC();
        usdg = new TestUSDG({
            _usdc: address(usdc),
            _usdcReceiver: usdcReceiver,
            _owner: usdgOwner,
            _univ2Factory: address(uniswapFactory)
        });

        vm.startPrank(tx.origin);
        uint256 sum = 0;
        for (uint256 i = 0; i < 10; i++) {
            addresses.push(address(uint160(SIMON) + addressOffset));
            amounts.push(5_000_000 ether);
            sum += 5_000_000 ether;
            addressOffset++;
        }
        for (uint256 i = 0; i < 4; i++) {
            addresses.push(address(uint160(SIMON) + addressOffset));
            amounts.push(10_000_000 ether);
            sum += 10_000_000 ether;
            addressOffset++;
        }
        assert(sum == 90_000_000 ether);
        disperser = new GlowUnlocker(addresses, amounts);
        //Create contracts
        glw = new TestGLOW({
            _earlyLiquidityAddress: EARLY_LIQUIDITY,
            _vestingContract: address(mockVestingAddress),
            _owner: SIMON,
            _usdg: address(usdg),
            _uniswapV2Factory: address(uniswapFactory)
        });
        disperser.initialize(address(glw));

        //Make sure early liquidity receives 12 million tokens
        assertEq(glw.balanceOf(EARLY_LIQUIDITY), 12_000_000 ether);
        vm.stopPrank();
        vm.startPrank(SIMON);
        glw.setGlowUnlocker(address(disperser));
        vm.stopPrank();

        vm.startPrank(mockVestingAddress);
        glw.transfer(address(disperser), 90_000_000 ether);
        vm.stopPrank();
    }

    function test_disperser_getNextReward() public {
        vm.warp(block.timestamp + uint256(365 days));
        address rewardAddress1 = addresses[0];
        address rewardAddress11 = addresses[10];
        {
            uint256 amount1 = disperser.amountUnlockable(rewardAddress1);
            uint256 amount11 = disperser.amountUnlockable(rewardAddress11);
            assert(amount1 == 5_000_000 ether);
            assert(amount11 == 10_000_000 ether);
        }
        uint256 reward1 = disperser.nextReward(rewardAddress1);
        uint256 reward11 = disperser.nextReward(rewardAddress11);
        assert(reward1 == 0 ether);
        assert(reward11 == 0 ether);

        vm.warp(block.timestamp + uint256(365 days));
        //after 365 days we should have 5_000_000 / 6 and 10_000_000 / 6
        reward1 = disperser.nextReward(rewardAddress1);
        reward11 = disperser.nextReward(rewardAddress11);
        assert(reward1 == uint256(5_000_000 ether) / uint256(5));
        assert(reward11 == uint256(10_000_000 ether) / uint256(5));

        vm.startPrank(rewardAddress1);
        disperser.claim(rewardAddress1);
        vm.stopPrank();

        reward1 = disperser.nextReward(rewardAddress1);
        assert(reward1 == 0 ether);

        //Warp again to 2 years
        vm.warp(block.timestamp + uint256(365 days));
        reward1 = disperser.nextReward(rewardAddress1);
        assert(reward1 == uint256(5_000_000 ether) / uint256(5));
        //claim again
        vm.startPrank(rewardAddress1);
        disperser.claim(rewardAddress1);
        vm.stopPrank();

        reward1 = disperser.nextReward(rewardAddress1);
        assert(reward1 == 0 ether);
        //fast forward 3 years to mark the end of the vesting period
        vm.warp(block.timestamp + uint256(3 * 365 days));
        reward1 = disperser.nextReward(rewardAddress1);
        // console.log("reward1", reward1);
        assert(reward1 == uint256(5_000_000 ether) * uint256(3) / uint256(5));
        //claim again
        vm.startPrank(rewardAddress1);
        disperser.claim(rewardAddress1);
        vm.stopPrank();

        reward1 = disperser.nextReward(rewardAddress1);
        assert(reward1 == 0 ether);

        //fast fowrad 2 years to make sure there is no overflow
        vm.warp(block.timestamp + uint256(2 * 365 days));
        reward1 = disperser.nextReward(rewardAddress1);
        assert(reward1 == 0 ether);

        //make sure it reverts
        vm.startPrank(rewardAddress1);
        vm.expectRevert(GlowUnlocker.NothingToClaim.selector);
        disperser.claim(rewardAddress1);
        vm.stopPrank();

        uint256 balance = glw.balanceOf(rewardAddress1);
        // console.log("balance", balance);
        //Tiny offset for dust
        assert(glw.balanceOf(rewardAddress1) == 5000000 ether);

        vm.startPrank(rewardAddress11);
        disperser.claim(rewardAddress11);
        vm.stopPrank();
        balance = glw.balanceOf(rewardAddress11);
        // console.log("balance", balance);
        //Tiny offset for dust
        assert(balance == 10_000_000 ether);
    }

    function testFuzz_claimingBeforeReleaseStartTimestamp_shouldRevert(uint256 timeToWarp) public {
        //release period is frozen between contract creation time and 1 year after
        timeToWarp = block.timestamp + timeToWarp % 365 days;
        vm.warp(timeToWarp);
        address rewardAddress1 = addresses[0];
        vm.expectRevert(GlowUnlocker.ReleasePeriodNotStarted.selector);
        disperser.claim(rewardAddress1);
    }

    function testFuzz_warpRandomTime_rewardsShouldNeverOverflow(uint128 secondsToWarpForward) public {
        vm.assume(secondsToWarpForward > uint256(365 days));
        vm.warp(block.timestamp + secondsToWarpForward);
        address rewardAddress1 = addresses[0];
        vm.startPrank(rewardAddress1);
        disperser.claim(rewardAddress1);
        vm.stopPrank();

        uint256 originalAmountOwed = disperser.amountUnlockable(rewardAddress1);

        uint256 balance = glw.balanceOf(rewardAddress1);
        assert(balance <= originalAmountOwed);
    }

    ///--------------------- MODIFIERS ---------------------
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/testing/TestGLOW.sol";
import "forge-std/console.sol";
import {IGlow} from "../../src/interfaces/IGlow.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PremineDisperser} from "@/PremineDisperser.sol";

contract PremineDisperserTest is Test {
    //-------------------- Mock Addresses --------------------
    address public constant SIMON = address(0x11241998);
    uint256 public constant FIVE_YEARS = 365 days * 5;
    address public constant GCA = address(0x1);
    address public constant VETO_COUNCIL = address(0x2);
    address public constant GRANTS_TREASURY = address(0x3);
    address public constant EARLY_LIQUIDITY = address(0x4);
    address public constant VESTING_CONTRACT = address(0x5);
    PremineDisperser public disperser;
    address[] public addresses;
    uint256[] public amounts;
    uint160 addressOffset = 100;

    //Make 10 addresses that each get 5 million,
    //and 4 addresses that each get 10 million

    //-------------------- Contracts --------------------
    TestGLOW public glw;

    //-------------------- Setup --------------------
    function setUp() public {
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
        disperser = new PremineDisperser(addresses, amounts);
        //Create contracts
        glw = new TestGLOW(EARLY_LIQUIDITY,address(disperser));
        disperser.initialize(address(glw));

        //Make sure early liquidity receives 12 million tokens
        assertEq(glw.balanceOf(EARLY_LIQUIDITY), 12_000_000 ether);
    }

    function test_disperser_getNextReward() public {
        address rewardAddress1 = addresses[0];
        address rewardAddress11 = addresses[10];
        {
            uint256 amount1 = disperser.amountOwed(rewardAddress1);
            uint256 amount11 = disperser.amountOwed(rewardAddress11);
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
        assert(reward1 == uint256(5_000_000 ether) / uint256(6));
        assert(reward11 == uint256(10_000_000 ether) / uint256(6));

        vm.startPrank(rewardAddress1);
        disperser.claim();
        vm.stopPrank();

        reward1 = disperser.nextReward(rewardAddress1);
        assert(reward1 == 0 ether);

        //Warp again to 2 years
        vm.warp(block.timestamp + uint256(365 days));
        reward1 = disperser.nextReward(rewardAddress1);
        assert(reward1 == uint256(5_000_000 ether) / uint256(6));
        //claim again
        vm.startPrank(rewardAddress1);
        disperser.claim();
        vm.stopPrank();

        reward1 = disperser.nextReward(rewardAddress1);
        assert(reward1 == 0 ether);
        //fast forward 4 years to mark the end of the vesting period

        vm.warp(block.timestamp + uint256(4 * 365 days));
        reward1 = disperser.nextReward(rewardAddress1);
        assert(reward1 == uint256(5_000_000 ether) * uint256(4) / uint256(6));
        //claim again
        vm.startPrank(rewardAddress1);
        disperser.claim();
        vm.stopPrank();

        reward1 = disperser.nextReward(rewardAddress1);
        assert(reward1 == 0 ether);

        //fast fowrad 2 years to make sure there is no overflow
        vm.warp(block.timestamp + uint256(2 * 365 days));
        reward1 = disperser.nextReward(rewardAddress1);
        assert(reward1 == 0 ether);

        //make sure it reverts
        vm.startPrank(rewardAddress1);
        vm.expectRevert(PremineDisperser.NothingToClaim.selector);
        disperser.claim();
        vm.stopPrank();

        uint256 balance = glw.balanceOf(rewardAddress1);
        console.log("balance", balance);
        //Tiny offset for dust
        assert(glw.balanceOf(rewardAddress1) == 4999999999999999999999999);

        vm.startPrank(rewardAddress11);
        disperser.claim();
        vm.stopPrank();

        balance = glw.balanceOf(rewardAddress11);
        console.log("balance", balance);
        //Tiny offset for dust
        assert(balance == 10_000_000 ether);
    }

    function testFuzz_warpRandomTime_rewardsShouldNeverOverflow(uint128 secondsToWarpForward) public {
        vm.assume(secondsToWarpForward > 0);
        vm.warp(block.timestamp + secondsToWarpForward);
        address rewardAddress1 = addresses[0];
        vm.startPrank(rewardAddress1);
        disperser.claim();
        vm.stopPrank();

        uint256 originalAmountOwed = disperser.amountOwed(rewardAddress1);

        uint256 balance = glw.balanceOf(rewardAddress1);
        assert(balance <= originalAmountOwed);
    }

    ///--------------------- MODIFIERS ---------------------
}

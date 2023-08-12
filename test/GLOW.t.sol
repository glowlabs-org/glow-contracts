// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/testing/TestGLOW.sol";
import "forge-std/console.sol";
import {IGlow} from "../src/interfaces/IGlow.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract TokenTest is Test {
    TestGLOW public glw;
    address public constant SIMON = address(0x11241998);
    uint256 public constant FIVE_YEARS = 365 days * 5;

    // function fastForwardInSeconds(uint secondsToFastForward) internal {
    //     vm.warp(block.timestamp + secondsToFastForward);
    // }
    function setUp() public {
        glw = new TestGLOW();
    }

    function testMint() public {
        uint256 amountToMint = 1e9 ether;
        vm.startPrank(SIMON);
        glw.mint(SIMON, amountToMint);
        assertEq(glw.balanceOf(SIMON), amountToMint);
    }

    function testStake() public {
        vm.startPrank(SIMON);
        uint256 amountToMint = 1e9 ether;
        glw.mint(SIMON, amountToMint);
        glw.stake(amountToMint);

        assertEq(glw.balanceOf(SIMON), 0);
        uint256 amountToStakeThatShouldFail = 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, SIMON, 0, amountToStakeThatShouldFail
            )
        );
        glw.stake(1);

        vm.expectRevert(IGlow.CannotStakeZeroTokens.selector);
        glw.stake(0);

        assertEq(glw.numStaked(SIMON), amountToMint);
    }

    function testStakeAndUnstakeSinglePosition() public {
        vm.startPrank(SIMON);
        uint256 amountToMint = 1e9 ether;
        glw.mint(SIMON, amountToMint);
        glw.stake(1 ether);

        vm.expectRevert(IGlow.UnstakeAmountExceedsStakedBalance.selector);
        glw.unstake(1 ether + 1);

        uint256 unstakeBlockTimestamp = block.timestamp;
        glw.unstake(1 ether);

        assertEq(glw.numStaked(SIMON), 0);

        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON);
        for (uint256 i; i < unstakedPositions.length; ++i) {
            IGlow.UnstakedPosition memory pos = unstakedPositions[i];
            // console.log("timestamp expiration", pos.cooldownEnd);
            // console.log("amount in unstake pool", pos.amount);
            assertEq(pos.cooldownEnd, unstakeBlockTimestamp + FIVE_YEARS);
            assertEq(pos.amount, 1 ether);
            // console.logString("-------------------------------");
        }
        vm.warp(unstakedPositions[0].cooldownEnd + 1);

        glw.stake(0.5 ether);
        assertEq(glw.numStaked(SIMON), 0.5 ether);

        unstakedPositions = glw.unstakedPositionsOf(SIMON);
        for (uint256 i; i < unstakedPositions.length; ++i) {
            IGlow.UnstakedPosition memory pos = unstakedPositions[i];
            // console.log("timestamp expiration", pos.cooldownEnd);
            // console.log("amount in unstake pool", pos.amount);
            // assertEq(pos.cooldownEnd, unstakeBlockTimestamp + FIVE_YEARS);
            assertEq(pos.amount, 0.5 ether);
            // console.logString("-------------------------------");
        }
    }

    function _calculateAmountToStakeForIndex(uint256 index) internal pure returns (uint256) {
        return (index + 1) * 1 ether;
    }

    modifier stageStakeAndUnstakeMultiplePositions() {
        vm.startPrank(SIMON);
        uint256 amountToMint = 1e9 ether;
        glw.mint(SIMON, amountToMint);
        glw.stake(55 ether);
        for (uint256 i; i < 10; ++i) {
            glw.unstake(_calculateAmountToStakeForIndex(i));
            vm.warp(block.timestamp + 5 minutes);
        }

        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON);
        for (uint256 i; i < unstakedPositions.length; ++i) {
            IGlow.UnstakedPosition memory pos = unstakedPositions[i];
            // console.log("timestamp expiration", pos.cooldownEnd);
            // console.log("amount in unstake pool", pos.amount);
            // assertEq(pos.cooldownEnd, unstakeBlockTimestamp + FIVE_YEARS);
            // assertEq(pos.amount, 1 ether);
            // console.logString("-------------------------------");
        }
        //Warp to the end
        vm.warp(unstakedPositions[9].cooldownEnd + 1);
        _;
    }

    function testStakeAndUnstakeMultiplePositions() public stageStakeAndUnstakeMultiplePositions {
        glw.stake(3 ether);
        // assertEq(glw.numStaked(SIMON),.5 ether);
        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON);
        for (uint256 i; i < unstakedPositions.length; ++i) {
            IGlow.UnstakedPosition memory pos = unstakedPositions[i];
            assertEq(pos.amount, _calculateAmountToStakeForIndex(i + 2));
        }
        //First 2 should be sliced since we re-staked (1 + 2) ether
        assertEq(unstakedPositions.length, 8);
    }

    function testStakeAndUnstakeMultiplePositions2() public stageStakeAndUnstakeMultiplePositions {
        glw.stake(2.5 ether);
        // assertEq(glw.numStaked(SIMON),.5 ether);
        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON);
        for (uint256 i; i < unstakedPositions.length; ++i) {
            IGlow.UnstakedPosition memory pos = unstakedPositions[i];
            if (i == 0) {
                assertEq(pos.amount, 0.5 ether);
                continue;
            }
            assertEq(pos.amount, _calculateAmountToStakeForIndex(i + 1));
        }

        //The new position 0 should have .5 ether and the rest should have stayed the same
        //First 2 should be sliced since we re-staked (1 + 2) ether
        assertEq(unstakedPositions.length, 9);
    }

    function testStakeAndUnstakeMultiplePositions3() public stageStakeAndUnstakeMultiplePositions {
        //This is the total amount that we've unstaked in the modifier
        glw.stake(55 ether);
        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON);
        //since we staked a total of 55 ether, the new length should be 0
        assertEq(unstakedPositions.length, 0);

        //Let's mint some more
        glw.mint(SIMON, 1e4 ether);

        uint256 numStaked = glw.numStaked(SIMON);
        assertEq(numStaked, 55 ether);
        glw.stake(1 ether);
        uint256 balBefore = glw.balanceOf(SIMON);
        glw.unstake(0.5 ether);

        unstakedPositions = glw.unstakedPositionsOf(SIMON);
        assertEq(unstakedPositions.length, 1);
        assertEq(unstakedPositions[0].amount, 0.5 ether);

        glw.stake(1.5 ether);
        uint256 balAfter = glw.balanceOf(SIMON);
        //Sanity check to make sure we actually transferred 1 ether of tokens
        assertEq(balAfter, balBefore - 1 ether);

        /*
            We staked 1 ether, then unstaked .5, then staked 1.5
            That means our unstaked position should still have .5 ether in it
            If we now go to stake 1.5 ether, we should only need to stake 1 ether 
            since we have .5 in our unstaked positions
        */
        unstakedPositions = glw.unstakedPositionsOf(SIMON);
        //The length should be 0 since we should have nothing in our unstaked positions since we restaked
        assertEq(unstakedPositions.length, 0);
    }

    function testClaim() public {
        vm.startPrank(SIMON);
        glw.mint(SIMON, 1e9 ether);
        glw.stake(1 ether);
        vm.expectRevert(IGlow.InsufficientClaimableBalance.selector);
        glw.claimUnstakedTokens(1 ether);

        glw.unstake(1 ether);
        vm.warp(block.timestamp + 5 minutes);
        //should revert since we need to wait 5 years
        vm.expectRevert(IGlow.InsufficientClaimableBalance.selector);
        glw.claimUnstakedTokens(1 ether);

        vm.warp(block.timestamp + FIVE_YEARS);
        uint256 balBefore = glw.balanceOf(SIMON);
        uint256 glwBalBefore = glw.balanceOf(address(glw));
        glw.claimUnstakedTokens(1 ether);
        uint256 balAfter = glw.balanceOf(SIMON);
        uint256 glwBalAfter = glw.balanceOf(address(glw));
        assertEq(balAfter, balBefore + 1 ether);

        assertEq(glwBalAfter, glwBalBefore - 1 ether);

        //Our unstaked positions should be empty now
        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON);
        assertEq(unstakedPositions.length, 0);

        //Sanity check: num staked should be zero
        assertEq(glw.numStaked(SIMON), 0);
    }

    function testClaimPartialFill() public {
        vm.startPrank(SIMON);
        glw.mint(SIMON, 1e9 ether);
        glw.stake(1 ether);
        vm.expectRevert(IGlow.InsufficientClaimableBalance.selector);
        glw.claimUnstakedTokens(1 ether);

        glw.unstake(1 ether);
        vm.warp(block.timestamp + 5 minutes);
        //should revert since we need to wait 5 years
        vm.expectRevert(IGlow.InsufficientClaimableBalance.selector);
        glw.claimUnstakedTokens(0.5 ether);

        vm.warp(block.timestamp + FIVE_YEARS);
        uint256 balBefore = glw.balanceOf(SIMON);
        uint256 glwBalBefore = glw.balanceOf(address(glw));
        glw.claimUnstakedTokens(0.5 ether);
        uint256 balAfter = glw.balanceOf(SIMON);
        uint256 glwBalAfter = glw.balanceOf(address(glw));
        assertEq(balAfter, balBefore + 0.5 ether);

        assertEq(glwBalAfter, glwBalBefore - 0.5 ether);

        //Our unstaked positions should be empty now
        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON);
        assertEq(unstakedPositions.length, 1);
        //Should have .5 ether
        assertEq(unstakedPositions[0].amount, 0.5 ether);

        //Sanity check: num staked should be zero
        assertEq(glw.numStaked(SIMON), 0);
    }
}

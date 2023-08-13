// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "../../src/testing/TestGLOW.sol";
import "forge-std/console.sol";
import {IGlow} from "../../src/interfaces/IGlow.sol";
import {Handler} from "./Handler.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract TokenTest is Test {
    TestGLOW public glw;
    Handler public handler;
    address public constant SIMON = address(0x11241998);
    uint256 public constant FIVE_YEARS = 365 days * 5;
    address public constant GCA = address(0x1);
    address public constant VETO_COUNCIL = address(0x2);
    address public constant GRANTS_TREASURY = address(0x3);
    address public constant EARLY_LIQUIDITY = address(0x4);
    address public constant VESTING_CONTRACT = address(0x5);

    //Manually inlining IGlow events until  0.8.22 release...
    event Stake(address indexed user, uint256 amount);
    event Unstake(address indexed user, uint256 amount);
    event ClaimUnstakedGLW(address indexed user, uint256 amount);

    function _fallsWithinBounds(uint256 actual, uint256 lowerBound, uint256 upperBound) internal pure returns (bool) {
        return actual >= lowerBound && actual <= upperBound;
    }

    function setUp() public {
        glw = new TestGLOW(EARLY_LIQUIDITY,VESTING_CONTRACT);
        handler = new Handler(address(glw));
        assertEq(glw.balanceOf(EARLY_LIQUIDITY), 12_000_000 ether);

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = Handler.stake.selector;
        selectors[1] = Handler.unstake.selector;
        selectors[2] = Handler.claimUnstakedTokens.selector;
        FuzzSelector memory fs = FuzzSelector({addr: address(handler), selectors: selectors});
        assertEq(glw.totalSupply(), 72_000_000 ether);
        glw.mint(address(handler), 1e20 ether);
        targetSender(address(SIMON));
        targetSelector(fs);
        targetContract(address(handler));
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

    function testUnstakeOver100ShouldForceCooldown() public {
        vm.startPrank(SIMON);
        uint256 amountToMint = 1e9 ether;
        glw.mint(SIMON, amountToMint);
        glw.stake(amountToMint);
        for (uint256 i; i < glw.MAX_UNSTAKES_BEFORE_EMERGENCY_COOLDOWN(); ++i) {
            glw.unstake(1 ether);
        }
        vm.expectRevert(IGlow.UnstakingOnEmergencyCooldown.selector);
        glw.unstake(1 ether);

        //After the emergency cooldown period, we should be able to unstake again
        vm.warp(block.timestamp + glw.EMERGENCY_COOLDOWN_PERIOD());
        glw.unstake(1 ether);
    }

    function testClaimZeroTokensShouldFail() public {
        vm.startPrank(SIMON);
        glw.mint(SIMON, 1e9 ether);
        glw.stake(1 ether);
        glw.unstake(1 ether);
        vm.warp(block.timestamp + FIVE_YEARS);
        vm.expectRevert(IGlow.CannotClaimZeroTokens.selector);
        glw.claimUnstakedTokens(0);
    }

    function testClaimTokens() public {
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

    function testClaimTokens_ClaimableTotalGT_Amount_NoNewTail() public {
        vm.startPrank(SIMON);
        glw.mint(SIMON, 1e9 ether);
        glw.stake(1 ether);
        vm.expectRevert(IGlow.InsufficientClaimableBalance.selector);
        glw.claimUnstakedTokens(1 ether);

        glw.unstake(1 ether);
        vm.warp(block.timestamp + 5 minutes);
        //should revert since we need to wait 5 years
        vm.expectRevert(IGlow.InsufficientClaimableBalance.selector);
        glw.claimUnstakedTokens(0.1 ether);

        vm.warp(block.timestamp + FIVE_YEARS);
        uint256 balBefore = glw.balanceOf(SIMON);
        uint256 glwBalBefore = glw.balanceOf(address(glw));
        glw.claimUnstakedTokens(0.1 ether);
        uint256 balAfter = glw.balanceOf(SIMON);
        uint256 glwBalAfter = glw.balanceOf(address(glw));
        assertEq(balAfter, balBefore + 0.1 ether);

        assertEq(glwBalAfter, glwBalBefore - 0.1 ether);

        //Our unstaked positions should be empty now
        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON);
        assertEq(unstakedPositions.length, 1);

        //Sanity check: num staked should be zero
        assertEq(glw.numStaked(SIMON), 0);
    }

    function testClaimTokens_ClaimableTotalGT_Amount_NewTail() public {
        vm.startPrank(SIMON);
        glw.mint(SIMON, 1e9 ether);
        glw.stake(1 ether);
        vm.expectRevert(IGlow.InsufficientClaimableBalance.selector);
        glw.claimUnstakedTokens(1 ether);

        //Create 2 staked positions
        glw.unstake(0.01 ether);
        glw.unstake(0.99 ether);

        vm.warp(block.timestamp + 5 minutes);
        //should revert since we need to wait 5 years
        vm.expectRevert(IGlow.InsufficientClaimableBalance.selector);
        glw.claimUnstakedTokens(1.1 ether);

        vm.warp(block.timestamp + FIVE_YEARS);
        uint256 balBefore = glw.balanceOf(SIMON);
        uint256 glwBalBefore = glw.balanceOf(address(glw));
        glw.claimUnstakedTokens(0.1 ether);
        uint256 balAfter = glw.balanceOf(SIMON);
        uint256 glwBalAfter = glw.balanceOf(address(glw));
        assertEq(balAfter, balBefore + 0.1 ether);

        assertEq(glwBalAfter, glwBalBefore - 0.1 ether);

        //Our unstaked positions should be empty now
        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON);
        assertEq(unstakedPositions.length, 1);

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

    //TODO: Debug why this test fails
    // function testEmits() public {
    //     vm.startPrank(SIMON);
    //     glw.mint(SIMON, 1e9 ether);

    //     vm.expectEmit(address(glw));
    //     emit Stake(SIMON, 1 ether);
    //     glw.stake(1 ether);

    // }

    //-------------------- Inflation Tests --------------------

    function testInflationShouldRevertIfContractsNotSet() public {
        vm.expectRevert(IGlow.AddressNotSet.selector);
        glw.claimGLWFromGCAAndMinerPool();
        vm.expectRevert(IGlow.AddressNotSet.selector);
        glw.claimGLWFromVetoCouncil();
        vm.expectRevert(IGlow.AddressNotSet.selector);
        glw.claimGLWFromGrantsTreasury();
    }

    modifier setInflationContracts() {
        vm.startPrank(SIMON);
        glw.setContractAddresses(GCA, VETO_COUNCIL, GRANTS_TREASURY);
        vm.stopPrank();
        _;
    }

    function testClaimInflationFromGCA() public setInflationContracts {
        vm.startPrank(SIMON);

        vm.expectRevert(IGlow.CallerNotGCA.selector);
        glw.claimGLWFromGCAAndMinerPool();
        //Sanity Check to make sure GCA has 0 balance
        vm.stopPrank();

        vm.startPrank(GCA);
        vm.warp(glw.GENESIS_TIMESTAMP());
        glw.claimGLWFromGCAAndMinerPool();
        assertEq(glw.balanceOf(GCA), 0);

        //Should be able to pull 185,000 * 1e18 tokens in 1 week
        vm.warp(glw.GENESIS_TIMESTAMP() + 7 days);
        glw.claimGLWFromGCAAndMinerPool();
        uint256 balanceAfterFirstClaim = glw.balanceOf(GCA);
        //.00000005% rounding error caught
        assertEq(_fallsWithinBounds(balanceAfterFirstClaim, 184_999.999 ether, 185_000.001 ether), true);

        vm.warp(glw.GENESIS_TIMESTAMP() + 7 days);
        //balanceAfterSecond claim should be exactly the same as the first claim since no time has passed
        glw.claimGLWFromGCAAndMinerPool();
        uint256 balanceAfterSecondClaim = glw.balanceOf(GCA);
        assertEq(balanceAfterFirstClaim, balanceAfterSecondClaim);
    }

    function testClaimFromVetoCouncil() public setInflationContracts {
        vm.startPrank(SIMON);
        vm.expectRevert(IGlow.CallerNotVetoCouncil.selector);
        glw.claimGLWFromVetoCouncil();
        vm.stopPrank();

        vm.startPrank(VETO_COUNCIL);
        vm.warp(glw.GENESIS_TIMESTAMP());
        glw.claimGLWFromVetoCouncil();
        assertEq(glw.balanceOf(VETO_COUNCIL), 0);

        //Should be able to pull 5,000 * 1e18 tokens in 1 week
        vm.warp(glw.GENESIS_TIMESTAMP() + 7 days);
        glw.claimGLWFromVetoCouncil();
        uint256 balanceAfterFirstClaim = glw.balanceOf(VETO_COUNCIL);
        //.0.00000002% rounding error caught
        assertEq(_fallsWithinBounds(balanceAfterFirstClaim, 4_999.9999 ether, 5_000.0001 ether), true);

        vm.warp(glw.GENESIS_TIMESTAMP() + 7 days);
        //balanceAfterSecond claim should be exactly the same as the first claim since no time has passed
        glw.claimGLWFromVetoCouncil();
        uint256 balanceAfterSecondClaim = glw.balanceOf(VETO_COUNCIL);
        assertEq(balanceAfterFirstClaim, balanceAfterSecondClaim);
    }

    function testClaimFromGrantsTreasury() public setInflationContracts {
        vm.startPrank(SIMON);
        vm.expectRevert(IGlow.CallerNotGrantsTreasury.selector);
        glw.claimGLWFromGrantsTreasury();
        vm.stopPrank();

        vm.startPrank(GRANTS_TREASURY);
        vm.warp(glw.GENESIS_TIMESTAMP());
        glw.claimGLWFromGrantsTreasury();
        assertEq(glw.balanceOf(GRANTS_TREASURY), 0);

        //Should be able to pull 40,000 * 1e18 tokens in 1 week
        vm.warp(glw.GENESIS_TIMESTAMP() + 7 days);
        glw.claimGLWFromGrantsTreasury();
        uint256 balanceAfterFirstClaim = glw.balanceOf(GRANTS_TREASURY);
        //.00000025% rounding error caught
        assertEq(_fallsWithinBounds(balanceAfterFirstClaim, 39_999.999 ether, 40_000.0001 ether), true);

        vm.warp(glw.GENESIS_TIMESTAMP() + 7 days);
        //balanceAfterSecond claim should be exactly the same as the first claim since no time has passed
        glw.claimGLWFromGrantsTreasury();
        uint256 balanceAfterSecondClaim = glw.balanceOf(GRANTS_TREASURY);
        assertEq(balanceAfterFirstClaim, balanceAfterSecondClaim);
    }

    function testInflationGettersShouldRevertIfContractsNotSet() public {
        vm.expectRevert(IGlow.AddressNotSet.selector);
        (uint256 a, uint256 b, uint256 c) = glw.gcaInflationData();

        vm.expectRevert(IGlow.AddressNotSet.selector);
        (a, b, c) = glw.vetoCouncilInflationData();

        vm.expectRevert(IGlow.AddressNotSet.selector);
        (a, b, c) = glw.grantsTreasuryInflationData();

        glw.setContractAddresses(GCA, VETO_COUNCIL, GRANTS_TREASURY);

        //Should now work
        (a, b, c) = glw.gcaInflationData();
        (a, b, c) = glw.vetoCouncilInflationData();
        (a, b, c) = glw.grantsTreasuryInflationData();
    }

    function testSetContractAddressesCannotBeZero() public {
        //All combinations of 0 addresses should revert
        vm.expectRevert(IGlow.ZeroAddressNotAllowed.selector);
        glw.setContractAddresses(a(0), a(0), a(0));
        vm.expectRevert(IGlow.ZeroAddressNotAllowed.selector);
        glw.setContractAddresses(a(0), a(0), a(1));
        vm.expectRevert(IGlow.ZeroAddressNotAllowed.selector);
        glw.setContractAddresses(a(0), a(1), a(0));
        vm.expectRevert(IGlow.ZeroAddressNotAllowed.selector);
        glw.setContractAddresses(a(1), a(0), a(0));

        vm.expectRevert(IGlow.ZeroAddressNotAllowed.selector);
        glw.setContractAddresses(a(0), a(1), a(2));
        vm.expectRevert(IGlow.ZeroAddressNotAllowed.selector);
        glw.setContractAddresses(a(1), a(0), a(2));
        vm.expectRevert(IGlow.ZeroAddressNotAllowed.selector);
        glw.setContractAddresses(a(1), a(2), a(0));
    }

    function testSetContractAddressesCannotBeDuplicates() public {
        vm.expectRevert(IGlow.DuplicateAddressNotAllowed.selector);
        glw.setContractAddresses(VETO_COUNCIL, VETO_COUNCIL, VETO_COUNCIL);
        vm.expectRevert(IGlow.DuplicateAddressNotAllowed.selector);
        glw.setContractAddresses(VETO_COUNCIL, VETO_COUNCIL, GRANTS_TREASURY);
        vm.expectRevert(IGlow.DuplicateAddressNotAllowed.selector);
        glw.setContractAddresses(VETO_COUNCIL, GRANTS_TREASURY, VETO_COUNCIL);
        vm.expectRevert(IGlow.DuplicateAddressNotAllowed.selector);
        glw.setContractAddresses(VETO_COUNCIL, GRANTS_TREASURY, GRANTS_TREASURY);
        vm.expectRevert(IGlow.DuplicateAddressNotAllowed.selector);
        glw.setContractAddresses(GRANTS_TREASURY, VETO_COUNCIL, VETO_COUNCIL);
        vm.expectRevert(IGlow.DuplicateAddressNotAllowed.selector);
        glw.setContractAddresses(GRANTS_TREASURY, VETO_COUNCIL, GRANTS_TREASURY);
        vm.expectRevert(IGlow.DuplicateAddressNotAllowed.selector);
        glw.setContractAddresses(GRANTS_TREASURY, GRANTS_TREASURY, VETO_COUNCIL);
        vm.expectRevert(IGlow.DuplicateAddressNotAllowed.selector);
        glw.setContractAddresses(GRANTS_TREASURY, GRANTS_TREASURY, GRANTS_TREASURY);
    }

    function testShouldOnlyBeAbleToSetContractAddressesOnce() public {
        glw.setContractAddresses(GCA, VETO_COUNCIL, GRANTS_TREASURY);
        vm.expectRevert(IGlow.AddressAlreadySet.selector);
        glw.setContractAddresses(GCA, VETO_COUNCIL, GRANTS_TREASURY);
    }

    function testUnstakedPositionsOf() public {
        vm.startPrank(SIMON);
        uint256 amountToMint = 1e9 ether;
        glw.mint(SIMON, amountToMint);
        glw.stake(55 ether);
        for (uint256 i; i < 10; ++i) {
            glw.unstake(_calculateAmountToStakeForIndex(i));
            vm.warp(block.timestamp + 5 minutes);
        }
        //Should have 10 unstaked positions and my tail should be 0
        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON);
        assertEq(unstakedPositions.length, 10);

        //let's make sure all the values are correct
        for (uint256 i; i < 10; ++i) {
            assertEq(unstakedPositions[i].amount, _calculateAmountToStakeForIndex(i));
        }
        //Let's fast forward 5 years to claim some positions which should update the tail
        vm.warp(block.timestamp + 365 days * 5);

        //This should pop the first position (move the tail by 1)
        uint256 amountToUnstake = _calculateAmountToStakeForIndex(0);
        glw.claimUnstakedTokens(amountToUnstake);

        //Now if we query we should only get 9 positions
        unstakedPositions = glw.unstakedPositionsOf(SIMON);
        assertEq(unstakedPositions.length, 9);

        //assert that the values are correct ,
        //we should have 9 positions and the first position should be _calculateAmountToStakeForIndex(1)
        for (uint256 i; i < 9; ++i) {
            assertEq(unstakedPositions[i].amount, _calculateAmountToStakeForIndex(i + 1));
        }

        //Let's pop 2 positions
        uint256 amountToPop2 = _calculateAmountToStakeForIndex(1) + _calculateAmountToStakeForIndex(2);
        glw.claimUnstakedTokens(amountToPop2);

        //Now if we query we should only get 7 positions
        unstakedPositions = glw.unstakedPositionsOf(SIMON);
        assertEq(unstakedPositions.length, 7);

        //assert that the values are correct ,
        //we should have 7 positions and the first position should be _calculateAmountToStakeForIndex(3)
        for (uint256 i; i < 7; ++i) {
            assertEq(unstakedPositions[i].amount, _calculateAmountToStakeForIndex(i + 3));
        }
    }

    function testUnstakedPositionsOfPagination() public {
        vm.startPrank(SIMON);
        uint256 amountToMint = 1e9 ether;
        glw.mint(SIMON, amountToMint);
        glw.stake(55 ether);
        for (uint256 i; i < 10; ++i) {
            glw.unstake(_calculateAmountToStakeForIndex(i));
            vm.warp(block.timestamp + 5 minutes);
        }
        //Should have 10 unstaked positions and my tail should be 0
        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON);
        assertEq(unstakedPositions.length, 10);

        unstakedPositions = glw.unstakedPositionsOf(SIMON, 0, 10);
        assertEq(unstakedPositions.length, 10);

        //Sanity check to make sure we can correclty paginate
        unstakedPositions = glw.unstakedPositionsOf(SIMON, 0, 5);
        assertEq(unstakedPositions.length, 5);

        //Let's check the pagination results to make sure they're consistent
        for (uint256 i; i < 5; ++i) {
            assertEq(unstakedPositions[i].amount, _calculateAmountToStakeForIndex(i));
        }

        //Let's get 5,10
        unstakedPositions = glw.unstakedPositionsOf(SIMON, 5, 10);
        assertEq(unstakedPositions.length, 5);
        for (uint256 i; i < 5; ++i) {
            assertEq(unstakedPositions[i].amount, _calculateAmountToStakeForIndex(i + 5));
        }

        //if we try to get more than 10 we should get only 10
        unstakedPositions = glw.unstakedPositionsOf(SIMON, 0, 11);
        assertEq(unstakedPositions.length, 10);

        //Let's fast forward 5 years to claim some positions which should update the tail
        vm.warp(block.timestamp + 365 days * 5);

        uint256 amountToUnstake = _calculateAmountToStakeForIndex(0);
        glw.claimUnstakedTokens(amountToUnstake);

        //Now if we query 0,10 we should only get 9 positions
        unstakedPositions = glw.unstakedPositionsOf(SIMON, 0, 10);
        assertEq(unstakedPositions.length, 9);

        //assert that the values are correct ,
        //we should have 9 positions and the first position should be _calculateAmountToStakeForIndex(1)
        for (uint256 i; i < 9; ++i) {
            assertEq(unstakedPositions[i].amount, _calculateAmountToStakeForIndex(i + 1));
        }

        //Let's unclaim 2
        uint256 amountToPop2 = _calculateAmountToStakeForIndex(1) + _calculateAmountToStakeForIndex(2);
        glw.claimUnstakedTokens(amountToPop2);

        //Now if we query 0,10 we should only get 7 positions
        unstakedPositions = glw.unstakedPositionsOf(SIMON, 0, 10);

        //assert that the values are correct ,
        //we should have 7 positions and the first position should be _calculateAmountToStakeForIndex(3)
        assertEq(unstakedPositions.length, 7);
        for (uint256 i; i < 7; ++i) {
            assertEq(unstakedPositions[i].amount, _calculateAmountToStakeForIndex(i + 3));
        }

        //Let's query 0,7 to make sure we get the same results
        unstakedPositions = glw.unstakedPositionsOf(SIMON, 0, 7);
        assertEq(unstakedPositions.length, 7);
    }

    function testPaginationTailGreaterThanLengthShouldReturnEmptyArray() public {
        vm.startPrank(SIMON);
        uint256 amountToMint = 1e9 ether;
        glw.mint(SIMON, amountToMint);
        glw.stake(55 ether);
        for (uint256 i; i < 10; ++i) {
            glw.unstake(_calculateAmountToStakeForIndex(i));
            vm.warp(block.timestamp + 5 minutes);
        }

        // start should be > than length case 0
        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON, 11, 12);
        assertEq(unstakedPositions.length, 0);

        //start should be == length, case 1
        unstakedPositions = glw.unstakedPositionsOf(SIMON, 10, 12);
        assertEq(unstakedPositions.length, 0);
    }

    function a(uint256 a) internal pure returns (address) {
        return address(uint160(a));
    }
}

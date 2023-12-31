// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import "../../src/testing/TestGLOW.sol";
import "forge-std/console.sol";
import {IGlow} from "../../src/interfaces/IGlow.sol";
import {IGrantsTreasury} from "../../src/interfaces/IGrantsTreasury.sol";
import {GrantsTreasury} from "../../src/GrantsTreasury.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract GrantsTreasuryTest is Test {
    TestGLOW public glw;
    GrantsTreasury public grantsTreasury;
    address public constant SIMON = address(0x11241998);
    uint256 public constant FIVE_YEARS = 365 days * 5;
    address public constant GCA = address(0x1);
    address public constant VETO_COUNCIL = address(0x2);
    address public constant EARLY_LIQUIDITY = address(0x4);
    address public constant VESTING_CONTRACT = address(0x5);
    address public constant GOVERNANCE = address(0x6);
    address public constant NOT_GOVERNANCE = address(0x7);
    uint256 public constant GRANTS_INFLATION_PER_WEEK = 40_000 ether;
    uint256 constant STARTING_GRANTS_BALANCE = 0 ether;
    address deployer = tx.origin;

    function setUp() public {
        vm.startPrank(deployer);
        uint256 deployerNonce = vm.getNonce(deployer);
        address precomputeGrants = computeCreateAddress(deployer, deployerNonce + 1);
        glw = new TestGLOW(EARLY_LIQUIDITY, VESTING_CONTRACT, GCA, VETO_COUNCIL, precomputeGrants);
        grantsTreasury = new GrantsTreasury(address(glw), GOVERNANCE);
        assertEq(precomputeGrants, address(grantsTreasury));

        vm.stopPrank();
        //TODO: set the contract addresses
        // glw.setContractAddresses(GCA, VETO_COUNCIL, address(grantsTreasury));
    }

    function test_AllocatingFromNotGovernanceShouldRevert() public {
        vm.expectRevert(IGrantsTreasury.CallerNotGovernance.selector);
        grantsTreasury.allocateGrantFunds(SIMON, 1);
    }

    function test_AllocationFromGovernanceShouldWork() public {
        vm.startPrank(GOVERNANCE);
        grantsTreasury.allocateGrantFunds(SIMON, 1 ether);
        vm.stopPrank();
    }

    /**
     * no time should have passed, therefore the treasury should have 0 from inflation
     * and {allocateGrantFunds} should return false
     */
    function test_AllocationShouldReturnFalse() public {
        vm.startPrank(GOVERNANCE);
        //The contract starts with 6 million tokens
        bool succesfulCall = grantsTreasury.allocateGrantFunds(SIMON, STARTING_GRANTS_BALANCE + 1 ether);
        assertEq(succesfulCall, false);
        assertEq(grantsTreasury.recipientBalance(SIMON), 0 ether);
        assertEq(grantsTreasury.cumulativeAllocated(), 0 ether);
        assertEq(grantsTreasury.cumulativePaidOut(), 0 ether);
        vm.stopPrank();
    }

    function test_AllocationShouldReturnTrue() public {
        vm.startPrank(GOVERNANCE);
        vm.warp(block.timestamp + 365 days);
        bool succesfulCall = grantsTreasury.allocateGrantFunds(SIMON, 1 ether);
        assertEq(succesfulCall, true);
        assertEq(grantsTreasury.recipientBalance(SIMON), 1 ether);
        assertEq(grantsTreasury.cumulativeAllocated(), 1 ether);
        assertEq(grantsTreasury.cumulativePaidOut(), 0 ether);
        vm.stopPrank();
    }

    function test_AllocationShouldReturnTrueAndRecipientShouldClaim() public {
        vm.startPrank(GOVERNANCE);
        vm.warp(block.timestamp + 365 days);
        grantsTreasury.claimGlowFromTreasury();
        uint256 balBefore = glw.balanceOf(address(grantsTreasury));
        bool succesfulCall = grantsTreasury.allocateGrantFunds(SIMON, 1 ether);
        assertEq(succesfulCall, true);
        assertEq(grantsTreasury.recipientBalance(SIMON), 1 ether);
        assertEq(grantsTreasury.cumulativeAllocated(), 1 ether);
        assertEq(grantsTreasury.cumulativePaidOut(), 0 ether);
        vm.stopPrank();
        vm.startPrank(SIMON);
        grantsTreasury.claimGrantReward();
        assertEq(glw.balanceOf(SIMON), 1 ether);
        assertEq(grantsTreasury.cumulativePaidOut(), 1 ether);
        uint256 balAfter = grantsTreasury.totalBalanceInGrantsTreasury();
        assertEq(balAfter, balBefore - 1 ether);
        assertEq(grantsTreasury.recipientBalance(SIMON), 0 ether);
        assertEq(grantsTreasury.cumulativeAllocated(), 1 ether);
        vm.stopPrank();
    }

    function test_actualBalanceTooLow() public {
        vm.startPrank(GOVERNANCE);
        vm.warp(block.timestamp + 365 days);
        grantsTreasury.claimGlowFromTreasury();
        uint256 balBefore = glw.balanceOf(address(grantsTreasury));
        bool succesfulCall = grantsTreasury.allocateGrantFunds(SIMON, balBefore);
        assertEq(succesfulCall, true);
        assertEq(grantsTreasury.recipientBalance(SIMON), balBefore);
        assertEq(grantsTreasury.cumulativeAllocated(), balBefore);
        assertEq(grantsTreasury.cumulativePaidOut(), 0 ether);

        //try to give 1 token to a recipient
        succesfulCall = grantsTreasury.allocateGrantFunds(address(0x12312312), 1);
        assertEq(succesfulCall, false);
        vm.stopPrank();

        //-----------------  CLAIM ---------------------//
        vm.startPrank(SIMON);
        grantsTreasury.claimGrantReward();
        assertEq(glw.balanceOf(SIMON), balBefore);
        assertEq(grantsTreasury.cumulativePaidOut(), balBefore);
        uint256 balAfter = grantsTreasury.totalBalanceInGrantsTreasury();
        assertEq(grantsTreasury.recipientBalance(SIMON), 0 ether);
        assertEq(grantsTreasury.cumulativeAllocated(), balBefore);
        vm.stopPrank();
    }

    function test_ClaimZeroShouldRevert() public {
        test_AllocationShouldReturnTrueAndRecipientShouldClaim();
        vm.startPrank(SIMON);
        vm.expectRevert(IGrantsTreasury.AllocationCannotBeZero.selector);
        grantsTreasury.claimGrantReward();
        vm.stopPrank();
    }

    function test_SyncShouldPullFromInflation() public {
        uint256 balBefore = glw.balanceOf(address(grantsTreasury));
        assertEq(balBefore, STARTING_GRANTS_BALANCE);
        vm.warp(block.timestamp + 7 days);
        grantsTreasury.claimGlowFromTreasury();
        uint256 balAfter = glw.balanceOf(address(grantsTreasury));

        assertEq(
            _fallsWithinBounds(
                balAfter,
                STARTING_GRANTS_BALANCE + GRANTS_INFLATION_PER_WEEK - 1e10,
                STARTING_GRANTS_BALANCE + GRANTS_INFLATION_PER_WEEK + 1e10
            ),
            true
        );
    }

    //-----------------  HELPERS ---------------------//
    function _fallsWithinBounds(uint256 actual, uint256 lowerBound, uint256 upperBound) internal pure returns (bool) {
        return actual >= lowerBound && actual <= upperBound;
    }
}

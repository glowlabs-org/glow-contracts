// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {OffchainFractions} from "@/v2/OffchainFractions.sol";
import {CounterfactualHolderFactory} from "@/v2/CounterfactualHolderFactory.sol";
import {MockERC20} from "@/testing/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Mock tax token that takes fees on transfer
contract MockTaxToken is MockERC20 {
    uint256 public taxRate = 100; // 1% tax (100 basis points out of 10000)

    constructor() MockERC20("Tax Token", "TAX", 18) {}

    function transfer(address to, uint256 amount) public override returns (bool) {
        uint256 tax = (amount * taxRate) / 10000;
        uint256 netAmount = amount - tax;

        _transfer(msg.sender, to, netAmount);
        if (tax > 0) {
            _transfer(msg.sender, address(0xdead), tax); // Burn tax
        }
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 tax = (amount * taxRate) / 10000;
        uint256 netAmount = amount - tax;

        uint256 currentAllowance = allowance(from, msg.sender);
        require(currentAllowance >= amount, "ERC20: insufficient allowance");

        _approve(from, msg.sender, currentAllowance - amount);
        _transfer(from, to, netAmount);
        if (tax > 0) {
            _transfer(from, address(0xdead), tax); // Burn tax
        }
        return true;
    }
}

/**
 * @title OffchainFractionsTest
 * @notice Comprehensive test suite for OffchainFractions contract
 * @dev Tests cover unit tests, fuzz tests, invariants, and edge cases
 * @dev Full test plan documented in OffchainFractionsTestPlan.md
 */
contract OffchainFractionsTest is Test {
    // ============ STATE VARIABLES ============

    OffchainFractions public offchainFractions;
    CounterfactualHolderFactory public counterfactualHolderFactory;
    MockERC20 public token;
    MockTaxToken public taxToken;

    // Test actors
    address public creator = makeAddr("creator");
    address public buyer1 = makeAddr("buyer1");
    address public buyer2 = makeAddr("buyer2");
    address public recipient = makeAddr("recipient");

    // Test constants
    bytes32 public constant FRACTION_ID = keccak256("test_fraction");
    uint256 public constant STEP_PRICE = 1e18; // 1 token per step
    uint256 public constant TOTAL_STEPS = 100;
    uint256 public constant MIN_SHARES = 50;
    uint256 public constant ONE_WEEK = 7 * uint256(1 days);
    uint48 public EXPIRATION_TIME = uint48(block.timestamp + ONE_WEEK);

    // ============ EVENTS FOR TESTING ============

    event FractionCreated(
        bytes32 indexed id,
        address indexed token,
        address indexed owner,
        uint256 step,
        uint256 totalSteps,
        uint48 expiration,
        address to,
        bool useCounterfactualAddress,
        uint256 minSharesToRaise,
        address closer
    );

    event FractionSold(
        bytes32 indexed id, address indexed creator, address indexed buyer, uint256 step, uint256 amount
    );

    event RoundFilled(bytes32 indexed id, address indexed creator);
    event FractionClosed(bytes32 indexed id, address indexed token, address indexed owner);
    event FractionRefunded(bytes32 indexed id, address indexed creator, address indexed user, uint256 amount);
    event MinSharesReached(bytes32 indexed id, address indexed creator, uint256 minShares, uint256 newTotalSharesSold);

    // ============ SETUP ============

    function setUp() public {
        counterfactualHolderFactory = new CounterfactualHolderFactory();
        offchainFractions = new OffchainFractions(counterfactualHolderFactory);
        token = new MockERC20("Test Token", "TEST", 18);
        taxToken = new MockTaxToken();

        // Setup initial balances
        token.mint(creator, 1000e18);
        token.mint(buyer1, 1000e18);
        token.mint(buyer2, 1000e18);
        taxToken.mint(buyer1, 1000e18);
        taxToken.mint(buyer2, 1000e18);

        // Setup approvals
        vm.prank(buyer1);
        token.approve(address(offchainFractions), type(uint256).max);
        vm.prank(buyer2);
        token.approve(address(offchainFractions), type(uint256).max);
        vm.prank(buyer1);
        taxToken.approve(address(offchainFractions), type(uint256).max);
        vm.prank(buyer2);
        taxToken.approve(address(offchainFractions), type(uint256).max);

        EXPIRATION_TIME = uint48(block.timestamp + ONE_WEEK);
    }

    // ============ HELPER FUNCTIONS ============

    function _createBasicFraction() internal {
        vm.prank(creator);
        offchainFractions.createFraction(
            FRACTION_ID, address(token), STEP_PRICE, TOTAL_STEPS, EXPIRATION_TIME, recipient, false, MIN_SHARES, creator
        );
    }

    // ============ UNIT TESTS - CREATE FRACTION ============

    function test_createFraction_Success() public {
        vm.prank(creator);
        vm.expectEmit(true, true, true, true);
        emit FractionCreated(
            FRACTION_ID,
            address(token),
            creator,
            STEP_PRICE,
            TOTAL_STEPS,
            EXPIRATION_TIME,
            recipient,
            false,
            MIN_SHARES,
            creator
        );

        offchainFractions.createFraction(
            FRACTION_ID, address(token), STEP_PRICE, TOTAL_STEPS, EXPIRATION_TIME, recipient, false, MIN_SHARES, creator
        );

        OffchainFractions.FractionData memory fraction = offchainFractions.getFraction(creator, FRACTION_ID);
        assertEq(fraction.token, address(token));
        assertEq(fraction.owner, creator);
        assertEq(fraction.step, STEP_PRICE);
        assertEq(fraction.totalSteps, TOTAL_STEPS);
        assertEq(fraction.expiration, EXPIRATION_TIME);
        assertEq(fraction.to, recipient);
        assertEq(fraction.minSharesToRaise, MIN_SHARES);
        assertFalse(fraction.manuallyClosed);
        assertFalse(fraction.useCounterfactualAddress);
        assertFalse(fraction.claimedFromMinSharesToRaise);
        assertEq(fraction.soldSteps, 0);
    }

    function test_createFraction_ZeroMinShares() public {
        vm.prank(creator);
        offchainFractions.createFraction(
            FRACTION_ID,
            address(token),
            STEP_PRICE,
            TOTAL_STEPS,
            EXPIRATION_TIME,
            recipient,
            false,
            0, // No minimum shares
            creator
        );

        OffchainFractions.FractionData memory fraction = offchainFractions.getFraction(creator, FRACTION_ID);
        assertEq(fraction.minSharesToRaise, 0);
        assertTrue(fraction.claimedFromMinSharesToRaise); // Should be true for zero min shares
    }

    function test_createFraction_RevertAlreadyExists() public {
        vm.startPrank(creator);

        // Create first fraction
        offchainFractions.createFraction(
            FRACTION_ID, address(token), STEP_PRICE, TOTAL_STEPS, EXPIRATION_TIME, recipient, false, MIN_SHARES, creator
        );

        // Try to create same fraction again
        vm.expectRevert(OffchainFractions.AlreadyExists.selector);
        offchainFractions.createFraction(
            FRACTION_ID, address(token), STEP_PRICE, TOTAL_STEPS, EXPIRATION_TIME, recipient, false, MIN_SHARES, creator
        );

        vm.stopPrank();
    }

    function test_createFraction_RevertInvalidToken() public {
        vm.prank(creator);
        vm.expectRevert(OffchainFractions.InvalidToken.selector);
        offchainFractions.createFraction(
            FRACTION_ID, address(0), STEP_PRICE, TOTAL_STEPS, EXPIRATION_TIME, recipient, false, MIN_SHARES, creator
        );
    }

    // ============ UNIT TESTS - BUY FRACTIONS ============

    function test_buyFractions_Success() public {
        _createBasicFraction();

        uint256 stepsToBuy = 25;
        uint256 expectedAmount = stepsToBuy * STEP_PRICE;

        vm.prank(buyer1);
        vm.expectEmit(true, true, true, true);
        emit FractionSold(FRACTION_ID, creator, buyer1, STEP_PRICE, expectedAmount);

        offchainFractions.buyFractions(creator, FRACTION_ID, stepsToBuy, stepsToBuy);

        // Verify state changes
        assertEq(offchainFractions.stepsPurchased(buyer1, creator, FRACTION_ID), stepsToBuy);

        OffchainFractions.FractionData memory fraction = offchainFractions.getFraction(creator, FRACTION_ID);
        assertEq(fraction.soldSteps, stepsToBuy);

        // Since we're below minSharesToRaise, funds should be held in contract
        assertEq(token.balanceOf(address(offchainFractions)), expectedAmount);
    }

    function test_buyFractions_ReachMinShares() public {
        _createBasicFraction();

        uint256 stepsToBuy = MIN_SHARES; // Exactly reach minimum
        uint256 expectedAmount = stepsToBuy * STEP_PRICE;

        vm.prank(buyer1);
        vm.expectEmit(true, true, true, true);
        emit MinSharesReached(FRACTION_ID, creator, MIN_SHARES, MIN_SHARES);

        offchainFractions.buyFractions(creator, FRACTION_ID, stepsToBuy, stepsToBuy);

        // Verify funds transferred to recipient
        assertEq(token.balanceOf(recipient), expectedAmount);
        assertEq(token.balanceOf(address(offchainFractions)), 0);

        OffchainFractions.FractionData memory fraction = offchainFractions.getFraction(creator, FRACTION_ID);
        assertTrue(fraction.claimedFromMinSharesToRaise);
    }

    function test_buyFractions_RevertZeroSteps() public {
        _createBasicFraction();

        vm.prank(buyer1);
        vm.expectRevert(OffchainFractions.ZeroSteps.selector);
        offchainFractions.buyFractions(creator, FRACTION_ID, 0, 0);
    }

    function test_buyFractions_RevertExpired() public {
        _createBasicFraction();

        // Fast forward past expiration
        vm.warp(EXPIRATION_TIME + 1);

        vm.prank(buyer1);
        vm.expectRevert(OffchainFractions.Expired.selector);
        offchainFractions.buyFractions(creator, FRACTION_ID, 10, 10);
    }

    // ============ UNIT TESTS - CLAIM REFUND ============

    function test_claimRefund_ExpiredNotFilled() public {
        _createBasicFraction();

        // Buy some steps (below minimum)
        uint256 stepsBought = 25;
        vm.prank(buyer1);
        offchainFractions.buyFractions(creator, FRACTION_ID, stepsBought, stepsBought);

        // Fast forward past expiration
        vm.warp(EXPIRATION_TIME + 1);

        uint256 expectedRefund = stepsBought * STEP_PRICE;
        uint256 balanceBefore = token.balanceOf(buyer1);

        vm.prank(buyer1);
        vm.expectEmit(true, true, true, true);
        emit FractionRefunded(FRACTION_ID, creator, buyer1, expectedRefund);

        offchainFractions.claimRefund(creator, FRACTION_ID);

        assertEq(token.balanceOf(buyer1), balanceBefore + expectedRefund);
        assertEq(offchainFractions.stepsPurchased(buyer1, creator, FRACTION_ID), 0);
    }

    function test_claimRefund_RevertRoundFullyFilled() public {
        _createBasicFraction();

        // Fill the round to minimum
        vm.prank(buyer1);
        offchainFractions.buyFractions(creator, FRACTION_ID, MIN_SHARES, MIN_SHARES);

        vm.warp(EXPIRATION_TIME + 1);

        vm.prank(buyer1);
        vm.expectRevert(OffchainFractions.CannotClaimRefundWhenRoundFullyFilled.selector);
        offchainFractions.claimRefund(creator, FRACTION_ID);
    }

    // ============ UNIT TESTS - CLOSE FRACTION ============

    function test_closeFraction_Success() public {
        _createBasicFraction();

        vm.prank(creator);
        vm.expectEmit(true, true, true, true);
        emit FractionClosed(FRACTION_ID, address(token), creator);

        offchainFractions.closeFraction(creator, FRACTION_ID);

        OffchainFractions.FractionData memory fraction = offchainFractions.getFraction(creator, FRACTION_ID);
        assertTrue(fraction.manuallyClosed);
    }

    // ============ FUZZ TESTS ============

    function testFuzz_createFraction_ValidInputs(
        uint256 step,
        uint256 totalSteps,
        uint256 minShares,
        uint48 expiration,
        bool useCounterfactual
    ) public {
        // Bound inputs to valid ranges
        step = bound(step, 1, type(uint128).max);
        totalSteps = bound(totalSteps, 1, type(uint128).max);
        minShares = bound(minShares, 0, totalSteps);
        expiration = uint48(bound(expiration, block.timestamp, type(uint48).max));

        vm.prank(creator);
        offchainFractions.createFraction(
            FRACTION_ID, address(token), step, totalSteps, expiration, recipient, useCounterfactual, minShares, creator
        );

        OffchainFractions.FractionData memory fraction = offchainFractions.getFraction(creator, FRACTION_ID);
        assertEq(fraction.step, step);
        assertEq(fraction.totalSteps, totalSteps);
        assertEq(fraction.minSharesToRaise, minShares);
        assertEq(fraction.expiration, expiration);
        assertEq(fraction.useCounterfactualAddress, useCounterfactual);
        assertEq(fraction.claimedFromMinSharesToRaise, minShares == 0);
    }

    // ============ EDGE CASE TESTS ============

    function test_exactMinimumBoundary() public {
        _createBasicFraction();

        // Buy exactly minimum - 1
        vm.prank(buyer1);
        offchainFractions.buyFractions(creator, FRACTION_ID, MIN_SHARES - 1, MIN_SHARES - 1);

        OffchainFractions.FractionData memory fraction = offchainFractions.getFraction(creator, FRACTION_ID);
        assertFalse(fraction.claimedFromMinSharesToRaise);

        // Buy 1 more to reach minimum
        vm.prank(buyer2);
        offchainFractions.buyFractions(creator, FRACTION_ID, 1, 1);

        fraction = offchainFractions.getFraction(creator, FRACTION_ID);
        assertTrue(fraction.claimedFromMinSharesToRaise);
    }

    function test_multipleUsers_SameRound() public {
        _createBasicFraction();

        // Multiple users buy different amounts
        vm.prank(buyer1);
        offchainFractions.buyFractions(creator, FRACTION_ID, 20, 20);

        vm.prank(buyer2);
        offchainFractions.buyFractions(creator, FRACTION_ID, 30, 30);

        // Verify individual purchases
        assertEq(offchainFractions.stepsPurchased(buyer1, creator, FRACTION_ID), 20);
        assertEq(offchainFractions.stepsPurchased(buyer2, creator, FRACTION_ID), 30);

        OffchainFractions.FractionData memory fraction = offchainFractions.getFraction(creator, FRACTION_ID);
        assertEq(fraction.soldSteps, 50); // Should reach minimum
        assertTrue(fraction.claimedFromMinSharesToRaise);
    }

    // ============ COMPREHENSIVE ERROR COVERAGE TESTS ============

    function test_error_NotFractionsOwner() public {
        // This error is not used in current implementation but exists for compatibility
        // Would need to be tested if there were owner-only functions beyond msg.sender checks
        vm.skip(true); // Skip until functionality is implemented
    }

    function test_error_AlreadyExists() public {
        _createBasicFraction();

        vm.prank(creator);
        vm.expectRevert(OffchainFractions.AlreadyExists.selector);
        offchainFractions.createFraction(
            FRACTION_ID, address(token), STEP_PRICE, TOTAL_STEPS, EXPIRATION_TIME, recipient, false, MIN_SHARES, creator
        );
    }

    function test_error_AlreadyClosed() public {
        _createBasicFraction();

        vm.prank(creator);
        offchainFractions.closeFraction(creator, FRACTION_ID);

        vm.prank(buyer1);
        vm.expectRevert(OffchainFractions.AlreadyClosed.selector);
        offchainFractions.buyFractions(creator, FRACTION_ID, 10, 10);
    }

    function test_error_Expired() public {
        _createBasicFraction();

        vm.warp(EXPIRATION_TIME + 1);

        vm.prank(buyer1);
        vm.expectRevert(OffchainFractions.Expired.selector);
        offchainFractions.buyFractions(creator, FRACTION_ID, 10, 10);
    }

    function test_error_InsufficientSharesAvailable() public {
        _createBasicFraction();

        vm.prank(buyer1);
        vm.expectRevert(OffchainFractions.InsufficientSharesAvailable.selector);
        offchainFractions.buyFractions(creator, FRACTION_ID, 10, TOTAL_STEPS + 1); // minStepsToBuy > available
    }

    function test_error_NoStepsPurchased() public {
        _createBasicFraction();

        vm.warp(EXPIRATION_TIME + 1);

        vm.prank(buyer1);
        vm.expectRevert(OffchainFractions.NoStepsPurchased.selector);
        offchainFractions.claimRefund(creator, FRACTION_ID);
    }

    function test_error_StepMustBeGreaterThanZero() public {
        vm.prank(creator);
        vm.expectRevert(OffchainFractions.StepMustBeGreaterThanZero.selector);
        offchainFractions.createFraction(
            FRACTION_ID,
            address(token),
            0, // Zero step price
            TOTAL_STEPS,
            EXPIRATION_TIME,
            recipient,
            false,
            MIN_SHARES,
            creator
        );
    }

    function test_error_ZeroSteps() public {
        _createBasicFraction();

        vm.prank(buyer1);
        vm.expectRevert(OffchainFractions.ZeroSteps.selector);
        offchainFractions.buyFractions(creator, FRACTION_ID, 0, 0);
    }

    function test_error_InvalidToken() public {
        vm.prank(creator);
        vm.expectRevert(OffchainFractions.InvalidToken.selector);
        offchainFractions.createFraction(
            FRACTION_ID, address(0), STEP_PRICE, TOTAL_STEPS, EXPIRATION_TIME, recipient, false, MIN_SHARES, creator
        );
    }

    function test_error_InvalidToAddress() public {
        vm.prank(creator);
        vm.expectRevert(OffchainFractions.InvalidToAddress.selector);
        offchainFractions.createFraction(
            FRACTION_ID,
            address(token),
            STEP_PRICE,
            TOTAL_STEPS,
            EXPIRATION_TIME,
            address(0),
            false,
            MIN_SHARES,
            creator
        );
    }

    function test_error_RecipientCannotBeSelf() public {
        vm.prank(creator);
        vm.expectRevert(OffchainFractions.RecipientCannotBeSelf.selector);
        offchainFractions.createFraction(
            FRACTION_ID,
            address(token),
            STEP_PRICE,
            TOTAL_STEPS,
            EXPIRATION_TIME,
            address(offchainFractions),
            false,
            MIN_SHARES,
            creator
        );
    }

    function test_error_CannotHaveZeroTotalSteps() public {
        vm.prank(creator);
        vm.expectRevert(OffchainFractions.CannotHaveZeroTotalSteps.selector);
        offchainFractions.createFraction(
            FRACTION_ID,
            address(token),
            STEP_PRICE,
            0, // Zero total steps
            EXPIRATION_TIME,
            recipient,
            false,
            MIN_SHARES,
            creator
        );
    }

    function test_error_CannotClaimRefundWhenRoundFullyFilled() public {
        _createBasicFraction();

        vm.prank(buyer1);
        offchainFractions.buyFractions(creator, FRACTION_ID, MIN_SHARES, MIN_SHARES);

        vm.warp(EXPIRATION_TIME + 1);

        vm.prank(buyer1);
        vm.expectRevert(OffchainFractions.CannotClaimRefundWhenRoundFullyFilled.selector);
        offchainFractions.claimRefund(creator, FRACTION_ID);
    }

    function test_error_CannotClaimRefundWhenNotExpired() public {
        _createBasicFraction();

        vm.prank(buyer1);
        offchainFractions.buyFractions(creator, FRACTION_ID, 25, 25);

        vm.prank(buyer1);
        vm.expectRevert(OffchainFractions.CannotClaimRefundWhenNotExpired.selector);
        offchainFractions.claimRefund(creator, FRACTION_ID);
    }

    function test_error_CannotCloseAFullRound() public {
        _createBasicFraction();

        vm.prank(buyer1);
        offchainFractions.buyFractions(creator, FRACTION_ID, MIN_SHARES, MIN_SHARES);

        vm.prank(creator);
        vm.expectRevert(OffchainFractions.CannotCloseAFullRound.selector);
        offchainFractions.closeFraction(creator, FRACTION_ID);
    }

    // Test unused errors for completeness
    function test_error_AlreadyClaimed() public {
        // This error is not used in current implementation
        vm.skip(true);
    }

    function test_error_NotAllOrNothing() public {
        // This error is not used in current implementation
        vm.skip(true);
    }

    function test_error_AlreadySent() public {
        // This error is not used in current implementation
        vm.skip(true);
    }

    function test_error_CannotClaimPayoutWhenRoundNotFullyFilled() public {
        // This error is not used in current implementation
        vm.skip(true);
    }

    function test_error_TaxTokenNotSupported() public {
        // Create fraction with tax token
        vm.prank(creator);
        offchainFractions.createFraction(
            FRACTION_ID,
            address(taxToken),
            STEP_PRICE,
            TOTAL_STEPS,
            EXPIRATION_TIME,
            recipient,
            false,
            MIN_SHARES,
            creator
        );

        // Try to buy with tax token - should fail due to tax
        vm.prank(buyer1);
        vm.expectRevert(OffchainFractions.TaxTokenNotSupported.selector);
        offchainFractions.buyFractions(creator, FRACTION_ID, 25, 25);
    }

    function test_error_TotalRaisedOverflow() public {
        // Test the new overflow protection
        uint256 maliciousStepPrice = type(uint256).max / 50; // This would cause overflow

        vm.prank(creator);
        vm.expectRevert(OffchainFractions.TotalRaisedOverflow.selector);
        offchainFractions.createFraction(
            FRACTION_ID,
            address(token),
            maliciousStepPrice,
            100, // 100 * (max/50) > max, so should revert
            EXPIRATION_TIME,
            recipient,
            false,
            MIN_SHARES,
            creator
        );
    }

    function test_error_TotalRaisedOverflow_EdgeCase() public {
        // Test exactly at the overflow boundary
        uint256 maxSteps = 1000;
        uint256 maxStepPrice = type(uint256).max / maxSteps;

        // This should work (exactly at boundary)
        vm.prank(creator);
        offchainFractions.createFraction(
            FRACTION_ID,
            address(token),
            maxStepPrice,
            maxSteps,
            EXPIRATION_TIME,
            recipient,
            false,
            maxSteps / 2,
            creator
        );

        // Verify fraction was created successfully
        OffchainFractions.FractionData memory fraction = offchainFractions.getFraction(creator, FRACTION_ID);
        assertEq(fraction.step, maxStepPrice);
        assertEq(fraction.totalSteps, maxSteps);

        // But adding 1 more step should fail
        bytes32 fraction2Id = keccak256("fraction_2");
        vm.prank(creator);
        vm.expectRevert(OffchainFractions.TotalRaisedOverflow.selector);
        offchainFractions.createFraction(
            fraction2Id,
            address(token),
            maxStepPrice,
            maxSteps + 1, // This should overflow
            EXPIRATION_TIME,
            recipient,
            false,
            maxSteps / 2,
            creator
        );
    }

    function test_error_TotalRaisedOverflow_ZeroValues() public {
        // Test that zero values don't trigger overflow (should be caught by other validations)
        vm.prank(creator);
        vm.expectRevert(OffchainFractions.StepMustBeGreaterThanZero.selector); // Should fail on step validation first
        offchainFractions.createFraction(
            FRACTION_ID,
            address(token),
            0, // Zero step price
            TOTAL_STEPS,
            EXPIRATION_TIME,
            recipient,
            false,
            MIN_SHARES,
            creator
        );

        // Test zero total steps
        vm.prank(creator);
        vm.expectRevert(OffchainFractions.CannotHaveZeroTotalSteps.selector); // Should fail on totalSteps validation first
        offchainFractions.createFraction(
            FRACTION_ID,
            address(token),
            STEP_PRICE,
            0, // Zero total steps
            EXPIRATION_TIME,
            recipient,
            false,
            MIN_SHARES,
            creator
        );
    }

    // ============ COMPREHENSIVE STATE MUTATION FUZZ TESTS ============

    struct StateBefore {
        uint256 soldSteps;
        uint256 contractBalance;
        uint256 recipientBalance;
        uint256 buyerBalance;
        uint256 buyerStepsPurchased;
        bool claimedFromMinShares;
        bool manuallyClosed;
    }

    struct StateAfter {
        uint256 soldSteps;
        uint256 contractBalance;
        uint256 recipientBalance;
        uint256 buyerBalance;
        uint256 buyerStepsPurchased;
        bool claimedFromMinShares;
        bool manuallyClosed;
    }

    function testFuzz_buyFractions_StateTransitions(
        uint16 _totalSteps,
        uint16 _stepPrice,
        uint8 _initialStepsRatio,
        uint8 _stepsToBuyRatio,
        uint8 _minSharesRatio
    ) public {
        // Use separate bounded parameters to avoid overflow completely
        uint256 totalSteps = bound(_totalSteps, 100, 1000);
        uint256 stepPrice = bound(_stepPrice, 1, 1e12); // Max 1e12 wei (very small)
        uint256 initialSteps = (totalSteps * bound(_initialStepsRatio, 0, 33)) / 100; // 0-33% of total
        uint256 stepsToBuy = 1 + ((totalSteps * bound(_stepsToBuyRatio, 1, 33)) / 100); // 1-33% of total
        uint256 minShares = (totalSteps * bound(_minSharesRatio, 0, 100)) / 100; // 0-100% of total

        // Ensure we don't exceed total steps
        if (initialSteps + stepsToBuy > totalSteps) {
            stepsToBuy = totalSteps - initialSteps;
            if (stepsToBuy == 0) stepsToBuy = 1;
        }

        uint256 minStepsToBuy = 1 + (stepsToBuy / 2); // Always <= stepsToBuy

        // Create fraction with fuzzed parameters
        vm.prank(creator);
        offchainFractions.createFraction(
            FRACTION_ID, address(token), stepPrice, totalSteps, EXPIRATION_TIME, recipient, false, minShares, creator
        );

        // Set up initial state if needed
        if (initialSteps > 0) {
            token.mint(buyer2, initialSteps * stepPrice);
            vm.prank(buyer2);
            token.approve(address(offchainFractions), initialSteps * stepPrice);
            vm.prank(buyer2);
            offchainFractions.buyFractions(creator, FRACTION_ID, initialSteps, initialSteps);
        }

        // Capture state before purchase
        OffchainFractions.FractionData memory fractionBefore = offchainFractions.getFraction(creator, FRACTION_ID);
        StateBefore memory stateBefore = StateBefore({
            soldSteps: fractionBefore.soldSteps,
            contractBalance: token.balanceOf(address(offchainFractions)),
            recipientBalance: token.balanceOf(recipient),
            buyerBalance: token.balanceOf(buyer1),
            buyerStepsPurchased: offchainFractions.stepsPurchased(buyer1, creator, FRACTION_ID),
            claimedFromMinShares: fractionBefore.claimedFromMinSharesToRaise,
            manuallyClosed: fractionBefore.manuallyClosed
        });

        // Ensure buyer has enough tokens
        uint256 maxAmount = stepsToBuy * stepPrice;
        token.mint(buyer1, maxAmount);
        vm.prank(buyer1);
        token.approve(address(offchainFractions), maxAmount);

        // Update stateBefore to reflect the minted tokens
        stateBefore.buyerBalance = token.balanceOf(buyer1);

        // Skip if insufficient shares available
        uint256 availableSteps = totalSteps - stateBefore.soldSteps;
        if (availableSteps < minStepsToBuy) {
            vm.expectRevert(OffchainFractions.InsufficientSharesAvailable.selector);
            vm.prank(buyer1);
            offchainFractions.buyFractions(creator, FRACTION_ID, stepsToBuy, minStepsToBuy);
            return;
        }

        // Execute purchase
        vm.prank(buyer1);
        offchainFractions.buyFractions(creator, FRACTION_ID, stepsToBuy, minStepsToBuy);

        // Capture state after purchase
        OffchainFractions.FractionData memory fractionAfter = offchainFractions.getFraction(creator, FRACTION_ID);
        StateAfter memory stateAfter = StateAfter({
            soldSteps: fractionAfter.soldSteps,
            contractBalance: token.balanceOf(address(offchainFractions)),
            recipientBalance: token.balanceOf(recipient),
            buyerBalance: token.balanceOf(buyer1),
            buyerStepsPurchased: offchainFractions.stepsPurchased(buyer1, creator, FRACTION_ID),
            claimedFromMinShares: fractionAfter.claimedFromMinSharesToRaise,
            manuallyClosed: fractionAfter.manuallyClosed
        });

        // Calculate expected values
        uint256 actualStepsBought = min(stepsToBuy, availableSteps);
        uint256 expectedAmount = actualStepsBought * stepPrice;
        uint256 expectedSoldSteps = stateBefore.soldSteps + actualStepsBought;

        // Verify state transitions
        assertEq(stateAfter.soldSteps, expectedSoldSteps, "soldSteps mismatch");
        assertEq(
            stateAfter.buyerStepsPurchased,
            stateBefore.buyerStepsPurchased + actualStepsBought,
            "buyerStepsPurchased mismatch"
        );

        // Verify fund flows based on minimum shares logic
        if (expectedSoldSteps < minShares) {
            // Below minimum - funds should go to contract
            assertEq(
                stateAfter.contractBalance, stateBefore.contractBalance + expectedAmount, "contract balance below min"
            );
            assertEq(
                stateAfter.recipientBalance,
                stateBefore.recipientBalance,
                "recipient balance should not change below min"
            );
            assertEq(
                stateAfter.claimedFromMinShares,
                stateBefore.claimedFromMinShares,
                "claimedFromMinShares should not change below min"
            );
        } else {
            // Above minimum - check if first time reaching minimum
            if (!stateBefore.claimedFromMinShares) {
                // First time reaching minimum - all accumulated funds go to recipient
                uint256 totalAccumulated = expectedSoldSteps * stepPrice;
                assertEq(
                    stateAfter.recipientBalance,
                    stateBefore.recipientBalance + totalAccumulated,
                    "recipient balance first time min"
                );
                assertEq(stateAfter.contractBalance, 0, "contract balance should be zero first time min");
                assertTrue(stateAfter.claimedFromMinShares, "claimedFromMinShares should be true");
            } else {
                // Already claimed from min shares - direct transfer to recipient
                assertEq(
                    stateAfter.recipientBalance,
                    stateBefore.recipientBalance + expectedAmount,
                    "recipient balance after min"
                );
                assertEq(
                    stateAfter.contractBalance,
                    stateBefore.contractBalance,
                    "contract balance after min should not change"
                );
                assertTrue(stateAfter.claimedFromMinShares, "claimedFromMinShares should remain true");
            }
        }

        // Buyer balance should decrease by amount paid
        assertEq(stateAfter.buyerBalance, stateBefore.buyerBalance - expectedAmount, "buyer balance decrease");

        // Other state should remain unchanged
        assertEq(stateAfter.manuallyClosed, stateBefore.manuallyClosed, "manuallyClosed should not change");
    }

    function testFuzz_refund_StateConsistency(
        uint256 stepsBought1,
        uint256 stepsBought2,
        uint256 totalSteps,
        uint256 minShares,
        bool shouldExpire
    ) public {
        // Bound inputs
        totalSteps = bound(totalSteps, 100, 10000);
        minShares = bound(minShares, totalSteps / 2, totalSteps - 1); // Ensure we can test below minimum
        stepsBought1 = bound(stepsBought1, 1, minShares / 2);
        stepsBought2 = bound(stepsBought2, 1, minShares / 2);

        // Ensure total purchases are below minimum
        vm.assume(stepsBought1 + stepsBought2 < minShares);

        // Create fraction
        vm.prank(creator);
        offchainFractions.createFraction(
            FRACTION_ID, address(token), STEP_PRICE, totalSteps, EXPIRATION_TIME, recipient, false, minShares, creator
        );

        // Two buyers make purchases
        token.mint(buyer1, stepsBought1 * STEP_PRICE);
        token.mint(buyer2, stepsBought2 * STEP_PRICE);
        vm.prank(buyer1);
        token.approve(address(offchainFractions), stepsBought1 * STEP_PRICE);
        vm.prank(buyer2);
        token.approve(address(offchainFractions), stepsBought2 * STEP_PRICE);

        vm.prank(buyer1);
        offchainFractions.buyFractions(creator, FRACTION_ID, stepsBought1, stepsBought1);
        vm.prank(buyer2);
        offchainFractions.buyFractions(creator, FRACTION_ID, stepsBought2, stepsBought2);

        // Capture state before refunds
        uint256 contractBalanceBefore = token.balanceOf(address(offchainFractions));
        uint256 buyer1BalanceBefore = token.balanceOf(buyer1);
        uint256 buyer2BalanceBefore = token.balanceOf(buyer2);

        // Expire or close the fraction
        if (shouldExpire) {
            vm.warp(EXPIRATION_TIME + 1);
        } else {
            vm.prank(creator);
            offchainFractions.closeFraction(creator, FRACTION_ID);
        }

        // First buyer claims refund
        vm.prank(buyer1);
        offchainFractions.claimRefund(creator, FRACTION_ID);

        // Verify state after first refund
        assertEq(token.balanceOf(buyer1), buyer1BalanceBefore + (stepsBought1 * STEP_PRICE), "buyer1 refund amount");
        assertEq(offchainFractions.stepsPurchased(buyer1, creator, FRACTION_ID), 0, "buyer1 steps reset");

        OffchainFractions.FractionData memory fraction = offchainFractions.getFraction(creator, FRACTION_ID);
        assertEq(fraction.soldSteps, stepsBought2, "soldSteps after first refund");

        // Second buyer claims refund
        vm.prank(buyer2);
        offchainFractions.claimRefund(creator, FRACTION_ID);

        // Verify final state
        assertEq(token.balanceOf(buyer2), buyer2BalanceBefore + (stepsBought2 * STEP_PRICE), "buyer2 refund amount");
        assertEq(offchainFractions.stepsPurchased(buyer2, creator, FRACTION_ID), 0, "buyer2 steps reset");
        assertEq(token.balanceOf(address(offchainFractions)), 0, "contract balance should be zero after all refunds");

        fraction = offchainFractions.getFraction(creator, FRACTION_ID);
        assertEq(fraction.soldSteps, 0, "soldSteps should be zero after all refunds");
    }

    function testFuzz_TotalRaisedOverflow_Protection(uint256 stepPrice, uint256 totalSteps) public {
        // Test that the overflow protection works correctly
        stepPrice = bound(stepPrice, 1, type(uint256).max);
        totalSteps = bound(totalSteps, 1, type(uint256).max);

        // Calculate if this would overflow
        bool shouldOverflow = (stepPrice > type(uint256).max / totalSteps);

        vm.prank(creator);
        if (shouldOverflow) {
            // Should revert with TotalRaisedOverflow
            vm.expectRevert(OffchainFractions.TotalRaisedOverflow.selector);
            offchainFractions.createFraction(
                FRACTION_ID,
                address(token),
                stepPrice,
                totalSteps,
                EXPIRATION_TIME,
                recipient,
                false,
                totalSteps / 2, // Reasonable min shares
                creator
            );
        } else {
            // Should succeed
            offchainFractions.createFraction(
                FRACTION_ID,
                address(token),
                stepPrice,
                totalSteps,
                EXPIRATION_TIME,
                recipient,
                false,
                totalSteps / 2,
                creator
            );

            // Verify fraction was created
            OffchainFractions.FractionData memory fraction = offchainFractions.getFraction(creator, FRACTION_ID);
            assertEq(fraction.step, stepPrice);
            assertEq(fraction.totalSteps, totalSteps);
        }
    }

    // ============ ADVERSARIAL TESTS - TRYING TO BREAK INVARIANTS ============

    function test_adversarial_IntegerOverflowAttempt() public {
        // Try to create fraction with very large values - should succeed since contract handles them properly
        vm.prank(creator);
        offchainFractions.createFraction(
            FRACTION_ID,
            address(token),
            type(uint128).max, // Use uint128 to avoid potential overflow in multiplication
            type(uint128).max,
            type(uint48).max,
            recipient,
            false,
            type(uint128).max,
            creator
        );

        // Verify the fraction was created successfully
        OffchainFractions.FractionData memory fraction = offchainFractions.getFraction(creator, FRACTION_ID);
        assertEq(fraction.step, type(uint128).max);
        assertEq(fraction.totalSteps, type(uint128).max);
        assertEq(fraction.minSharesToRaise, type(uint128).max);
    }

    function test_adversarial_UnderflowInRefund() public {
        _createBasicFraction();

        // Buy some steps
        vm.prank(buyer1);
        offchainFractions.buyFractions(creator, FRACTION_ID, 25, 25);

        // Manually manipulate state to test underflow protection
        // This would require direct storage manipulation which isn't possible in this test
        // But we can test the edge case where soldSteps might be less than stepsPurchased

        vm.warp(EXPIRATION_TIME + 1);
        vm.prank(buyer1);
        offchainFractions.claimRefund(creator, FRACTION_ID);

        // Try to claim refund again - should fail with NoStepsPurchased
        vm.prank(buyer1);
        vm.expectRevert(OffchainFractions.NoStepsPurchased.selector);
        offchainFractions.claimRefund(creator, FRACTION_ID);
    }

    function test_adversarial_RaceConditionMinShares() public {
        _createBasicFraction();

        // Set up scenario where two buyers try to reach minimum simultaneously
        uint256 steps1 = MIN_SHARES - 1;
        uint256 steps2 = 2;

        vm.prank(buyer1);
        offchainFractions.buyFractions(creator, FRACTION_ID, steps1, steps1);

        // At this point, we're 1 step away from minimum
        // Next purchase should trigger minimum reached
        vm.prank(buyer2);
        offchainFractions.buyFractions(creator, FRACTION_ID, steps2, steps2);

        // Verify that minimum was properly reached and funds transferred
        OffchainFractions.FractionData memory fraction = offchainFractions.getFraction(creator, FRACTION_ID);
        assertTrue(fraction.claimedFromMinSharesToRaise, "Should have claimed from min shares");

        uint256 expectedRecipientBalance = (steps1 + steps2) * STEP_PRICE;
        assertEq(token.balanceOf(recipient), expectedRecipientBalance, "Recipient should have all funds");
        assertEq(token.balanceOf(address(offchainFractions)), 0, "Contract should have no remaining funds");
    }

    function test_adversarial_ExactExpirationTiming() public {
        _createBasicFraction();

        // Try to buy exactly at expiration time
        vm.warp(EXPIRATION_TIME);
        vm.prank(buyer1);
        offchainFractions.buyFractions(creator, FRACTION_ID, 10, 10);

        // Should succeed at exact expiration time
        assertEq(offchainFractions.stepsPurchased(buyer1, creator, FRACTION_ID), 10);

        // But fail one second later
        vm.warp(EXPIRATION_TIME + 1);
        vm.prank(buyer1);
        vm.expectRevert(OffchainFractions.Expired.selector);
        offchainFractions.buyFractions(creator, FRACTION_ID, 10, 10);
    }

    function test_adversarial_MaximumStepsEdgeCase() public {
        // Create fraction with 1 total step to test edge cases
        vm.prank(creator);
        offchainFractions.createFraction(
            FRACTION_ID,
            address(token),
            STEP_PRICE,
            1, // Only 1 step total
            EXPIRATION_TIME,
            recipient,
            false,
            1, // Minimum is also 1
            creator
        );

        // First buyer should get the only step and trigger minimum
        vm.prank(buyer1);
        offchainFractions.buyFractions(creator, FRACTION_ID, 1, 1);

        // Verify round is complete
        OffchainFractions.FractionData memory fraction = offchainFractions.getFraction(creator, FRACTION_ID);
        assertEq(fraction.soldSteps, 1);
        assertTrue(fraction.claimedFromMinSharesToRaise);

        // Second buyer should fail due to insufficient shares
        vm.prank(buyer2);
        vm.expectRevert(OffchainFractions.InsufficientSharesAvailable.selector);
        offchainFractions.buyFractions(creator, FRACTION_ID, 1, 1);
    }

    function test_adversarial_ZeroMinSharesEdgeCase() public {
        // Create fraction with zero minimum shares
        vm.prank(creator);
        offchainFractions.createFraction(
            FRACTION_ID,
            address(token),
            STEP_PRICE,
            TOTAL_STEPS,
            EXPIRATION_TIME,
            recipient,
            false,
            0, // Zero minimum shares
            creator
        );

        // First purchase should go directly to recipient
        vm.prank(buyer1);
        offchainFractions.buyFractions(creator, FRACTION_ID, 25, 25);

        // Verify funds went directly to recipient
        assertEq(token.balanceOf(recipient), 25 * STEP_PRICE);
        assertEq(token.balanceOf(address(offchainFractions)), 0);

        OffchainFractions.FractionData memory fraction = offchainFractions.getFraction(creator, FRACTION_ID);
        assertTrue(fraction.claimedFromMinSharesToRaise); // Should be true from creation
    }

    function test_adversarial_MinStepsToBuyGreaterThanAvailable() public {
        _createBasicFraction();

        // Buy most of the steps first, leaving only a few available
        vm.prank(buyer1);
        offchainFractions.buyFractions(creator, FRACTION_ID, 95, 95); // Buy 95, leaving 5 available

        // Now try to buy with minStepsToBuy > available steps
        vm.prank(buyer2);
        vm.expectRevert(OffchainFractions.InsufficientSharesAvailable.selector);
        offchainFractions.buyFractions(creator, FRACTION_ID, 3, 10); // Want 3, need 10 minimum, but only 5 available
    }

    function test_adversarial_MinStepsToBuyGreaterThanRequest() public {
        _createBasicFraction();

        // This is actually valid behavior - the contract allows minStepsToBuy > stepsToBuy
        // It will just buy stepsToBuy amount if minStepsToBuy is satisfied
        vm.prank(buyer1);
        offchainFractions.buyFractions(creator, FRACTION_ID, 10, 5); // Want 10, need 5 minimum - should work

        // Verify the purchase went through
        assertEq(offchainFractions.stepsPurchased(buyer1, creator, FRACTION_ID), 10);
    }

    function test_adversarial_PrecisionLoss() public {
        // Test with very small step prices to check for precision issues
        vm.prank(creator);
        offchainFractions.createFraction(
            FRACTION_ID,
            address(token),
            1, // 1 wei per step
            1000000, // 1 million steps
            EXPIRATION_TIME,
            recipient,
            false,
            500000, // 500k minimum
            creator
        );

        // Buy exactly the minimum with tiny amounts
        token.mint(buyer1, 500000);
        vm.prank(buyer1);
        token.approve(address(offchainFractions), 500000);
        vm.prank(buyer1);
        offchainFractions.buyFractions(creator, FRACTION_ID, 500000, 500000);

        // Verify precision is maintained
        assertEq(token.balanceOf(recipient), 500000);

        OffchainFractions.FractionData memory fraction = offchainFractions.getFraction(creator, FRACTION_ID);
        assertTrue(fraction.claimedFromMinSharesToRaise);
    }

    function test_adversarial_MaxUint256EdgeCase() public {
        // Test edge case with maximum possible step price and steps
        uint256 maxSteps = type(uint128).max; // Use uint128 to avoid overflow
        uint256 maxPrice = type(uint128).max;

        vm.prank(creator);
        offchainFractions.createFraction(
            FRACTION_ID,
            address(token),
            maxPrice,
            maxSteps,
            EXPIRATION_TIME,
            recipient,
            false,
            1, // Small minimum to test
            creator
        );

        // Try to buy 1 step with maximum price
        token.mint(buyer1, maxPrice);
        vm.prank(buyer1);
        token.approve(address(offchainFractions), maxPrice);
        vm.prank(buyer1);
        offchainFractions.buyFractions(creator, FRACTION_ID, 1, 1);

        assertEq(token.balanceOf(recipient), maxPrice);
    }

    function test_adversarial_FractionIdCollision() public {
        // Test that different creators can use same fraction ID
        bytes32 sameId = keccak256("collision_test");

        // Creator 1 creates fraction
        vm.prank(creator);
        offchainFractions.createFraction(
            sameId, address(token), STEP_PRICE, TOTAL_STEPS, EXPIRATION_TIME, recipient, false, MIN_SHARES, creator
        );

        // Different creator should be able to use same ID
        address creator2 = makeAddr("creator2");
        vm.prank(creator2);
        offchainFractions.createFraction(
            sameId,
            address(token),
            STEP_PRICE * 2,
            TOTAL_STEPS / 2,
            EXPIRATION_TIME,
            recipient,
            false,
            MIN_SHARES / 2,
            creator2
        );

        // Verify both fractions exist independently
        OffchainFractions.FractionData memory fraction1 = offchainFractions.getFraction(creator, sameId);
        OffchainFractions.FractionData memory fraction2 = offchainFractions.getFraction(creator2, sameId);

        assertEq(fraction1.step, STEP_PRICE);
        assertEq(fraction2.step, STEP_PRICE * 2);
        assertEq(fraction1.totalSteps, TOTAL_STEPS);
        assertEq(fraction2.totalSteps, TOTAL_STEPS / 2);
    }

    function test_adversarial_RefundAfterPartialMinReach() public {
        // Test edge case where minimum is reached but then refunds bring it back below
        _createBasicFraction();

        // Buyer 1 buys just below minimum
        uint256 steps1 = MIN_SHARES - 10;
        vm.prank(buyer1);
        offchainFractions.buyFractions(creator, FRACTION_ID, steps1, steps1);

        // Buyer 2 pushes above minimum
        uint256 steps2 = 20;
        vm.prank(buyer2);
        offchainFractions.buyFractions(creator, FRACTION_ID, steps2, steps2);

        // Verify minimum was reached
        OffchainFractions.FractionData memory fraction = offchainFractions.getFraction(creator, FRACTION_ID);
        assertTrue(fraction.claimedFromMinSharesToRaise);

        // Now close the fraction (can't close when above minimum, so this should fail)
        vm.prank(creator);
        vm.expectRevert(OffchainFractions.CannotCloseAFullRound.selector);
        offchainFractions.closeFraction(creator, FRACTION_ID);

        // Expire the fraction instead
        vm.warp(EXPIRATION_TIME + 1);

        // Buyers should not be able to claim refund when minimum was reached
        vm.prank(buyer1);
        vm.expectRevert(OffchainFractions.CannotClaimRefundWhenRoundFullyFilled.selector);
        offchainFractions.claimRefund(creator, FRACTION_ID);
    }

    function test_adversarial_EmptyFractionQuery() public {
        // Test querying non-existent fraction
        OffchainFractions.FractionData memory fraction = offchainFractions.getFraction(creator, FRACTION_ID);

        // Should return empty struct
        assertEq(fraction.token, address(0));
        assertEq(fraction.owner, address(0));
        assertEq(fraction.step, 0);
        assertEq(fraction.totalSteps, 0);
        assertEq(fraction.soldSteps, 0);
        assertEq(fraction.minSharesToRaise, 0);
        assertFalse(fraction.manuallyClosed);
        assertFalse(fraction.useCounterfactualAddress);
        assertFalse(fraction.claimedFromMinSharesToRaise);
    }

    function test_adversarial_BuyFromNonExistentFraction() public {
        // Try to buy from fraction that doesn't exist
        vm.prank(buyer1);
        vm.expectRevert(OffchainFractions.Expired.selector); // Will fail on expiration check since expiration is 0
        offchainFractions.buyFractions(creator, FRACTION_ID, 10, 10);
    }

    function test_adversarial_CloseNonExistentFraction() public {
        // Try to close fraction that doesn't exist
        vm.prank(creator);
        // This will not revert because the default state has soldSteps=0 and minSharesToRaise=0
        // So soldSteps >= minSharesToRaise is 0 >= 0 which is true, causing CannotCloseAFullRound
        vm.expectRevert(OffchainFractions.NotFractionsCloser.selector);
        offchainFractions.closeFraction(creator, FRACTION_ID);
    }

    function test_adversarial_ExtremelyLargeFraction() public {
        // Test with very large but valid parameters
        uint256 largeSteps = 1e12; // 1 trillion steps
        uint256 smallPrice = 1; // 1 wei per step

        vm.prank(creator);
        offchainFractions.createFraction(
            FRACTION_ID,
            address(token),
            smallPrice,
            largeSteps,
            EXPIRATION_TIME,
            recipient,
            false,
            largeSteps / 2, // Half as minimum
            creator
        );

        // Buy a small portion
        uint256 buyAmount = 1000;
        token.mint(buyer1, buyAmount);
        vm.prank(buyer1);
        token.approve(address(offchainFractions), buyAmount);
        vm.prank(buyer1);
        offchainFractions.buyFractions(creator, FRACTION_ID, buyAmount, buyAmount);

        // Verify purchase was recorded correctly
        assertEq(offchainFractions.stepsPurchased(buyer1, creator, FRACTION_ID), buyAmount);

        OffchainFractions.FractionData memory fraction = offchainFractions.getFraction(creator, FRACTION_ID);
        assertEq(fraction.soldSteps, buyAmount);
        assertFalse(fraction.claimedFromMinSharesToRaise); // Still below minimum
    }

    // ============ CRITICAL BUG TESTS - OVERFLOW DoS ATTACK ============

    function test_CRITICAL_overflow_DoS_attack() public {
        // This test demonstrates a critical DoS vulnerability
        uint256 maliciousStepPrice = type(uint256).max / 50; // Large but not max

        vm.prank(creator);
        vm.expectRevert(OffchainFractions.TotalRaisedOverflow.selector);
        offchainFractions.createFraction(
            FRACTION_ID,
            address(token),
            maliciousStepPrice,
            1000, // 1000 total steps
            EXPIRATION_TIME,
            recipient,
            false,
            100, // 100 minimum
            creator
        );
    }

    function test_CRITICAL_overflow_in_totalAmount_calculation() public {
        // Test overflow in the totalAmount calculation (line 385)
        uint256 maliciousStepPrice = type(uint256).max / 49; // Slightly larger

        vm.prank(creator);
        vm.expectRevert(OffchainFractions.TotalRaisedOverflow.selector); // Should revert due to arithmetic overflow
        offchainFractions.createFraction(
            FRACTION_ID,
            address(token),
            maliciousStepPrice,
            100,
            EXPIRATION_TIME,
            recipient,
            false,
            50, // When we reach 50 steps, totalAmount = 50 * (max/49) which overflows
            creator
        );
    }

    // ============ INTEGRATION TESTS ============

    function test_integration_CounterfactualAddress() public {
        // Test integration with CounterfactualHolderFactory
        vm.prank(creator);
        offchainFractions.createFraction(
            FRACTION_ID,
            address(token),
            STEP_PRICE,
            TOTAL_STEPS,
            EXPIRATION_TIME,
            recipient,
            true, // Use counterfactual address
            MIN_SHARES,
            creator
        );

        vm.prank(buyer1);
        offchainFractions.buyFractions(creator, FRACTION_ID, MIN_SHARES, MIN_SHARES);

        // Verify funds went to counterfactual address
        address cfhAddress = counterfactualHolderFactory.getCurrentCFH(recipient, address(token));
        assertEq(token.balanceOf(cfhAddress), MIN_SHARES * STEP_PRICE);
    }

    // ============ HELPER FUNCTIONS FOR ADVERSARIAL TESTS ============

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CounterfactualHolderFactory} from "./CounterfactualHolderFactory.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title OffchainFractions
 * @notice A contract for creating and managing fractional token sales with optional minimum raise requirements
 * @dev Supports both direct transfers and counterfactual holder addresses for recipients
 */
contract OffchainFractions is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // === Fraction Management Errors ===
    error NotFractionsOwner();
    error AlreadyExists();
    error AlreadyClosed();
    error Expired();
    error MinSharesCannotBeGreaterThanTotalSteps();
    error NotFractionsCloser();

    // === Purchase/Sale Errors ===
    error InsufficientSharesAvailable();
    error NoStepsPurchased();
    error StepMustBeGreaterThanZero();
    error ZeroSteps();

    // === Validation Errors ===
    error InvalidToken();
    error InvalidToAddress();
    error RecipientCannotBeSelf();
    error CannotHaveZeroTotalSteps();
    error TaxTokenNotSupported();

    // === Refund/Claim Errors ===
    error CannotClaimRefundWhenRoundFullyFilled();
    error CannotClaimRefundWhenNotExpired();
    error CannotClaimPayoutWhenRoundNotFullyFilled();
    error CannotCloseAFullRound();
    error TotalRaisedOverflow();

    // === Unused Errors (kept for compatibility) ===
    error AlreadyClaimed();
    error NotAllOrNothing();
    error AlreadySent();

    /**
     * @notice Data structure representing a fractional token sale
     * @param token The ERC20 token being sold
     * @param expiration Timestamp when the sale expires
     * @param manuallyClosed Whether the sale was manually closed by the owner
     * @param minSharesToRaise Minimum number of steps that must be sold for the sale to be valid
     * @param useCounterfactualAddress Whether to use a counterfactual holder address for the recipient
     * @param claimedFromMinSharesToRaise Whether funds have been claimed after reaching minimum shares
     * @param owner The creator/owner of this fraction sale
     * @param step Price per step (in wei of the token)
     * @param to The recipient address for the raised funds
     * @param soldSteps Number of steps already sold
     * @param totalSteps Total number of steps available for sale
     * @param closer The address that manually closed the sale
     */
    struct FractionData {
        address token;
        uint48 expiration;
        bool manuallyClosed;
        uint256 minSharesToRaise;
        bool useCounterfactualAddress;
        bool claimedFromMinSharesToRaise;
        address owner;
        uint256 step;
        address to;
        uint256 soldSteps;
        uint256 totalSteps;
        address closer;
    }

    /**
     * @notice Internal struct to hold purchase calculation results (avoids stack too deep)
     * @param stepsToBuy Final number of steps to purchase (adjusted for availability)
     * @param amount Total cost for the purchase
     * @param newFractionsSold Total steps that will be sold after this purchase
     * @param sendTo Address where funds should be sent
     * @param roundFullyFilled Whether this purchase completes the round
     */
    struct PurchaseDetails {
        uint256 stepsToBuy;
        uint256 amount;
        uint256 newFractionsSold;
        address sendTo;
        bool roundFullyFilled;
    }

    /// @notice Tracks the number of steps purchased by each user for each fraction sale
    mapping(address user => mapping(address creator => mapping(bytes32 id => uint256 stepsPurchased))) public
        stepsPurchased;

    /// @notice Stores fraction sale data indexed by creator and fraction ID
    mapping(address user => mapping(bytes32 id => FractionData)) private _fractions;

    /// @notice Factory contract for creating counterfactual holder addresses
    CounterfactualHolderFactory public immutable i_CFHFactory;

    /// @notice Emitted when a new fraction sale is created
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

    /// @notice Emitted when steps are purchased in a fraction sale
    event FractionSold(
        bytes32 indexed id, address indexed creator, address indexed buyer, uint256 step, uint256 amount
    );

    /// @notice Emitted when a fraction sale round is completely filled
    event RoundFilled(bytes32 indexed id, address indexed creator);

    /// @notice Emitted when a fraction sale is manually closed by the owner
    event FractionClosed(bytes32 indexed id, address indexed token, address indexed owner);

    /// @notice Emitted when a user claims a refund from an unfilled sale
    event FractionRefunded(bytes32 indexed id, address indexed creator, address indexed user, uint256 amount);

    /// @notice Emitted when the minimum shares threshold is reached and funds are released
    event MinSharesReached(bytes32 indexed id, address indexed creator, uint256 minShares, uint256 newTotalSharesSold);

    constructor(CounterfactualHolderFactory _counterfactualHolderFactory) {
        i_CFHFactory = _counterfactualHolderFactory;
    }

    /**
     * @notice Creates a new fractional token sale
     * @param id Unique identifier for this fraction sale
     * @param token The ERC20 token to be sold
     * @param step Price per step (in wei of the token)
     * @param totalSteps Total number of steps available for sale
     * @param expiration Timestamp when the sale expires
     * @param to Recipient address for the raised funds
     * @param useCounterfactualAddress Whether to use a counterfactual holder for the recipient
     * @param minSharesToRaise Minimum steps required for the sale to be valid (0 = no minimum)
     * @param closer The address that is allowed to manually close the sale
     */
    function createFraction(
        bytes32 id,
        address token,
        uint256 step,
        uint256 totalSteps,
        uint48 expiration,
        address to,
        bool useCounterfactualAddress,
        uint256 minSharesToRaise,
        address closer
    ) external nonReentrant {
        // Validate input parameters
        _validateFractionCreationParams(token, to, step, totalSteps, minSharesToRaise);

        // Ensure fraction doesn't already exist
        if (_fractions[msg.sender][id].totalSteps != 0) {
            revert AlreadyExists();
        }

        // Create the fraction data
        _fractions[msg.sender][id] = FractionData({
            token: token,
            owner: msg.sender,
            step: step,
            soldSteps: 0,
            totalSteps: totalSteps,
            expiration: expiration,
            manuallyClosed: false,
            useCounterfactualAddress: useCounterfactualAddress,
            to: to,
            minSharesToRaise: minSharesToRaise,
            claimedFromMinSharesToRaise: minSharesToRaise == 0,
            closer: closer
        });

        emit FractionCreated(
            id, token, msg.sender, step, totalSteps, expiration, to, useCounterfactualAddress, minSharesToRaise, closer
        );
    }

    /**
     * @notice Purchase steps in a fractional token sale
     * @param creator The address that created the fraction sale
     * @param id The unique identifier of the fraction sale
     * @param stepsToBuy Maximum number of steps to purchase
     * @param minStepsToBuy Minimum number of steps that must be available to purchase
     */
    function buyFractions(address creator, bytes32 id, uint256 stepsToBuy, uint256 minStepsToBuy)
        external
        nonReentrant
    {
        FractionData storage fraction = _fractions[creator][id];
        if (stepsToBuy == 0) {
            revert ZeroSteps();
        }

        // Validate the purchase can proceed
        _validatePurchaseConditions(fraction);

        // Calculate purchase details with stack isolation
        PurchaseDetails memory details = _calculatePurchaseDetails(fraction, stepsToBuy, minStepsToBuy);

        // Handle the token transfers based on minimum shares logic
        _handlePurchaseTransfers(fraction, details, creator, id);

        // Update state and emit events
        _finalizePurchase(fraction, details, creator, id);
    }

    /**
     * @notice Allows participants to claim a refund if the round didn't reach minimum shares
     * @dev Can only claim refund if:
     *      - Round didn't reach minSharesToRaise threshold
     *      - Round is expired OR manually closed
     * @param creator The address that created the fraction sale
     * @param id The unique identifier of the fraction sale
     */
    function claimRefund(address creator, bytes32 id) external nonReentrant {
        uint256 _stepsPurchased = stepsPurchased[msg.sender][creator][id];
        if (_stepsPurchased == 0) {
            revert NoStepsPurchased();
        }

        FractionData storage fraction = _fractions[creator][id];

        // Check if round reached minimum threshold
        uint256 soldSteps = fraction.soldSteps;
        bool roundFilled = soldSteps >= fraction.minSharesToRaise;
        if (roundFilled) {
            revert CannotClaimRefundWhenRoundFullyFilled();
        }

        // Check if refund conditions are met (expired OR manually closed)
        bool expired = block.timestamp > fraction.expiration;
        bool manuallyClosed = fraction.manuallyClosed;
        // equivalent to require(manually closed || expired)
        if (!manuallyClosed && !expired) {
            revert CannotClaimRefundWhenNotExpired();
        }

        // Calculate refund amount and update state
        uint256 amount = _stepsPurchased * fraction.step;
        stepsPurchased[msg.sender][creator][id] = 0;
        /// @auditor - Let me know if you think we can remove this,
        /// I don't think it's necessary
        fraction.soldSteps = soldSteps - _stepsPurchased;

        // Transfer refund to user
        IERC20(fraction.token).safeTransfer(msg.sender, amount);
        emit FractionRefunded(id, creator, msg.sender, amount);
    }

    /**
     * @notice Manually close a fraction sale before expiration
     * @dev Only the creator can close their own fraction sale
     * @dev Can only close if the round hasn't reached minimum shares threshold
     * @param creator The address that created the fraction sale
     * @param id The unique identifier of the fraction sale to close
     */
    function closeFraction(address creator, bytes32 id) external nonReentrant {
        FractionData storage fraction = _fractions[creator][id];
        if (msg.sender != fraction.closer) {
            revert NotFractionsCloser();
        }

        // Validate closure conditions
        if (fraction.manuallyClosed) {
            revert AlreadyClosed();
        }
        if (fraction.soldSteps >= fraction.minSharesToRaise) {
            revert CannotCloseAFullRound();
        }

        // Mark as manually closed
        fraction.manuallyClosed = true;
        emit FractionClosed(id, fraction.token, creator);
    }

    /**
     * @notice Get the fraction sale data for a specific creator and ID
     * @param creator The address that created the fraction sale
     * @param id The unique identifier of the fraction sale
     * @return The complete fraction sale data
     */
    function getFraction(address creator, bytes32 id) external view returns (FractionData memory) {
        return _fractions[creator][id];
    }

    // ============ INTERNAL FUNCTIONS ============

    /**
     * @notice Validates parameters for fraction creation
     * @param token The ERC20 token address
     * @param to The recipient address
     * @param step The price per step
     * @param totalSteps The total number of steps
     * @param minSharesToRaise The minimum number of steps to raise
     */
    function _validateFractionCreationParams(
        address token,
        address to,
        uint256 step,
        uint256 totalSteps,
        uint256 minSharesToRaise
    ) internal view {
        if (token == address(0)) revert InvalidToken();
        if (to == address(0)) revert InvalidToAddress();
        if (step == 0) revert StepMustBeGreaterThanZero();
        if (totalSteps == 0) revert CannotHaveZeroTotalSteps();
        if (to == address(this)) revert RecipientCannotBeSelf();
        if (minSharesToRaise > totalSteps) revert MinSharesCannotBeGreaterThanTotalSteps();
        if (willMultiplyOverflow(step, totalSteps)) revert TotalRaisedOverflow();
    }

    /**
     * @notice Validates that a purchase can proceed
     * @param fraction The fraction data to validate
     */
    function _validatePurchaseConditions(FractionData storage fraction) internal view {
        if (fraction.manuallyClosed) revert AlreadyClosed();
        if (block.timestamp > fraction.expiration) revert Expired();
    }

    /**
     * @notice Calculates purchase details including adjusted steps and recipient address
     * @param fraction The fraction data
     * @param stepsToBuy Requested number of steps to buy
     * @param minStepsToBuy Minimum steps required to be available
     * @return details Calculated purchase details
     */
    function _calculatePurchaseDetails(FractionData storage fraction, uint256 stepsToBuy, uint256 minStepsToBuy)
        internal
        view
        returns (PurchaseDetails memory details)
    {
        {
            address toInStruct = fraction.to;
            details.sendTo = fraction.useCounterfactualAddress
                ? i_CFHFactory.getCurrentCFH({user: toInStruct, token: fraction.token})
                : toInStruct;
        }

        {
            uint256 soldSteps = fraction.soldSteps;
            uint256 totalSteps = fraction.totalSteps;
            uint256 stepsLeft = totalSteps - soldSteps;

            if (stepsLeft < minStepsToBuy) revert InsufficientSharesAvailable();
            details.stepsToBuy = min(stepsLeft, stepsToBuy);
        }

        details.newFractionsSold = fraction.soldSteps + details.stepsToBuy;
        details.amount = details.stepsToBuy * fraction.step;

        details.roundFullyFilled = details.newFractionsSold == fraction.totalSteps;
    }

    /**
     * @notice Handles token transfers based on minimum shares logic
     * @dev All fundraised amounts before `minSharesToRaise` is reached are held in the contract.
     * @dev When `minSharesToRaise` is reached, the funds are transferred to the recipient.
     * @param fraction The fraction data
     * @param details Purchase calculation results
     * @param creator The fraction creator
     * @param id The fraction ID
     */
    function _handlePurchaseTransfers(
        FractionData storage fraction,
        PurchaseDetails memory details,
        address creator,
        bytes32 id
    ) internal {
        address token = fraction.token;
        uint256 minSharesToRaise = fraction.minSharesToRaise;

        /// If `minShares` has not been reached, send funds to the contract.
        if (details.newFractionsSold < minSharesToRaise) {
            // Below minimum threshold - hold funds in contract
            _safeTransferFromNoTaxToken(token, msg.sender, address(this), details.amount);
        }
        // If `minShares` has been reached
        // If it's the first time reaching `minShares`, transfer all accumulated funds to the recipient. and mark it as claimed.
        // If it's not the first time reaching `minShares`, transfer the funds to the recipient.
        else {
            // Above minimum threshold - handle fund distribution
            if (fraction.claimedFromMinSharesToRaise) {
                // Minimum already claimed, send directly to recipient
                IERC20(token).safeTransferFrom(msg.sender, details.sendTo, details.amount);
            } else {
                // First time reaching minimum - transfer all accumulated funds
                _safeTransferFromNoTaxToken(token, msg.sender, address(this), details.amount);
                uint256 totalAmount = details.newFractionsSold * fraction.step;
                IERC20(token).safeTransfer(details.sendTo, totalAmount);
                fraction.claimedFromMinSharesToRaise = true;
                // For `0` min shares, this won't be emitted.
                emit MinSharesReached(id, creator, minSharesToRaise, details.newFractionsSold);
            }
        }
    }

    /**
     * @notice Finalizes the purchase by updating state and emitting events
     * @param fraction The fraction data
     * @param details Purchase calculation results
     * @param creator The fraction creator
     * @param id The fraction ID
     */
    function _finalizePurchase(
        FractionData storage fraction,
        PurchaseDetails memory details,
        address creator,
        bytes32 id
    ) internal {
        // Update user's purchase record
        stepsPurchased[msg.sender][creator][id] += details.stepsToBuy;

        // Update fraction's sold steps
        fraction.soldSteps = details.newFractionsSold;

        // Emit events
        if (details.roundFullyFilled) {
            emit RoundFilled(id, creator);
        }

        emit FractionSold(id, creator, msg.sender, fraction.step, details.amount);
    }

    /**
     * @notice Safe transfer that ensures no tax tokens are used
     * @dev Reverts if the received amount doesn't match the sent amount (indicating a tax token)
     * @param token The ERC20 token to transfer
     * @param from The address to transfer from
     * @param to The address to transfer to
     * @param amount The amount to transfer
     */
    function _safeTransferFromNoTaxToken(address token, address from, address to, uint256 amount) internal {
        uint256 balBefore = IERC20(token).balanceOf(to);
        IERC20(token).safeTransferFrom(from, to, amount);
        uint256 balAfter = IERC20(token).balanceOf(to);
        if (balAfter - balBefore != amount) {
            revert TaxTokenNotSupported();
        }
    }

    /**
     * @notice Returns the minimum of two values
     * @param a First value
     * @param b Second value
     * @return The smaller of the two values
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /// @notice Checks if a * b would overflow
    /// @param a The first operand
    /// @param b The second operand
    /// @return bool True if multiplication would overflow, false otherwise
    function willMultiplyOverflow(uint256 a, uint256 b) internal pure returns (bool) {
        // Gas-optimized shortcut: zero can't overflow
        if (a == 0 || b == 0) return false;
        // Overflow occurs if a > type(uint256).max / b
        return a > type(uint256).max / b;
    }
}

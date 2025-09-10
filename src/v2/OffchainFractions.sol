// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CounterfactualHolderFactory} from "./CounterfactualHolderFactory.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract OffchainFractions is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error NotFractionsOwner();
    error MaxStepsReached();
    error Expired();
    error AlreadyClosed();
    error AlreadyExists();
    error CannotHaveZeroTotalSteps();
    error TaxTokenNotSupported();
    error AlreadyClaimed();
    error NotAllOrNothing();

    error AlreadySent();
    error CannotClaimRefundWhenRoundFullyFilled();
    error CannotClaimRefundWhenNotExpired();
    error CannotClaimPayoutWhenRoundNotFullyFilled();

    error InvalidToken();
    error InvalidToAddress();
    error NoStepsPurchased();
    error CannotCloseAFullRound();
    error StepMustBeGreaterThanZero();

    error RecipientCannotBeSelf();

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
    }

    mapping(address user => mapping(address creator => mapping(bytes32 id => uint256 stepsPurchased))) public
        stepsPurchased;
    mapping(address user => mapping(bytes32 id => FractionData)) private _fractions;

    CounterfactualHolderFactory public immutable i_CFHFactory;

    event FractionCreated(
        bytes32 indexed id,
        address indexed token,
        address indexed owner,
        uint256 step,
        uint256 totalSteps,
        uint48 expiration,
        address to,
        bool useCounterfactualAddress,
        uint256 minSharesToRaise
    );
    event FractionSold(
        bytes32 indexed id, address indexed creator, address indexed buyer, uint256 step, uint256 amount
    );
    event RoundFilled(bytes32 indexed id, address indexed creator);
    event FractionClosed(bytes32 indexed id, address indexed token, address indexed owner);
    event FractionRefunded(bytes32 indexed id, address indexed creator, address indexed user, uint256 amount);
    event MinSharesReached(bytes32 indexed id, address indexed creator, uint256 minShares, uint256 newTotalSharesSold);

    constructor(CounterfactualHolderFactory _counterfactualHolderFactory) {
        i_CFHFactory = _counterfactualHolderFactory;
    }

    function createFraction(
        bytes32 id,
        address token,
        uint256 step,
        uint256 totalSteps,
        uint48 expiration,
        address to,
        bool useCounterfactualAddress,
        uint256 minSharesToRaise
    ) external nonReentrant {
        if (token == address(0)) {
            revert InvalidToken();
        }
        if (to == address(0)) {
            revert InvalidToAddress();
        }
        if (step == 0) {
            revert StepMustBeGreaterThanZero();
        }
        if (totalSteps == 0) {
            revert CannotHaveZeroTotalSteps();
        }
        if (to == address(this)) {
            revert RecipientCannotBeSelf();
        }

        if (_fractions[msg.sender][id].totalSteps != 0) {
            revert AlreadyExists();
        }
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
            claimedFromMinSharesToRaise: minSharesToRaise == 0 ? true : false
        });
        emit FractionCreated(
            id, token, msg.sender, step, totalSteps, expiration, to, useCounterfactualAddress, minSharesToRaise
        );
    }

    function buyFractions(address creator, bytes32 id, uint256 stepsToBuy) external nonReentrant {
        FractionData storage fraction = _fractions[creator][id];
        if (fraction.manuallyClosed) {
            revert AlreadyClosed();
        }
        if (block.timestamp > fraction.expiration) {
            revert Expired();
        }
        address token = fraction.token;
        address toInStruct = fraction.to;
        uint256 step = fraction.step;
        address sendTo = fraction.useCounterfactualAddress
            ? i_CFHFactory.getCurrentCFH({user: toInStruct, token: token})
            : toInStruct;
        uint256 amount = stepsToBuy * step;
        uint256 soldSteps = fraction.soldSteps;
        uint256 newFractionsSold = soldSteps + stepsToBuy;
        uint256 minSharesToRaise = fraction.minSharesToRaise;

        if (newFractionsSold > fraction.totalSteps) {
            revert MaxStepsReached();
        }

        bool roundFullyFilled = newFractionsSold == fraction.totalSteps;

        if (roundFullyFilled) {
            emit RoundFilled(id, creator);
        }

        if (newFractionsSold < minSharesToRaise) {
            _safeTransferFromNoTaxToken(token, msg.sender, address(this), amount);
        } else {
            if (fraction.claimedFromMinSharesToRaise) {
                IERC20(token).safeTransferFrom(msg.sender, sendTo, amount);
            } else {
                _safeTransferFromNoTaxToken(token, msg.sender, address(this), amount);
                uint256 totalAmount = newFractionsSold * step;
                IERC20(token).safeTransfer(sendTo, totalAmount);
            }

            fraction.claimedFromMinSharesToRaise = true;
            emit MinSharesReached(id, creator, minSharesToRaise, newFractionsSold);
        }

        stepsPurchased[msg.sender][creator][id] += stepsToBuy;
        fraction.soldSteps = newFractionsSold;
        emit FractionSold(id, creator, msg.sender, step, amount);
    }

    /// @dev Allows participants to claim a refund if the round is not fully filled
    /// @dev Only applies to `allOrNothing` rounds
    /// @dev Can only claim the refund if the round is not fully filled AND if the round is expired
    /// @dev The round is considered expired when the expiration timestamp is in the past
    ///       - OR if the round is manually closed
    function claimRefund(address creator, bytes32 id) external nonReentrant {
        uint256 _stepsPurchased = stepsPurchased[msg.sender][creator][id];
        if (_stepsPurchased == 0) {
            revert NoStepsPurchased();
        }
        FractionData storage fraction = _fractions[creator][id];

        uint256 soldSteps = fraction.soldSteps;
        bool roundFilled = soldSteps >= fraction.minSharesToRaise;
        if (roundFilled) {
            revert CannotClaimRefundWhenRoundFullyFilled();
        }
        bool expired = block.timestamp > fraction.expiration;
        bool manuallyClosed = fraction.manuallyClosed;
        //Users cant claim if not expired, unless it's manually closed
        if (!manuallyClosed) {
            if (!expired) {
                revert CannotClaimRefundWhenNotExpired();
            }
        }

        uint256 amount = _stepsPurchased * fraction.step;
        stepsPurchased[msg.sender][creator][id] = 0;
        fraction.soldSteps = soldSteps - _stepsPurchased;
        IERC20(fraction.token).safeTransfer(msg.sender, amount);
        emit FractionRefunded(id, creator, msg.sender, amount);

        // If not past expiration
    }

    //// @dev No need to check if the sender is the owner
    function closeFraction(bytes32 id) external {
        FractionData storage fraction = _fractions[msg.sender][id];

        if (fraction.manuallyClosed) {
            revert AlreadyClosed();
        }
        if (fraction.soldSteps >= fraction.minSharesToRaise) {
            revert CannotCloseAFullRound();
        }

        fraction.manuallyClosed = true;
        emit FractionClosed(id, fraction.token, msg.sender);
    }

    function getFraction(address creator, bytes32 id) external view returns (FractionData memory) {
        return _fractions[creator][id];
    }

    function _safeTransferFromNoTaxToken(address token, address from, address to, uint256 amount) internal {
        uint256 balBefore = IERC20(token).balanceOf(to);
        IERC20(token).safeTransferFrom(from, to, amount);
        uint256 balAfter = IERC20(token).balanceOf(to);
        if (balAfter - balBefore != amount) {
            revert TaxTokenNotSupported();
        }
    }
}

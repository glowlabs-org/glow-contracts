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

    struct FractionData {
        address token;
        address owner;
        uint256 step;
        address to;
        bool useCounterfactualAddress;
        uint256 soldSteps;
        uint256 totalSteps;
        uint48 expiration;
        bool manuallyClosed;
    }

    mapping(address user => mapping(bytes32 id => uint256 amountPurchased)) public amountPurchased;
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
        bool useCounterfactualAddress
    );
    event FractionSold(bytes32 indexed id, address indexed token, address indexed owner, uint256 step, uint256 amount);
    event FractionClosed(bytes32 indexed id, address indexed token, address indexed owner);

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
        bool useCounterfactualAddress
    ) external nonReentrant {
        if (_fractions[msg.sender][id].totalSteps != 0) {
            revert AlreadyExists();
        }
        if (totalSteps == 0) {
            revert CannotHaveZeroTotalSteps();
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
            to: to
        });
        emit FractionCreated(id, token, msg.sender, step, totalSteps, expiration, to, useCounterfactualAddress);
    }

    function buyFractions(bytes32 id, uint256 stepsToBuy) external nonReentrant {
        FractionData storage fraction = _fractions[msg.sender][id];
        if (fraction.manuallyClosed) {
            revert AlreadyClosed();
        }
        if (block.timestamp > fraction.expiration) {
            revert Expired();
        }
        address token = fraction.token;
        address toInStruct = fraction.to;
        address sendTo = fraction.useCounterfactualAddress
            ? i_CFHFactory.getCurrentCFH({user: toInStruct, token: token})
            : toInStruct;
        uint256 amount = stepsToBuy * fraction.step;
        uint256 newFractionsSold = fraction.soldSteps + stepsToBuy;
        if (newFractionsSold > fraction.totalSteps) {
            revert MaxStepsReached();
        }
        IERC20(fraction.token).safeTransferFrom(msg.sender, sendTo, amount);
        fraction.soldSteps = newFractionsSold;
        amountPurchased[msg.sender][id] += amount;
        emit FractionSold(id, fraction.token, msg.sender, fraction.step, amount);
    }

    function closeFraction(bytes32 id) external {
        FractionData storage fraction = _fractions[msg.sender][id];
        if (fraction.owner != msg.sender) {
            revert NotFractionsOwner();
        }
        if (fraction.manuallyClosed) {
            revert AlreadyClosed();
        }
        fraction.manuallyClosed = true;
        emit FractionClosed(id, fraction.token, msg.sender);
    }

    function getFraction(address creator, bytes32 id) external view returns (FractionData memory) {
        return _fractions[creator][id];
    }
}

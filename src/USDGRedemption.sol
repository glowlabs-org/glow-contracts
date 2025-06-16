// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {USDG} from "@/USDG.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract USDGRedemption is ReentrancyGuard {
    using SafeCast for *;

    error NotAuthorized();
    error NotWithdrawGuardian();
    error CircuitBreakerActive();
    error CallerNotWithdrawPositionOwner();
    error ClaimTooEarly();

    USDG internal immutable i_USDG;
    address internal immutable i_WITHDRAW_GUARDIAN;
    address internal constant BURN_ADDRESS = 0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF;
    uint256 internal constant WITHDRAW_DELAY = 2 weeks;

    uint256 public $nextWithdrawPositionId;

    mapping(address => bool) internal $authorized;
    mapping(uint256 id => WithdrawPosition) internal $withdrawPositions;

    struct WithdrawPosition {
        uint128 amount;
        uint128 aomuntClaimed;
        uint40 releaseTimestamp;
        address owner;
    }

    // struct Queue

    event WithdrawPositionOpened(uint256 id, WithdrawPosition pos);

    constructor(USDG _usdg, address withdrawGuardian) payable {
        i_USDG = _usdg;
        i_WITHDRAW_GUARDIAN = withdrawGuardian;
    }

    function createWithdrawPosition(uint256 amount) public nonReentrant {
        _checkAuthorized(msg.sender);
        _checkCircuitBreakerActive();
        i_USDG.transferFrom(msg.sender, BURN_ADDRESS, amount);
        uint256 withdrawId = $nextWithdrawPositionId++;

        // INSERT_YOUR_CODE
        WithdrawPosition memory pos = WithdrawPosition({
            amount: amount.toUint128(),
            releaseTimestamp: (block.timestamp + WITHDRAW_DELAY).toUint40(),
            owner: msg.sender
        });
        $withdrawPositions[withdrawId] = pos;
        emit WithdrawPositionOpened(withdrawId, pos);
    }

    function _withdraw(uint256 positionId, uint256 amountToClaim) internal {
        _checkAuthorized(msg.sender);
        _checkCircuitBreakerActive();
        WithdrawPosition storage pos = $WithdrawPosition[positionId];
        if (pos.owner != msg.sender) revert CallerNotWithdrawPositionOwner();
        if (block.timestamp < pos.releaseTimestamp) revert ClaimTooEarly();
        pos.aomuntClaimed += amountToClaim; //TODO: Make sure covered upstream
    }

    function authorize(address a, bool status) public {
        _checkWithdrawGuardian();
        $authorized[a] = status;
    }

    function authorizeBulk(address[] calldata addrs, bool status) public {
        _checkWithdrawGuardian();
        uint256 len = addrs.length;
        for (uint256 i = 0; i < len; ++i) {
            $authorized[addrs[i]] = status;
        }
    }

    function isAuthorized(address a) public view returns (bool) {
        return $authorized[a];
    }

    function withdrawGuardian() public view returns (address) {
        return i_WITHDRAW_GUARDIAN;
    }

    function USDGToken() public view returns (USDG) {
        return i_USDG;
    }

    function _checkAuthorized(address a) internal view {
        if (!isAuthorized(a)) revert NotAuthorized();
    }

    function _checkWithdrawGuardian() internal view {
        if (msg.sender != withdrawGuardian()) revert NotWithdrawGuardian();
    }

    function circuitBreakerActive() public view returns (bool) {
        return i_USDG.permanentlyFreezeTransfers();
    }

    function _checkCircuitBreakerActive() internal {
        if (circuitBreakerActive()) revert CircuitBreakerActive();
    }
}

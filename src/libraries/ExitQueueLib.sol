// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {RevertLib} from "@glowswap/libraries/RevertLib.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ArithmeticLib} from "@glowswap/libraries/ArithmeticLib.sol";

/// @title Exit Queue Library
/// @notice Generic queue that releases ERC-20 liquidity over time while guaranteeing FIFO access for earlier positions.
/// @dev Modeled after LiquidityQueueLib but simplified for an ERC-20 single-asset exit queue.
library ExitQueueLib {
    using RevertLib for bytes4;
    using SafeCast for *;
    using ArithmeticLib for *;

    ///////////////////////////////////////////////
    ///////////////////  ERRORS  //////////////////
    ///////////////////////////////////////////////

    /// @notice Not enough unclaimed amount left in the position.
    error InsufficientExitRemaining();

    /// @notice Global progress has not yet advanced far enough for this position.
    error InsufficientAvailable();

    /// @notice Caller is not the owner of the position.
    error CallerNotExitOwner();

    /// @notice Position does not exist or has been closed.
    error NonexistentOrClosedPosition();

    /// @notice Position cannot be claimed before its release timestamp.
    error ReleaseTimeNotReached();

    /// @notice totalAvailableCumSum cannot ever exceed the total amount requested by the queue.
    error AvailableCannotBeGreaterThanTotalRequested();

    ///////////////////////////////////////////////
    /////////////////// STRUCTS ///////////////////
    ///////////////////////////////////////////////

    /**
     * @notice Represents a single exit request in the queue.
     * @param owner            Address that owns (and can claim) this position.
     * @param amount           Total tokens originally requested to exit.
     * @param amountClaimed    Amount already claimed from the position.
     * @param releaseTimestamp UNIX timestamp after which the position becomes claimable.
     * @param startClaimAmount Snapshot of State.totalRequested *before* this position was inserted. Guarantees FIFO.
     */
    struct Position {
        address owner;
        uint128 amount;
        uint128 amountClaimed;
        uint64 releaseTimestamp;
        uint256 startClaimAmount;
    }

    /**
     * @notice Global queue state.
     * @param totalRequested       Cumulative outstanding amount requested by all active positions.
     * @param totalAvailableCumSum Monotonically increasing counter of tokens that have become available for exit.
     * @param totalClaimed         Aggregate tokens claimed out of the queue so far.
     */
    struct State {
        uint256 totalRequested;
        uint256 totalAvailableCumSum;
        uint256 totalClaimed;
    }

    ///////////////////////////////////////////////
    /////////////////// EVENTS ////////////////////
    ///////////////////////////////////////////////

    /// @notice Emitted whenever new liquidity becomes available to the queue.
    /// @param added Amount by which `totalAvailableCumSum` increased.
    event ExitQueueUpdateAvailable(uint256 added);

    /// @notice Emitted when a new exit position is opened.
    /// @param positionId Unique identifier chosen by the caller (e.g. incremental id in parent contract).
    /// @param position   Full details of the newly created position.
    event ExitQueuePositionOpen(uint256 indexed positionId, Position position);

    /// @notice Emitted when a position claims tokens.
    /// @param positionId  The id of the position claiming.
    /// @param amountClaimed  The number of tokens claimed in this operation.
    event ExitQueuePositionClaim(uint256 indexed positionId, uint256 amountClaimed);

    ///////////////////////////////////////////////
    ////////////////// FUNCTIONS ///////////////////
    ///////////////////////////////////////////////

    /**
     * @notice Opens a new exit position in the queue.
     * @param state      Storage reference to global queue state.
     * @param position   Storage reference where the position will be stored (e.g. positions[positionId]).
     * @param positionId Id used only for the emitted event.
     * @param amount     Amount of tokens to exit.
     * @param releaseTimestamp Timestamp at which the position becomes eligible to claim.
     */
    function requestExit(
        State storage state,
        Position storage position,
        uint256 positionId,
        uint128 amount,
        uint64 releaseTimestamp
    ) internal {
        position.owner = msg.sender;
        position.amount = amount;
        position.amountClaimed = 0;
        position.releaseTimestamp = releaseTimestamp;
        position.startClaimAmount = state.totalRequested;

        state.totalRequested = state.totalRequested + uint256(amount);

        emit ExitQueuePositionOpen(positionId, position);
    }

    /**
     * @notice Adds newly available tokens to the queue.
     * @dev MUST only be called by the parent contract when it has **actually** made tokens available.
     *      Invariant: `state.totalAvailableCumSum` must never exceed `state.totalRequested`.
     * @param state              Global state struct.
     * @param amountToAdd        Tokens that became available.
     */
    function dangerouslyIncreaseTotalAvailable(State storage state, uint256 amountToAdd) internal {
        uint256 newTotalAvailable = state.totalAvailableCumSum + amountToAdd;
        if (newTotalAvailable > state.totalRequested) {
            AvailableCannotBeGreaterThanTotalRequested.selector.selfRevert();
        }
        state.totalAvailableCumSum = newTotalAvailable;
        emit ExitQueueUpdateAvailable(amountToAdd);
    }

    /**
     * @notice Claims `amountToClaim` tokens from an exit position.
     * @dev Reverts with detailed custom errors if any requirement is violated.
     * @param state          Global queue state reference.
     * @param position       Position to claim from (should be positions[positionId]).
     * @param positionId     Position id for event emission.
     * @param amountToClaim  Desired amount to claim.
     */
    function claim(State storage state, Position storage position, uint256 positionId, uint128 amountToClaim)
        internal
    {
        _checkCanClaim(state, position, msg.sender, amountToClaim);

        // Update position
        uint128 newClaimed = position.amountClaimed + amountToClaim;
        position.amountClaimed = newClaimed;

        // Close position if fully claimed
        if (newClaimed == position.amount) {
            position.owner = address(0);
        }

        // Update global accounting
        state.totalClaimed = state.totalClaimed + uint256(amountToClaim);

        emit ExitQueuePositionClaim(positionId, amountToClaim);
    }

    /**
     * @notice External helper that checks whether a claim is possible and reverts otherwise.
     */
    function _checkCanClaim(State storage state, Position storage position, address sender, uint256 amountToClaim)
        private
        view
    {
        (bool ok, bytes4 err) = _canClaim(state, position, sender, amountToClaim);
        if (!ok) err.selfRevert();
    }

    /**
     * @notice Pure validation logic that determines if a claim would succeed.
     * @return success True if claim would succeed.
     * @return errorSelector Error selector explaining failure reason when `success` is false.
     */
    function _canClaim(State storage state, Position storage position, address sender, uint256 amountToClaim)
        private
        view
        returns (bool success, bytes4 errorSelector)
    {
        // Position must exist and be open
        address ownerCached = position.owner;
        if (ownerCached == address(0)) {
            return (false, NonexistentOrClosedPosition.selector);
        }

        // Must be owner
        if (sender != ownerCached) {
            return (false, CallerNotExitOwner.selector);
        }

        // Release timestamp reached
        if (block.timestamp < position.releaseTimestamp) {
            return (false, ReleaseTimeNotReached.selector);
        }

        // Cannot claim more than remaining
        uint256 remaining = position.amount - position.amountClaimed;
        if (amountToClaim > remaining) {
            return (false, InsufficientExitRemaining.selector);
        }

        // Ensure enough global availability for FIFO guarantee
        uint256 minRequired = position.startClaimAmount + position.amountClaimed + amountToClaim;
        if (state.totalAvailableCumSum < minRequired) {
            return (false, InsufficientAvailable.selector);
        }

        return (true, bytes4(0));
    }

    ///////////////////////////////////////////////
    ///////////////// VIEW HELPERS ////////////////
    ///////////////////////////////////////////////

    /// @notice Returns amount reserved (yet to be claimed) across all positions.
    function getReserved(State storage state) internal view returns (uint256) {
        return state.totalRequested - state.totalClaimed;
    }

    /// @notice Returns tokens available to claim right now across all positions.
    function getGloballyAvailableToClaim(State storage state) internal view returns (uint256) {
        return state.totalAvailableCumSum.saturatingSub(state.totalClaimed);
    }
}

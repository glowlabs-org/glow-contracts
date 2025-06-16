// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {USDG} from "@glow/USDG.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {LiquidityQueueLib} from "@glowswap/core/libraries/LiquidityQueueLib.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";


//TODO: Need to be able to get USDC out
contract USDGRedemption is ReentrancyGuard,Multicall {
    using SafeCast for *;
    using SafeERC20 for *;
    using LiquidityQueueLib for *;

    error NotAuthorized();
    error NotWithdrawGuardian();
    error CircuitBreakerActive();
    error ClaimTooEarly();
    error ZeroAddressNotAllowed();
    error ZeroNotAllowed();

    ///////////////////////////////////////////////
    /////////////////// EVENTS /////////////////////
    ///////////////////////////////////////////////

    /// @notice Emitted when USDC liquidity is topped up.
    /// @param caller The address providing the USDC liquidity.
    /// @param amount The actual amount of USDC transferred in and credited to the queue progress.
    event RedemptionLiquidityToppedUp(address indexed caller, uint256 amount);

    /// @notice Emitted when a new USDG redemption position is created.
    /// @param positionId The id assigned to the withdraw position.
    /// @param owner The owner of the position.
    /// @param amountRequested The amount of USDG burned / USDC requested.
    /// @param releaseTimestamp The timestamp after which the position can be claimed.
    event WithdrawPositionCreated(uint256 indexed positionId, address indexed owner, uint256 amountRequested, uint256 releaseTimestamp);

    /// @notice Emitted when USDC is claimed from an existing withdraw position.
    /// @param positionId The id of the position.
    /// @param owner The owner of the position (caller).
    /// @param amountClaimed The amount of USDC transferred in this claim.
    /// @param cumulativeAmountWithdrawn The cumulative amount withdrawn from this position after the claim.
    /// @param positionClosed Whether the position is now fully withdrawn/closed.
    event WithdrawPositionClaimed(uint256 indexed positionId, address indexed owner, uint256 amountClaimed, uint256 cumulativeAmountWithdrawn, bool positionClosed);

    /// @notice Emitted whenever an address's authorization status is changed.
    /// @param account The address whose status was updated.
    /// @param status True if authorized, false if de-authorized.
    event AuthorizationUpdated(address indexed account, bool status);

    // solhint-disable-next-line private-vars-leading-underscore
    USDG internal immutable i_USDG;

    // solhint-disable-next-line private-vars-leading-underscore
    IERC20 internal immutable i_USDC;

    // solhint-disable-next-line private-vars-leading-underscore
    address internal immutable i_WITHDRAW_GUARDIAN;


    // solhint-disable-next-line private-vars-leading-underscore
    address internal constant BURN_ADDRESS = 0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF;

    // solhint-disable-next-line private-vars-leading-underscore
    uint256 internal constant WITHDRAW_DELAY = 2 weeks;

    // solhint-disable-next-line private-vars-leading-underscore
    LiquidityQueueLib.State internal $liquidityQueue;

    // Tracks the next position id to assign when users create a new withdraw request
    // solhint-disable-next-line private-vars-leading-underscore
    uint256 internal $nextWithdrawPositionId;

    // solhint-disable-next-line private-vars-leading-underscore
    mapping(address => bool) internal $authorized;

    // solhint-disable-next-line private-vars-leading-underscore
    mapping(uint256 withdrawId => uint256 releaseTimestamp) internal $positionWithdrawTimestamp;

    // solhint-disable-next-line private-vars-leading-underscore
    mapping(uint256 withdrawId => LiquidityQueueLib.Position) internal $positions;


    constructor(USDG _usdg, IERC20 _usdc, address withdrawGuardian) payable {
        if (address(_usdg) == address(0)) revert ZeroAddressNotAllowed();
        if (address(_usdc) == address(0)) revert ZeroAddressNotAllowed();
        if (withdrawGuardian == address(0)) revert ZeroAddressNotAllowed();
        i_USDG = _usdg;
        i_USDC = _usdc;
        i_WITHDRAW_GUARDIAN = withdrawGuardian;
    }

    /// @notice Tops up the redemption contract with USDC liquidity.
    /// @dev This moves USDC from the caller into the contract and immediately credits it towards
    ///      the queue's `liquidityProgress` (up to what is currently pending).
    /// @param maxAmount The maximum amount of USDC the caller is willing to contribute.
    function topUpLiquidity(uint256 maxAmount) public nonReentrant {
        uint256 amountLeftInQueue = $liquidityQueue.getPendingLiquidityInQueue();
        uint256 amountToRequest = _min(maxAmount, amountLeftInQueue);
        if(amountToRequest == 0) return;
        i_USDC.safeTransferFrom(msg.sender, address(this), amountToRequest);
        $liquidityQueue.dangerouslyUpdateLiquidityProgress(amountToRequest);
        emit RedemptionLiquidityToppedUp(msg.sender, amountToRequest);
    }

    /// @notice Burns `amount` of USDG and opens a new withdrawal position in the queue.
    /// @dev Transfers USDG from the caller and burns it, then creates a queue position that can
    ///      be claimed after `WITHDRAW_DELAY` once sufficient queue progress is made.
    /// @param amount The amount of USDG the caller wishes to redeem for USDC.
    function createWithdrawPosition(uint256 amount) public nonReentrant {
        if(amount == 0) revert ZeroNotAllowed();
        _checkAuthorized(msg.sender);
        _checkCircuitBreakerActive();
        i_USDG.transferFrom(msg.sender, BURN_ADDRESS, amount);

        uint256 posId = $nextWithdrawPositionId++;
        LiquidityQueueLib.Position storage pos = $positions[posId];
        pos.owner = msg.sender;

        // Enforce the mandatory delay before the position can be claimed
        $positionWithdrawTimestamp[posId] = block.timestamp + WITHDRAW_DELAY;

        $liquidityQueue.requestLiquidity({
            position: pos,
            positionId: posId,
            liquidityRequested: amount.toUint128(),
            dangerousExcessFreeLiquidity: 0
        });

        emit WithdrawPositionCreated(posId, msg.sender, amount, $positionWithdrawTimestamp[posId]);
    }


    /// @notice Claims as much USDC as currently available for the given position.
    /// @param positionId The id of the withdraw position.
    /// @return amountClaimed The amount of USDC that was transferred to the caller.
    function withdraw(uint256 positionId) external nonReentrant returns (uint256 amountClaimed) {
        amountClaimed = _withdraw(positionId);
    }

    function _withdraw(uint256 positionId) internal returns (uint256 amountClaimed)  {
        _checkAuthorized(msg.sender);
        _checkCircuitBreakerActive();

        // Ensure the mandatory delay has elapsed
        uint256 releaseTs = $positionWithdrawTimestamp[positionId];
        if (block.timestamp < releaseTs) revert ClaimTooEarly();
        LiquidityQueueLib.Position storage pos = $positions[positionId];

        // Derive the amount that can be claimed: the minimum of what is left in the position
        // and what is currently available to be claimed in the queue.
        uint256 amountLeftToWithdraw = uint256(pos.liquidityRequested) - uint256(pos.amountWithdrawn);
        uint256 amountAvailableToClaim = $liquidityQueue.getLiquidityAvailableToClaim();

        amountClaimed = _min(amountLeftToWithdraw, amountAvailableToClaim);

        // Revert if nothing can be claimed (saves gas and avoids needless calls)
        if (amountClaimed == 0) {
            revert LiquidityQueueLib.InsufficientLiquidityInQueue();
        }

        // Will revert internally if the claim is not allowed (insufficient queue progress, etc.)
        $liquidityQueue.claimLiquidity(pos, amountClaimed.toUint128());

        // Transfer out USDC to the claimer
        i_USDC.safeTransfer(msg.sender, amountClaimed);

        emit WithdrawPositionClaimed(positionId, msg.sender, amountClaimed, uint256(pos.amountWithdrawn), pos.owner == address(0));
    }

    /// @notice Grants or revokes `a` the ability to open redemption positions.
    /// @dev Only callable by the designated withdraw guardian.
    /// @param a The address to update.
    /// @param status Whether the address should be authorized (`true`) or de-authorized (`false`).
    function authorize(address a, bool status) public {
        _checkWithdrawGuardian();
        $authorized[a] = status;
        emit AuthorizationUpdated(a, status);
    }

    /// @notice Bulk version of {authorize}.
    /// @param addrs The list of addresses to update.
    /// @param status The authorization status to set for each address.
    function authorizeBulk(address[] calldata addrs, bool status) public {
        _checkWithdrawGuardian();
        uint256 len = addrs.length;
        for (uint256 i = 0; i < len; ++i) {
            $authorized[addrs[i]] = status;
            emit AuthorizationUpdated(addrs[i], status);
        }
    }

    /// @notice Returns whether `a` is allowed to create withdraw positions.
    function isAuthorized(address a) public view returns (bool) {
        return $authorized[a];
    }

    /// @notice Returns the current withdraw guardian.
    function withdrawGuardian() public view returns (address) {
        return i_WITHDRAW_GUARDIAN;
    }

    /// @notice Returns the USDG token contract.
    function USDGToken() public view returns (USDG) {
        return i_USDG;
    }

    /// @notice Returns the USDC token contract.
    function USDCToken() public view returns (IERC20) {
        return i_USDC;
    }

    /// @notice Returns the constant burn address used for USDG burns.
    function burnAddress() public pure returns (address) {
        return BURN_ADDRESS;
    }

    /// @notice Returns the mandatory delay (in seconds) before a position can be claimed.
    function withdrawDelay() public pure returns (uint256) {
        return WITHDRAW_DELAY;
    }

    /// @notice Returns the next position id that will be assigned.
    function nextWithdrawPositionId() public view returns (uint256) {
        return $nextWithdrawPositionId;
    }

    /// @notice Returns queue-level statistics.
    /// @return totalLiquidityRequested The total liquidity ever requested and still outstanding.
    /// @return liquidityProgress How much liquidity has been fulfilled so far.
    /// @return totalClaimed How much liquidity has been claimed by users.
    function getLiquidityQueueState()
        public
        view
        returns (uint256 totalLiquidityRequested, uint256 liquidityProgress, uint256 totalClaimed)
    {
        LiquidityQueueLib.State storage s = $liquidityQueue;
        return (s.totalLiquidityRequested, s.liquidityProgress, s.totalClaimed);
    }

    /// @notice Returns the details of a withdraw position.
    /// @param positionId The id of the position.
    /// @return position The position struct.
    /// @return releaseTimestamp The timestamp after which the position can be claimed.
    function getWithdrawPosition(uint256 positionId)
        public
        view
        returns (LiquidityQueueLib.Position memory position, uint256 releaseTimestamp)
    {
        position = $positions[positionId];
        releaseTimestamp = $positionWithdrawTimestamp[positionId];
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

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
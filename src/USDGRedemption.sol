// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {USDG} from "./USDG.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title USDGRedemption
 * @notice Enables users to redeem USDG for USDC on a 1:1 basis and allows a designated
 *         withdraw guardian to manage USDC reserves.
 * @dev    Relies on OpenZeppelin's ReentrancyGuard and SafeERC20 utilities for safe
 *         external calls and token transfers.
 */
contract USDGRedemption is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Zero amount or zero address supplied where a positive, non-zero value is required.
    error ZeroNotAllowed();

    /// @notice Caller is not the authorised withdraw guardian.
    error NotWithdrawGuardian();

    /// @notice Circuit-breaker is not permanently switched on.
    error CircuitBreakerNotOn();

    /// @notice Thrown when a claim amount of zero is supplied where a positive, non-zero value is required.
    error ClaimZeroNotAllowed();
    /// @notice Thrown when the USDC balance is zero and an operation requiring a positive balance is attempted.
    error ZeroUSDCBalance();

    /// @dev USDG sent to this address is considered burned
    // solhint-disable-next-line private-vars-leading-underscore
    address internal constant BURN_ADDRESS = 0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF;

    /// @notice USDG token being redeemed.
    // solhint-disable-next-line private-vars-leading-underscore
    USDG internal immutable i_USDG;

    /// @notice USDC token backing USDG redemptions.
    // solhint-disable-next-line private-vars-leading-underscore
    IERC20 internal immutable i_USDC;

    /// @notice Address authorised to withdraw USDC reserves held by this contract.
    // solhint-disable-next-line private-vars-leading-underscore
    address internal immutable i_WITHDRAW_GUARDIAN;

    /// @notice Emitted after a successful redemption.
    /// @param user        Address that performed the redemption.
    /// @param amountUSDG  Amount of USDG redeemed.
    event Exchanged(address indexed user, uint256 amountUSDG);

    /// @notice Emitted whenever USDC is withdrawn from the contract.
    /// @param to      Recipient of the withdrawn USDC.
    /// @param amount  Amount of USDC withdrawn.
    event Withdrawn(address indexed to, uint256 amount);

    /// @param usdg             Address of the USDG token to be redeemed.
    /// @param usdc             Address of the USDC token used for redemptions.
    /// @param withdrawGuardian Address authorised to withdraw USDC funds.
    /// @dev   Reverts with {ZeroNotAllowed} if any parameter is the zero address.
    constructor(USDG usdg, IERC20 usdc, address withdrawGuardian) payable {
        if (address(usdg) == address(0) || address(usdc) == address(0) || withdrawGuardian == address(0)) {
            revert ZeroNotAllowed();
        }
        i_USDG = usdg;
        i_USDC = usdc;
        i_WITHDRAW_GUARDIAN = withdrawGuardian;
    }

    /// @notice Redeem `amountUSDG` of USDG for an equal amount of USDC.
    /// @param amountUSDG Amount of USDG to redeem.
    /// @dev    Transfers USDG from `msg.sender` to {BURN_ADDRESS} and sends the same
    ///         amount of USDC back to the caller. Reverts with {ZeroNotAllowed} if
    ///         `amountUSDG` is zero.
    function exchange(uint256 amountUSDG) public nonReentrant {
        if (amountUSDG == 0) {
            revert ZeroNotAllowed();
        }
        // Burn USDG from sender
        IERC20(address(i_USDG)).safeTransferFrom(msg.sender, BURN_ADDRESS, amountUSDG);

        // Transfer USDC to sender 1:1
        i_USDC.safeTransfer(msg.sender, amountUSDG);

        emit Exchanged(msg.sender, amountUSDG);
    }

    /// @notice Withdraw up to `amount` of USDC to the withdraw guardian.
    /// @param amount Requested withdrawal amount. Clamped to the contract's USDC balance.
    /// @dev    Only callable by the designated withdraw guardian. Emits {Withdrawn}.
    function withdrawUSDC(uint256 amount) public nonReentrant {
        if (amount == 0) revert ClaimZeroNotAllowed();
        if (msg.sender != i_WITHDRAW_GUARDIAN) {
            revert NotWithdrawGuardian();
        }
        uint256 bal = i_USDC.balanceOf(address(this));
        if (bal == 0) revert ZeroUSDCBalance();
        if (amount > bal) {
            amount = bal;
        }
        i_USDC.safeTransfer(i_WITHDRAW_GUARDIAN, amount);
        emit Withdrawn(i_WITHDRAW_GUARDIAN, amount);
    }

    /// @notice Withdraws **all** USDC reserves when the USDG circuit-breaker is permanently on.
    /// @dev Anyone can call this function
    /// @dev Emits {Withdrawn}.
    // solhint-disable-next-line func-name-mixedcase
    function withdrawUSDC_CircuitBreakerOn() public nonReentrant {
        bool circuitBreakerOn = i_USDG.permanentlyFreezeTransfers();
        if (!circuitBreakerOn) revert CircuitBreakerNotOn();
        uint256 bal = i_USDC.balanceOf(address(this));
        if (bal == 0) revert ZeroUSDCBalance();
        i_USDC.safeTransfer(i_WITHDRAW_GUARDIAN, bal);
        emit Withdrawn(i_WITHDRAW_GUARDIAN, bal);
    }

    /// @notice Returns the USDG token contract.
    function usdgToken() public view returns (USDG) {
        return i_USDG;
    }

    /// @notice Returns the withdraw guardian address.
    function withdrawGuardian() public view returns (address) {
        return i_WITHDRAW_GUARDIAN;
    }

    /// @notice Returns the USDC token contract.
    function usdcToken() public view returns (IERC20) {
        return i_USDC;
    }
}

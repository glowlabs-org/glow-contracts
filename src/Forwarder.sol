// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {USDG} from "@/USDG.sol";
import {CounterfactualSwapper} from "@/CounterfactualSwapper.sol";

contract Forwarder is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error MaxLengthExceeded();
    error ZeroAmount();

    uint256 private constant _MAX_LENGTH = 400;

    USDG public immutable i_USDG;
    IERC20 public immutable i_USDC;

    uint256 public nextNonce;

    constructor(USDG _usdg, IERC20 _usdc) payable {
        i_USDG = _usdg;
        i_USDC = _usdc;
    }

    event Forward(address indexed from, address indexed to, address indexed token, uint256 amount, string message);

    function forward(address token, address to, uint256 amount, string calldata message) external nonReentrant {
        _checkAmountAndLength(amount, message);
        SafeERC20.safeTransferFrom(IERC20(token), msg.sender, to, amount);
        emit Forward(msg.sender, to, token, amount, message);
    }

    /// @dev Swaps USDC for USDG and forwards the USDG to the recipient.
    /// @dev USDG has a `guard` that does not allow it to be transferred to a non-approved contract.
    /// This contract is not approved. We use a counterfactual swapper to swap USDC for USDG.
    /// The counterfactual swapper performs a swap for USDC -> USDG and then forwards the USDG to the recipient in its constructor
    /// This works because contracts have no bytecode during construction.
    /// @param amount The amount of USDC to swap.
    /// @param to The address to forward the USDG to.
    /// @param message The message to forward.
    function swapUSDCAndForwardUSDG(uint256 amount, address to, string calldata message) external nonReentrant {
        _checkAmountAndLength(amount, message);
        uint256 nonce = nextNonce;
        address counterfactualSwapper = _predictCounterfactualSwapper(nonce, amount, to);

        i_USDC.safeTransferFrom(msg.sender, counterfactualSwapper, amount);

        new CounterfactualSwapper{salt: bytes32(nonce)}(i_USDG, i_USDC, amount, to);

        nextNonce = nonce + 1;

        emit Forward(msg.sender, to, address(i_USDG), amount, message);
    }

    /// @dev Predict the CREATE2 address for CounterfactualSwapper with the given salt/args.
    function _predictCounterfactualSwapper(uint256 nonce, uint256 amount, address to)
        internal
        view
        returns (address predicted)
    {
        bytes32 salt = bytes32(nonce);

        // init code = creationCode ++ abi.encode(constructor args)
        bytes memory initCode =
            abi.encodePacked(type(CounterfactualSwapper).creationCode, abi.encode(i_USDG, i_USDC, amount, to));

        bytes32 initCodeHash = keccak256(initCode);

        // EIP-1014: keccak256(0xff ++ deployer ++ salt ++ keccak256(init_code))[12:]
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash));

        predicted = address(uint160(uint256(hash)));
    }

    function _checkAmountAndLength(uint256 amount, string calldata message) internal pure {
        if (amount == 0) {
            revert ZeroAmount();
        }
        if (bytes(message).length > _MAX_LENGTH) {
            revert MaxLengthExceeded();
        }
    }
}

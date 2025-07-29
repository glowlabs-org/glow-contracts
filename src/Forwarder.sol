// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Forwarder is ReentrancyGuard {
    error MaxLengthExceeded();
    error ZeroAmount();

    uint256 private constant _MAX_LENGTH = 400;

    event Forward(address indexed from, address indexed to, address indexed token, uint256 amount, string message);

    function forward(address token, address to, uint256 amount, string calldata message) external nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }
        if (bytes(message).length > _MAX_LENGTH) {
            revert MaxLengthExceeded();
        }
        SafeERC20.safeTransferFrom(IERC20(token), msg.sender, to, amount);
        emit Forward(msg.sender, to, token, amount, message);
    }
}

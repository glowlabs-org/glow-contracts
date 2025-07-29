// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract USDCForwarder is ReentrancyGuard {
    address public immutable usdc;
    address public immutable FORWARD_ADDRESS;

    event Forward(address indexed from, address indexed to, uint256 amount, string message);

    constructor(address _usdc, address _usdcForwarder) {
        usdc = _usdc;
        FORWARD_ADDRESS = _usdcForwarder;
    }

    function forward(uint256 amount, string memory message) external nonReentrant {
        SafeERC20.safeTransferFrom(IERC20(usdc), msg.sender, FORWARD_ADDRESS, amount);
        emit Forward(msg.sender, FORWARD_ADDRESS, amount, message);
    }
}

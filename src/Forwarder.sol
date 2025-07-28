// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Forwarder {
    event Forward(address indexed from, address indexed to, address indexed token, uint256 amount, string message);
     

    function forward(address token, address to, uint256 amount, string memory message) external {
        SafeERC20.safeTransferFrom(IERC20(token), msg.sender, to, amount);
        emit Forward(msg.sender, to, token, amount, message);
    }
}

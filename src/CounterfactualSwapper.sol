// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {USDG} from "@/USDG.sol";


contract CounterfactualSwapper is ReentrancyGuard {
    constructor(USDG _usdg, IERC20 _usdc, uint256 amount, address to) payable {
        _usdc.approve(address(_usdg), type(uint256).max);
        _usdg.swap(to, amount);
    }
}

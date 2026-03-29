// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";
import {CounterfactualHolderFactory} from "./CounterfactualHolderFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UniV2Swapper {
    constructor(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes memory data,
        CounterfactualHolderFactory factory
    ) payable {}
}

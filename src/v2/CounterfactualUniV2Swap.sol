// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {CounterfactualHolderFactory} from "./CounterfactualHolderFactory.sol";
import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";
import {IUniswapRouterV2} from "../interfaces/IUniswapRouterV2.sol";
import {Call} from "./Structs.sol";
import {USDG as USDGToken} from "../USDG.sol";

contract CounterfactualUniV2Swap {
    using SafeERC20 for IERC20;

    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 public constant GLOW = IERC20(0xf4fbC617A5733EAAF9af08E1Ab816B103388d8B6);
    USDGToken public constant USDG = USDGToken(0xe010ec500720bE9EF3F82129E7eD2Ee1FB7955F2);

    CounterfactualHolderFactory public constant CFH_FACTORY =
        CounterfactualHolderFactory(0x5bB7eC88cA80146FF47019079Cf0330532A1157F);
    IUniswapRouterV2 public constant ROUTER = IUniswapRouterV2(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    constructor(uint256 amountIn, uint256 amountOutMin, address[] memory path, address to, uint256 deadline) {
        if (path[0] == address(USDC)) {
            USDC.approve(address(USDG), type(uint256).max);
            USDG.swap({to: address(this), amount: amountIn});
            path[0] = address(USDG);
        }

        IERC20(path[0]).approve(address(ROUTER), type(uint256).max);
        uint256[] memory amounts =
            ROUTER.swapExactTokensForTokens(amountIn, amountOutMin, path, address(this), deadline);

        IERC20(path[1]).approve(address(CFH_FACTORY), type(uint256).max);
        CFH_FACTORY.transferToCFH(to, path[1], amounts[1]);
    }
}

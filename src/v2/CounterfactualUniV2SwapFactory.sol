// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {CounterfactualHolderFactory} from "./CounterfactualHolderFactory.sol";
import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";
import {IUniswapRouterV2} from "../interfaces/IUniswapRouterV2.sol";
import {Call} from "./Structs.sol";
import {USDG as USDGToken} from "../USDG.sol";
import {CounterfactualUniV2Swap} from "./CounterfactualUniV2Swap.sol";

contract CounterfactualUniV2SwapFactory {
    using SafeERC20 for IERC20;

    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 public constant GLOW = IERC20(0xf4fbC617A5733EAAF9af08E1Ab816B103388d8B6);
    USDGToken public constant USDG = USDGToken(0xe010ec500720bE9EF3F82129E7eD2Ee1FB7955F2);

    CounterfactualHolderFactory public constant CFH_FACTORY =
        CounterfactualHolderFactory(0x5bB7eC88cA80146FF47019079Cf0330532A1157F);
    IUniswapRouterV2 public constant ROUTER = IUniswapRouterV2(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    uint256 public nextSalt;

    function predictAddress(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline,
        uint256 salt
    ) public view returns (address) {
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(CounterfactualUniV2Swap).creationCode, abi.encode(amountIn, amountOutMin, path, to, deadline)
            )
        );
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), bytes32(salt), initCodeHash))))
        );
    }

    function exec(uint256 amountIn, uint256 amountOutMin, address[] memory path, address to, uint256 deadline)
        external
    {
        require(
            path[0] == address(USDG) || path[0] == address(GLOW) || path[0] == address(USDC),
            "CounterfactualUniV2Swap/incorrect-path-0"
        );

        require(path[1] == address(USDG) || path[1] == address(GLOW), "CounterfactualUniV2Swap/incorrect-path-1");

        uint256 salt = nextSalt++;

        address predicted = predictAddress(amountIn, amountOutMin, path, to, deadline, salt);
        IERC20(path[0]).safeTransferFrom(msg.sender, predicted, amountIn);

        new CounterfactualUniV2Swap{salt: bytes32(salt)}(amountIn, amountOutMin, path, to, deadline);
    }
}

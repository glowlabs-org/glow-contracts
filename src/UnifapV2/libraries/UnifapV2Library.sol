// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

import "../interfaces/IUnifapV2Pair.sol";
import "../UnifapV2Pair.sol";

/// @title UnifapV2Library
/// @author Uniswap Labs
/// @notice Provides common functionality for UnifapV2 Contracts
library UnifapV2Library {
    function sortPairs(address token0, address token1) internal pure returns (address, address) {
        return token0 < token1 ? (token0, token1) : (token1, token0);
    }

    function quote(uint256 amount0, uint256 reserve0, uint256 reserve1) internal pure returns (uint256) {
        return (amount0 * reserve1) / reserve0;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * (997);
        uint256 numerator = amountInWithFee * (reserveOut);
        uint256 denominator = reserveIn * (1000) + (amountInWithFee);
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * (amountOut) * (1000);
        uint256 denominator = reserveOut - (amountOut) * (997);
        amountIn = (numerator / denominator) + (1);
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(address factory, uint256 amountIn, address[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "UniswapV2Library: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(address factory, uint256 amountOut, address[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "UniswapV2Library: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }

    function getReserves(address factory, address tokenA, address tokenB)
        internal
        view
        returns (uint112 reserveA, uint112 reserveB)
    {
        (address token0, address token1) = sortPairs(tokenA, tokenB);
        (uint112 reserve0, uint112 reserve1,) = IUnifapV2Pair(pairFor(factory, token0, token1)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        // Sort the tokens to ensure deterministic ordering
        (address token0, address token1) = sortPairs(tokenA, tokenB);

        // Compute the create2 salt exactly as the factory does
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));

        // Compute init code hash from the current UnifapV2Pair creation code so the
        // library can never get out of sync with the factory.
        bytes32 initCodeHash = keccak256(type(UnifapV2Pair).creationCode);

        // Derive the pair address using the standard create2 formula
        pair = address(uint160(uint256(keccak256(abi.encodePacked(hex"ff", factory, salt, initCodeHash)))));
    }
}

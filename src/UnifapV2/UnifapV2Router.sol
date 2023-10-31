// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

import "./interfaces/IUnifapV2Factory.sol";
import "./interfaces/IUnifapV2Pair.sol";
import "./interfaces/IERC20.sol";
import "./libraries/UnifapV2Library.sol";
import "forge-std/console.sol";
contract UnifapV2Router {
    // ========= Custom Errors =========

    error Expired();
    error SafeTransferFromFailed();
    error InsufficientAmountA();
    error InsufficientAmountB();

    // ========= State Variables =========

    IUnifapV2Factory public immutable factory;

    // ========= Constructor =========

    constructor(address _factory) {
        factory = IUnifapV2Factory(_factory);
    }

    // ========= Modifiers =========
    modifier check(uint256 deadline) {
        if (block.timestamp > deadline) revert Expired();
        _;
    }

    // ========= Public Functions =========

    /// @notice Add liquidity to token pool pair
    /// @dev Creates pair if not already created
    /// @param tokenA The first token
    /// @param tokenB The second token
    /// @param amountADesired The amount of tokenA desired
    /// @param amountBDesired The amount of tokenB desired
    /// @param amountAMin The minimum amount of tokenA to transfer
    /// @param amountBMin The minimum amount of tokenB to transfer
    /// @param to The address to transfer liquidity to
    /// @param deadline The deadline for the transaction
    /// @return amountA Amount of tokenA to transfer
    /// @return amountB Amount of tokenB to transfer
    /// @return liquidity Amount of liquidity transfered
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public check(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (amountA, amountB) =
            _computeLiquidityAmounts(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = factory.pairs(tokenA, tokenB);
        _safeTransferFrom(tokenA, msg.sender, pair, amountA);
        _safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IUnifapV2Pair(pair).mint(to);
    }

    /// @notice Remove liquidity from token pool pair
    /// @param tokenA The first token
    /// @param tokenB The second token
    /// @param liquidity The amount of liquidity token to remove
    /// @param amountAMin The minimum amount of tokenA needed
    /// @param amountBMin The minimum amount of tokenB needed
    /// @param to The address to transfer pair contracts to
    /// @param deadline The deadline for the transaction
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public check(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = factory.pairs(tokenA, tokenB);
        _safeTransferFrom(address(pair), msg.sender, address(pair), liquidity);
        (uint256 amount0, uint256 amount1) = IUnifapV2Pair(pair).burn(to);
        (address token0,) = UnifapV2Library.sortPairs(tokenA, tokenB);
        (amountA, amountB) = token0 == tokenA ? (amount0, amount1) : (amount1, amount0);
        if (amountA < amountAMin) revert InsufficientAmountA();
        if (amountB < amountBMin) revert InsufficientAmountB();
    }

    // ========= Internal Functions =========

    /// @notice computes token amounts according to marginal prices to be transfered
    /// @dev Creates a token pool pair if not already created
    function _computeLiquidityAmounts(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal returns (uint256 amountA, uint256 amountB) {
        if (factory.pairs(tokenA, tokenB) == address(0)) {
            factory.createPair(tokenA, tokenB);
        }

        (uint112 reserveA, uint112 reserveB) = UnifapV2Library.getReserves(address(factory), tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            amountB = UnifapV2Library.quote(amountADesired, reserveA, reserveB);
            if (amountB <= amountBDesired) {
                if (amountB < amountBMin) revert InsufficientAmountB();
                amountA = amountADesired;
            } else {
                amountA = UnifapV2Library.quote(amountBDesired, reserveB, reserveA);
                assert(amountA <= amountADesired);

                if (amountA < amountAMin) revert InsufficientAmountA();
                amountB = amountBDesired;
            }
        }
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount)
        internal
        returns (bool success)
    {
        success = IERC20(token).transferFrom(from, to, amount);
        if (!success) revert SafeTransferFromFailed();
    }

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "UnifapV2Router: EXPIRED");
        _;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        amounts = UnifapV2Library.getAmountsOut(address(factory), amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UnifapV2Library.pairFor(address(factory), path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint256[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to = i < path.length - 2 ? UnifapV2Library.pairFor(address(factory), output, path[i + 2]) : _to;
            address pair = UnifapV2Library.pairFor(address(factory), input, output);
            console.log("pair address = ", pair);
            IUnifapV2Pair(pair).swap(amount0Out, amount1Out, to,new bytes(0));
        }
    }

    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "UnifapV2Router: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }
}

// helper methods for interacting with ERC20 tokens and sending ETH that do not consistently return true/false
library TransferHelper {
    function safeApprove(address token, address to, uint256 value) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))), "TransferHelper::safeApprove: approve failed"
        );
    }

    function safeTransfer(address token, address to, uint256 value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))), "TransferHelper::safeTransfer: transfer failed"
        );
    }

    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TransferHelper::transferFrom: transferFrom failed"
        );
    }

    function safeTransferETH(address to, uint256 value) internal {
        (bool success,) = to.call{value: value}(new bytes(0));
        require(success, "TransferHelper::safeTransferETH: ETH transfer failed");
    }
}

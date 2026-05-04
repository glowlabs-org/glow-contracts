// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUniswapV2Pair} from "../../interfaces/IUniswapV2Pair.sol";
import {IUniswapRouterV2} from "../../interfaces/IUniswapRouterV2.sol";

/// @notice Atomic POL zap beam. The `TokenDelegateExecutor` that delegate-calls
/// this contract is pre-funded with USDG by `TokenDelegateFactory`. We then:
///   1. compute the optimal split via the closed-form Uniswap v2 zap formula,
///   2. swap USDG -> GLW on the GLW/USDG pair (sandwich-protected by `minGlwOut`),
///   3. snapshot post-swap reserves (the price the user's own swap created),
///   4. addLiquidity with the remaining USDG + bought GLW, sending LP to
///      `endowment`,
///   5. sweep any rounding dust to `endowment`,
///   6. emit `Zapped` so the backend can credit GCTL using the same
///      `getLpValuationAtBlock` math at the post-swap block state.
///
/// @dev MUST be invoked via `delegatecall` (e.g. by `TokenDelegateExecutor`).
/// All token-flow happens in the executor's context, so all USDG transfers
/// originate from an address whose `extcodesize` is still 0 (the executor is
/// mid-construction), satisfying USDG's contract allowlist gate. `endowment`
/// must therefore be an EOA or a USDG-allowlisted contract — otherwise the
/// dust sweep will revert.
contract LiquidityZapperBeam {
    using SafeERC20 for IERC20;

    IERC20 public constant USDG             = IERC20(0xe010ec500720bE9EF3F82129E7eD2Ee1FB7955F2);
    IERC20 public constant GLW              = IERC20(0xf4fbC617A5733EAAF9af08E1Ab816B103388d8B6);
    IUniswapV2Pair public constant PAIR     = IUniswapV2Pair(0x6FA09ffC45F1dDC95c1bc192956717042f142c5d);
    IUniswapRouterV2 public constant ROUTER = IUniswapRouterV2(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    /// @dev USDG is 6-decimals; magnify both sides of the optimal-swap
    /// calculation to claw back precision lost to integer division. Mirrors
    /// the `USDC_MAGNIFICATION` choice in `ImpactCatalyst`.
    uint256 private constant USDG_MAGNIFICATION = 1e24;

    error PrecisionLossLeadToUnderflow();
    error NoUSDG();
    error InsufficientLpOut(uint256 minted, uint256 minLpOut);

    event Zapped(
        address indexed endowment,
        uint256 usdgIn,
        uint256 usdgSwapped,
        uint256 glwReceived,
        uint256 usdgReserveAfterSwap,
        uint256 glwReserveAfterSwap,
        uint256 lpMinted
    );

    /// @param endowment Recipient of the LP tokens (and any rounding dust).
    /// @param minGlwOut Sandwich-protection floor for the USDG -> GLW swap.
    /// Quote this offchain (e.g. router.getAmountsOut at submission time) and
    /// pass a tolerance like 99%. With `minGlwOut == 0` a frontrunner can move
    /// the GLW price arbitrarily and the swap still executes, leaving the
    /// addLiquidity step to mint LP at the post-sandwich ratio.
    /// @param minLpOut Final outcome check on LP minted to `endowment`. Pass
    /// `0` to skip (no real-world case wants "≥ 0 LP"). Defense-in-depth
    /// alongside `minGlwOut` — catches formula edge cases or unexpected pair
    /// state that wouldn't have tripped the swap-level floor.
    function cast(address endowment, uint256 minGlwOut, uint256 minLpOut) external {
        uint256 usdgIn = USDG.balanceOf(address(this));
        if (usdgIn == 0) revert NoUSDG();

        bool usdgIs0 = address(USDG) < address(GLW);

        uint256 usdgSwapped;
        uint256 glwReceived;
        {
            uint256 swapAmount;
            {
                (uint256 r0, uint256 r1,) = PAIR.getReserves();
                uint256 reserveUsdg = usdgIs0 ? r0 : r1;
                swapAmount = findOptimalAmountToSwap(usdgIn * USDG_MAGNIFICATION, reserveUsdg * USDG_MAGNIFICATION)
                    / USDG_MAGNIFICATION;
            }

            IERC20(address(USDG)).approve(address(ROUTER), usdgIn);
            address[] memory path = new address[](2);
            path[0] = address(USDG);
            path[1] = address(GLW);
            uint256[] memory amounts = ROUTER.swapExactTokensForTokens({
                amountIn: swapAmount,
                amountOutMin: minGlwOut,
                path: path,
                to: address(this),
                deadline: block.timestamp
            });
            usdgSwapped = amounts[0];
            glwReceived = amounts[1];
        }

        // Snapshot reserves after the swap, before addLiquidity. The price
        // ratio is unchanged by addLiquidity, but capturing here gives the
        // backend a clean "post-swap reserves" reading regardless of
        // how addLiquidity rounds.
        uint256 usdgReserveAfter;
        uint256 glwReserveAfter;
        {
            (uint256 r0, uint256 r1,) = PAIR.getReserves();
            usdgReserveAfter = usdgIs0 ? r0 : r1;
            glwReserveAfter = usdgIs0 ? r1 : r0;
        }

        uint256 lpMinted = _addLiquidity(usdgIn - usdgSwapped, glwReceived, endowment);

        if (minLpOut != 0 && lpMinted < minLpOut) revert InsufficientLpOut(lpMinted, minLpOut);

        {
            uint256 usdgDust = USDG.balanceOf(address(this));
            if (usdgDust > 0) IERC20(address(USDG)).safeTransfer(endowment, usdgDust);
            uint256 glwDust = GLW.balanceOf(address(this));
            if (glwDust > 0) IERC20(address(GLW)).safeTransfer(endowment, glwDust);
        }

        emit Zapped(endowment, usdgIn, usdgSwapped, glwReceived, usdgReserveAfter, glwReserveAfter, lpMinted);
    }

    /// @dev Extracted to its own frame to keep `cast`'s stack within limits.
    /// 1% `amount*Min` slack absorbs integer-rounding noise in
    /// `findOptimalAmountToSwap`.
    function _addLiquidity(uint256 usdgRemaining, uint256 glwReceived, address endowment)
        internal
        returns (uint256 lpMinted)
    {
        IERC20(address(GLW)).approve(address(ROUTER), glwReceived);
        (,, lpMinted) = ROUTER.addLiquidity(
            address(USDG),
            address(GLW),
            usdgRemaining,
            glwReceived,
            usdgRemaining * 99 / 100,
            glwReceived * 99 / 100,
            endowment,
            block.timestamp
        );
    }

    /// @notice Closed-form Uniswap v2 (0.3% fee) optimal one-sided zap split.
    /// Returns the amount of `amountIn` that should be swapped so the leftover
    /// matches the post-swap pool ratio with no dust.
    /// Magnify both `amountIn` and `reserveIn` by the same factor for
    /// precision; divide the result by that same factor.
    function findOptimalAmountToSwap(uint256 amountIn, uint256 reserveIn) public pure returns (uint256) {
        uint256 a = sqrt(reserveIn) + 1;
        uint256 b = sqrt(3988000 * amountIn + 3988009 * reserveIn);
        uint256 c = 1997 * reserveIn;
        uint256 d = 1994;
        if (c > a * b) revert PrecisionLossLeadToUnderflow();
        return ((a * b) - c) / d;
    }

    /// @dev Forked from solady; identical implementation to `ImpactCatalyst.sqrt`.
    function sqrt(uint256 x) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            let y := x
            z := 181

            if iszero(lt(y, 0x10000000000000000000000000000000000)) {
                y := shr(128, y)
                z := shl(64, z)
            }
            if iszero(lt(y, 0x1000000000000000000)) {
                y := shr(64, y)
                z := shl(32, z)
            }
            if iszero(lt(y, 0x10000000000)) {
                y := shr(32, y)
                z := shl(16, z)
            }
            if iszero(lt(y, 0x1000000)) {
                y := shr(16, y)
                z := shl(8, z)
            }

            z := shr(18, mul(z, add(y, 65536)))

            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))

            z := sub(z, lt(div(x, z), z))
        }
    }
}

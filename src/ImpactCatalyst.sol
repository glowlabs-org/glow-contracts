// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Pair} from "@/interfaces/IUniswapV2Pair.sol";
import "forge-std/console.sol";

contract ImpactCatalyst {
    error CallerNotGCC();
    error PrecisionLossLeadToUnderflow();

    address public immutable GCC;
    address public immutable USDC;
    IUniswapRouterV2 public immutable UNISWAP_ROUTER;
    address public immutable UNISWAP_V2_FACTORY;
    address public immutable UNISWAP_V2_PAIR;
    uint256 private constant GCC_MAGNIFICATION = 1e18;
    uint256 private constant USDC_MAGNIFICATION = 1e24;

    constructor(address _usdc, address router, address factory, address pair) payable {
        GCC = msg.sender;
        USDC = _usdc;
        UNISWAP_V2_FACTORY = factory;
        UNISWAP_ROUTER = IUniswapRouterV2(router);
        UNISWAP_V2_PAIR = pair;
    }

    /**
     * @notice entry point for GCC to commit GCC
     * @dev the retiring process is as follows:
     *         1. GCC is swapped for USDC
     *         2. GCC and USDC are added to the GCC-USDC pool
     *         3. The caller receives 2x the amount of USDC received from the swap in nominations
     *     - The point is to commit the GCC while adding liquidity to increase incentives for farms
     * @param amount the amount of GCC to commit
     * @return usdcEffect - the amount of USDC used in the LP Position
     * @return nominations - the amount of nominations to earn sqrt(amountGCCUsedInLiquidityPosition * amountUSDCUsedInLiquidityPosition)
     *                        - we do this to battle the quadratic nature of K in the UniswapV2Pair contract and standardize nominations
     */
    function commitGCC(uint256 amount) external returns (uint256 usdcEffect, uint256 nominations) {
        if (msg.sender != GCC) {
            _revert(CallerNotGCC.selector);
        }
        (uint256 reserveA, uint256 reserveB,) = IUniswapV2Pair(UNISWAP_V2_PAIR).getReserves();
        uint256 reserveGCC = GCC < USDC ? reserveA : reserveB;

        uint256 amountToSwap =
            findOptimalAmountToCommit(amount * GCC_MAGNIFICATION, reserveGCC * GCC_MAGNIFICATION) / GCC_MAGNIFICATION;
        uint256 amountToAddInLiquidity = amount - amountToSwap;

        IERC20(GCC).approve(address(UNISWAP_ROUTER), amount);
        address[] memory path = new address[](2);
        path[0] = GCC;
        path[1] = USDC;
        uint256[] memory amounts =
            UNISWAP_ROUTER.swapExactTokensForTokens(amountToSwap, 0, path, address(this), block.timestamp);
        uint256 amountUSDCReceived = amounts[1];
        IERC20(USDC).approve(address(UNISWAP_ROUTER), amountUSDCReceived);
        UNISWAP_ROUTER.addLiquidity(
            GCC, USDC, amountToAddInLiquidity, amountUSDCReceived, 0, 0, address(this), block.timestamp
        );
        usdcEffect = amountUSDCReceived;
        console.log("amount gcc adding into liquidity = %s", amountToAddInLiquidity);
        console.log("amount usdc adding into liquidity = %s", amountUSDCReceived);
        nominations = sqrt(amountToAddInLiquidity * amountUSDCReceived);
    }

    /**
     * @notice entry point for GCC to commit USDC
     * @dev the retiring process is as follows:
     *         1. USDC is swapped for GCC
     *         2. GCC and USDC are added to the GCC-USDC pool
     *         3. The caller `amount` of USDC used / committed
     * @param amount the amount of USDC to commit
     * @dev no need to return anything as the caller is the GCC contract and knows how much USDC was used
     * @return nominations - the amount of nominations to earn sqrt(amountGCCUsedInLiquidityPosition * amountUSDCUsedInLiquidityPosition)
     *                        - we do this to battle the quadratic nature of K in the UniswapV2Pair contract and standardize nominations
     */
    function commitUSDC(uint256 amount) external returns (uint256 nominations) {
        if (msg.sender != GCC) {
            _revert(CallerNotGCC.selector);
        }
        (uint256 reserveA, uint256 reserveB,) = IUniswapV2Pair(UNISWAP_V2_PAIR).getReserves();
        uint256 reserveUSDC = USDC < GCC ? reserveA : reserveB;
        uint256 amountToSwap = findOptimalAmountToCommit(amount * USDC_MAGNIFICATION, reserveUSDC * USDC_MAGNIFICATION)
            / USDC_MAGNIFICATION;
        uint256 amountToAddInLiquidity = amount - amountToSwap;
        IERC20(USDC).approve(address(UNISWAP_ROUTER), amount);
        address[] memory path = new address[](2);
        path[0] = USDC;
        path[1] = GCC;
        uint256[] memory amounts =
            UNISWAP_ROUTER.swapExactTokensForTokens(amountToSwap, 0, path, address(this), block.timestamp);
        IERC20(GCC).approve(address(UNISWAP_ROUTER), amounts[1]);
        UNISWAP_ROUTER.addLiquidity(USDC, GCC, amountToAddInLiquidity, amounts[1], 0, 0, address(this), block.timestamp);
        nominations = sqrt(amountToAddInLiquidity * amounts[1]);
    }

    /**
     * @notice helper function to find the optimal amount of tokens to swap
     * @param amountTocommit the amount of tokens to commit
     * @param totalReservesOfToken the total reserves of the token to commit
     * @return optimalAmount - the optimal amount of tokens to swap
     */
    function findOptimalAmountToCommit(uint256 amountTocommit, uint256 totalReservesOfToken)
        public
        view
        returns (uint256)
    {
        uint256 a = sqrt(totalReservesOfToken) + 1; //adjust for div round down errors
        uint256 b = sqrt(3988000 * amountTocommit + 3988009 * totalReservesOfToken);
        uint256 c = 1997 * totalReservesOfToken;
        uint256 d = 1994;
        if (c > a * b) _revert(PrecisionLossLeadToUnderflow.selector); // prevent underflow
        uint256 res = ((a * b) - c) / d;
        return res;
    }

    /// @dev forked from solady library
    /// @param x - the number to calculate the square root of
    /// @return z - the square root of x
    function sqrt(uint256 x) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let y := x // We start y at x, which will help us make our initial estimate.

            z := 181 // The "correct" value is 1, but this saves a multiplication later.

            // This segment is to get a reasonable initial estimate for the Babylonian method. With a bad
            // start, the correct # of bits increases ~linearly each iteration instead of ~quadratically.

            // We check y >= 2^(k + 8) but shift right by k bits
            // each branch to ensure that if x >= 256, then y >= 256.
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

            // Goal was to get z*z*y within a small factor of x. More iterations could
            // get y in a tighter range. Currently, we will have y in [256, 256*2^16).
            // We ensured y >= 256 so that the relative difference between y and y+1 is small.
            // That's not possible if x < 256 but we can just verify those cases exhaustively.

            // Now, z*z*y <= x < z*z*(y+1), and y <= 2^(16+8), and either y >= 256, or x < 256.
            // Correctness can be checked exhaustively for x < 256, so we assume y >= 256.
            // Then z*sqrt(y) is within sqrt(257)/sqrt(256) of sqrt(x), or about 20bps.

            // For s in the range [1/256, 256], the estimate f(s) = (181/1024) * (s+1) is in the range
            // (1/2.84 * sqrt(s), 2.84 * sqrt(s)), with largest error when s = 1 and when s = 256 or 1/256.

            // Since y is in [256, 256*2^16), let a = y/65536, so that a is in [1/256, 256). Then we can estimate
            // sqrt(y) using sqrt(65536) * 181/1024 * (a + 1) = 181/4 * (y + 65536)/65536 = 181 * (y + 65536)/2^18.

            // There is no overflow risk here since y < 2^136 after the first branch above.
            z := shr(18, mul(z, add(y, 65536))) // A mul() is saved from starting z at 181.

            // Given the worst case multiplicative error of 2.84 above, 7 iterations should be enough.
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))

            // If x+1 is a perfect square, the Babylonian method cycles between
            // floor(sqrt(x)) and ceil(sqrt(x)). This statement ensures we return floor.
            // See: https://en.wikipedia.org/wiki/Integer_square_root#Using_only_integer_division
            // Since the ceil is rare, we save gas on the assignment and repeat division in the rare case.
            // If you don't care whether the floor or ceil square root is returned, you can remove this statement.
            z := sub(z, lt(div(x, z), z))
        }
    }

    /**
     * @notice More efficiently reverts with a bytes4 selector
     * @param selector The selector to revert with
     */

    function _revert(bytes4 selector) private pure {
        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            mstore(0x0, selector)
            revert(0x0, 0x04)
        }
    }
}

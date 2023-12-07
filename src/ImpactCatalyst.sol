// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Pair} from "@/interfaces/IUniswapV2Pair.sol";
import {UniswapV2Library} from "@/libraries/UniswapV2Library.sol";
/**
 * @title ImpactCatalyst
 * @notice A contract for managing the GCC and USDC commitment
 *         A committment is when a user `donates` their GCC or USDC to the GCC-USDC pool
 *         to increase the liquidity of the pool and earn nominations
 *         For each commit, `amount` of GCC or USDC is swapped for the other token
 *         for the optimal amount such that the return amount of the other token
 *         is exactly enough to add liquidity to the GCC-USDC pool without any left over of either token
 *         (precision errors may have small dust)
 *         - Nominations are granted as (sqrt(amountGCCUsedInLiquidityPosition * amountUSDCUsedInLiquidityPosition))
 *                 - or as the amount of liquidity tokens created from adding liquidity to the GCC-USDC pool
 *         - This is done to battle the quadratic nature of K in the UniswapV2Pair contract and standardize nominations
 * @dev only the GCC contract can call this contract since GCC is the only contract that is allowed to grant nominations
 * - having the catalyst calls be open would lead to commitment that would not earn any impact points / rewards / nominations
 */

contract ImpactCatalyst {
    /* -------------------------------------------------------------------------- */
    /*                                   errors                                   */
    /* -------------------------------------------------------------------------- */
    error CallerNotGCC();
    error PrecisionLossLeadToUnderflow();
    error NotEnoughImpactPowerFromCommitment();

    /* -------------------------------------------------------------------------- */
    /*                                  constants                                 */
    /* -------------------------------------------------------------------------- */
    /// @dev the magnification of GCC to use in {findOptimalAmountToSwap} to reduce precision loss
    /// @dev GCC is in 18 decimals, so we can make it 1e18 to reduce precision loss
    uint256 private constant GCC_MAGNIFICATION = 1e18;

    /// @dev the magnification of USDC to use in {findOptimalAmountToSwap} to reduce precision loss
    /// @dev USDC is in 6 decimals, so we can make it 1e24 to reduce precision loss
    uint256 private constant USDC_MAGNIFICATION = 1e24;

    // /// @dev the minimum liquidity in univ2
    // uint private constant UNISWAP_V2_MINIMUM_LIQUIDITY = 10**3;

    /* -------------------------------------------------------------------------- */
    /*                                 immutables                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice the GCC token
    address public immutable GCC;

    /// @notice the USDC token
    address public immutable USDC;

    /// @notice the uniswap router
    IUniswapRouterV2 public immutable UNISWAP_ROUTER;

    /// @notice the uniswap factory
    address public immutable UNISWAP_V2_FACTORY;

    /// @notice the uniswap pair of GCC and USDC
    address public immutable UNISWAP_V2_PAIR;

    /* -------------------------------------------------------------------------- */
    /*                                 constructor                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @param _usdc - the address of the USDC token
     * @param router - the address of the uniswap router
     * @param factory - the address of the uniswap factory
     * @param pair - the address of the uniswap pair of GCC and USDC
     */
    constructor(address _usdc, address router, address factory, address pair) payable {
        GCC = msg.sender;
        USDC = _usdc;
        UNISWAP_ROUTER = IUniswapRouterV2(router);
        UNISWAP_V2_FACTORY = factory;
        UNISWAP_V2_PAIR = pair;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 gcc commits                                */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice entry point for GCC to commit GCC
     * @dev the commit process is as follows:
     *         1. GCC is swapped for USDC
     *         2. GCC and USDC are added to the GCC-USDC pool
     *         3. The caller receives 2x the amount of USDC received from the swap in nominations
     *     - The point is to commit the GCC while adding liquidity to increase incentives for farms
     * @param amount the amount of GCC to commit
     * @param minImpactPower the minimum amount of impact power expected to be earned from the commitment
     * @return usdcEffect - the amount of USDC used in the LP Position
     * @return nominations - the amount of nominations to earn sqrt(amountGCCUsedInLiquidityPosition * amountUSDCUsedInLiquidityPosition)
     *                        - we do this to battle the quadratic nature of K in the UniswapV2Pair contract and standardize nominations
     */
    function commitGCC(uint256 amount, uint256 minImpactPower)
        external
        returns (uint256 usdcEffect, uint256 nominations)
    {
        //Commitments can only be made through the GCC contract
        if (msg.sender != GCC) {
            _revert(CallerNotGCC.selector);
        }
        //Find the reserves of GCC and USDC in the GCC-USDC pool
        (uint256 reserveA, uint256 reserveB,) = IUniswapV2Pair(UNISWAP_V2_PAIR).getReserves();
        //Find the reserve of GCC and USDC in the GCC-USDC pool
        uint256 reserveGCC = GCC < USDC ? reserveA : reserveB;

        //Find the optimal amount of GCC to swap for USDC
        //This ensures that the the return amount of USDC after the swap
        //Should be exactly enough to add liquidity to the GCC-USDC pool with the remainder of `amount` of GCC left over
        uint256 amountToSwap =
            findOptimalAmountToSwap(amount * GCC_MAGNIFICATION, reserveGCC * GCC_MAGNIFICATION) / GCC_MAGNIFICATION;

        //Approve the GCC token to be spent by the router
        IERC20(GCC).approve(address(UNISWAP_ROUTER), amount);
        //Create the path for the swap
        address[] memory path = new address[](2);
        path[0] = GCC;
        path[1] = USDC;
        //Swap the GCC for USDC

        //If impact power = sqrt(amountGCCUsedInLiquidityPosition * amountUSDCUsedInLiquidityPosition)
        // square both sides, and we get impact power ^ 2 = amountGCCUsedInLiquidityPosition * amountUSDCUsedInLiquidityPosition
        // so we can find the minimum amount of USDC expected from the swap by doing
        // minimumUSDCExpected = (minImpactPower * minImpactPower) / (amount - amountToSwap)
        //since amount - amountToSwap is the expected amount of GCC used in the liquidity position
        uint256 minimumUSDCExpected = (minImpactPower * minImpactPower) / (amount - amountToSwap);
        uint256[] memory amounts = UNISWAP_ROUTER.swapExactTokensForTokens({
            amountIn: amountToSwap,
            // we allow for a 1% slippage due to potential rounding errors
            amountOutMin: minimumUSDCExpected * 99 / 100,
            path: path,
            to: address(this),
            deadline: block.timestamp
        });

        //Find how much USDC was received from the swap
        uint256 amountUSDCReceived = amounts[1];
        //Approve the USDC token to be spent by the router
        IERC20(USDC).approve(address(UNISWAP_ROUTER), amountUSDCReceived);
        uint256 amountToAddInLiquidity = amount - amounts[0];
        uint256 pairUSDCBalanceBefore = IERC20(USDC).balanceOf(UNISWAP_V2_PAIR);
        (,, uint256 actualImpactPowerEarned) = UNISWAP_ROUTER.addLiquidity({
            tokenA: GCC,
            tokenB: USDC,
            amountADesired: amountToAddInLiquidity,
            amountBDesired: amountUSDCReceived,
            // we allow for a 1% slippage due to potential rounding errors
            //This seems high, but it's simply a precaution to prevent the transaction from reverting
            // The bulk of the calculation happens in the logic above
            amountAMin: amountToAddInLiquidity * 99 / 100,
            amountBMin: amountUSDCReceived * 99 / 100,
            to: address(this),
            deadline: block.timestamp
        });
        uint256 pairUSDCBalanceAfter = IERC20(USDC).balanceOf(UNISWAP_V2_PAIR);
        usdcEffect = pairUSDCBalanceAfter - pairUSDCBalanceBefore;
        if (actualImpactPowerEarned < minImpactPower) {
            _revert(NotEnoughImpactPowerFromCommitment.selector);
        }

        //Set usdcEffect to the amount of USDC used in the liquidity position
        //set the nominations to sqrt(amountGCCUsedInLiquidityPosition * amountUSDCUsedInLiquidityPosition)
        nominations = actualImpactPowerEarned;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 usdc commits                               */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice entry point for GCC to commit USDC
     * @dev the commit process is as follows:
     *         1. USDC is swapped for GCC
     *         2. GCC and USDC are added to the GCC-USDC pool
     *         3. The caller `amount` of USDC used / committed
     * @param amount the amount of USDC to commit
     * @param minImpactPower the minimum amount of impact power expected to be earned from the commitment
     * @return nominations - the amount of nominations to earn sqrt(amountGCCUsedInLiquidityPosition * amountUSDCUsedInLiquidityPosition)
     *                        - we do this to battle the quadratic nature of K in the UniswapV2Pair contract and standardize nominations
     */
    function commitUSDC(uint256 amount, uint256 minImpactPower) external returns (uint256 nominations) {
        //Commitments can only be made through the GCC contract
        if (msg.sender != GCC) {
            _revert(CallerNotGCC.selector);
        }
        //Find the reserves of GCC and USDC in the GCC-USDC pool
        (uint256 reserveA, uint256 reserveB,) = IUniswapV2Pair(UNISWAP_V2_PAIR).getReserves();
        //Find the reserve of GCC and USDC in the GCC-USDC pool
        uint256 reserveUSDC = USDC < GCC ? reserveA : reserveB;
        //Find the optimal amount of USDC to swap for GCC
        //This ensures that the the return amount of GCC after the swap
        //Should be exactly enough to add liquidity to the GCC-USDC pool with the remainder of `amount`  USDC left over
        uint256 optimalSwapAmount =
            findOptimalAmountToSwap(amount * USDC_MAGNIFICATION, reserveUSDC * USDC_MAGNIFICATION) / USDC_MAGNIFICATION;

        //Approve the USDC token to be spent by the router
        IERC20(USDC).approve(address(UNISWAP_ROUTER), amount);
        //Create the path for the swap
        address[] memory path = new address[](2);
        path[0] = USDC;
        path[1] = GCC;

        //If impact power = sqrt(amountGCCUsedInLiquidityPosition * amountUSDCUsedInLiquidityPosition)
        // square both sides, and we get impact power ^ 2 = amountGCCUsedInLiquidityPosition * amountUSDCUsedInLiquidityPosition
        // so we can find the minimum amount of GCC expected from the swap by doing
        // minimumGCCExpected = (minImpactPower * minImpactPower) / (amount - optimalSwapAmount)
        //since amount - optimalSwapAmount is the expected amount of USDC used in the liquidity position
        uint256 minimumGCCExpected = (minImpactPower * minImpactPower) / (amount - optimalSwapAmount);

        //Swap the USDC for GCC
        uint256[] memory amounts = UNISWAP_ROUTER.swapExactTokensForTokens({
            amountIn: optimalSwapAmount,
            // we allow for a 1% slippage due to potential rounding errors
            amountOutMin: minimumGCCExpected * 99 / 100,
            path: path,
            to: address(this),
            deadline: block.timestamp
        });
        //Approve the GCC token to be spent by the router
        IERC20(GCC).approve(address(UNISWAP_ROUTER), amounts[1]);

        uint256 amountToAddInLiquidity = amount - amounts[0];

        //Add liquidity to the GCC-USDC pool
        (,, uint256 actualImpactPowerEarned) = UNISWAP_ROUTER.addLiquidity({
            tokenA: USDC,
            tokenB: GCC,
            amountADesired: amountToAddInLiquidity,
            amountBDesired: amounts[1],
            // we allow for a 1% slippage due to potential rounding errors
            //This seems high, but it's simply a precaution to prevent the transaction from reverting
            // The bulk of the calculation happens in the logic above
            amountAMin: amountToAddInLiquidity * 99 / 100,
            amountBMin: amounts[1] * 99 / 100,
            to: address(this),
            deadline: block.timestamp
        });

        if (actualImpactPowerEarned < minImpactPower) {
            _revert(NotEnoughImpactPowerFromCommitment.selector);
        }

        nominations = actualImpactPowerEarned;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 view functions                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice a helper function to estimate the impact power expected from a GCC commit
     * @dev there may be a slight difference between the actual impact power earned and the estimated impact power
     *     - A max .5% divergence should be accounted for when using this function
     * @param amount the amount of GCC to commit
     * @return expectedImpactPower - the amount of impact power expected to be earned from the commitment
     */
    function estimateUSDCCommitImpactPower(uint256 amount) external view returns (uint256 expectedImpactPower) {
        uint256 expectedImpactPower = _estimateUSDCCommitImpactPower(amount);
        return expectedImpactPower;
    }

    /**
     * @notice a helper function to estimate the impact power expected from a USDC commit
     * @dev there may be a slight difference between the actual impact power earned and the estimated impact power
     *     - A max .5% divergence should be accounted for when using this function
     * @param amount the amount of USDC to commit
     * @return expectedImpactPower - the amount of impact power expected to be earned from the commitment
     */
    function estimateGCCCommitImpactPower(uint256 amount) external view returns (uint256 expectedImpactPower) {
        uint256 expectedImpactPower = _estimateGCCCommitImpactPower(amount);
        return expectedImpactPower;
    }

    /**
     * @notice helper function to find the optimal amount of tokens to swap
     * @param amountTocommit the amount of tokens to commit
     * @param totalReservesOfToken the total reserves of the token to commit
     * @return optimalAmount - the optimal amount of tokens to swap
     */
    function findOptimalAmountToSwap(uint256 amountTocommit, uint256 totalReservesOfToken)
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

    /* -------------------------------------------------------------------------- */
    /*                               internal view funcs                          */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice returns {optimalSwapAmount, amountToAddInLiquidity, impactPowerExpected} for an USDC commit
     * @param amount the amount of USDC to commit
     * @dev there may be a slight difference between the actual impact power earned and the estimated impact power
     *     - A max .5% divergence should be accounted for when using this function
     * @return impactPowerExpected - the amount of impact power expected to be earned from the commitment
     */
    function _estimateUSDCCommitImpactPower(uint256 amount) internal view returns (uint256 impactPowerExpected) {
        //Get the reserves of GCC and USDC in the GCC-USDC pool
        (uint256 reserveA, uint256 reserveB,) = IUniswapV2Pair(UNISWAP_V2_PAIR).getReserves();
        //Get GCC Reserve
        uint256 reserveGCC = GCC < USDC ? reserveA : reserveB;
        //Get USDC Reserve
        uint256 reserveUSDC = USDC < GCC ? reserveA : reserveB;

        //Calculate the optimal amount of USDC to swap for GCC
        uint256 optimalSwapAmount =
            findOptimalAmountToSwap(amount * USDC_MAGNIFICATION, reserveUSDC * USDC_MAGNIFICATION) / USDC_MAGNIFICATION;

        //Since we commit USDC, we want to simulate how much GCC we would get from the swap
        //This is also the same amount of GCC that will be used to add liquidity to the GCC-USDC pool
        uint256 gccEstimate = UniswapV2Library.getAmountOut(optimalSwapAmount, reserveUSDC, reserveGCC);

        //This is the amount of USDC to add in the LP, which is the amount-optimalSwapAmount
        //This number represents the balance of USDC after the swap
        uint256 amountToAddInLiquidity = amount - optimalSwapAmount;

        //The new reserves of GCC and USDC after the swap
        //We add the optimalSwapAmount to USDC, since we used it to swap for GCC
        //and, we subtract the gccEstimate from GCC, since it was used when we swapped our USDC
        uint256 reserveUSDC_afterSwap = reserveUSDC + optimalSwapAmount;
        uint256 reserveGCC_afterSwap = reserveGCC - gccEstimate;

        //Get the total supply of LP tokens
        uint256 totalSupply = IUniswapV2Pair(UNISWAP_V2_PAIR).totalSupply();

        //Calculate the amount of LP tokens that would be generated from adding liquidity
        //This mirrors how uniswapV2 calculates the amount of LP tokens to mint
        //Check out UniswapV2Pair contract for more info
        //Link at time of deployment: https://github.com/Uniswap/v2-core/blob/ee547b17853e71ed4e0101ccfd52e70d5acded58/contracts/UniswapV2Pair.sol
        //  -   lines 110-131 in the `mint` function in link above
        uint256 liquidity = min(
            (amountToAddInLiquidity * totalSupply) / reserveUSDC_afterSwap,
            (gccEstimate * totalSupply) / reserveGCC_afterSwap
        );

        //Set impactPowerExpected to the amount of LP tokens generated
        impactPowerExpected = liquidity;
        return impactPowerExpected;
    }

    /**
     * @notice returns {optimalSwapAmount, amountToAddInLiquidity, impactPowerExpected} for a GCC commit
     * @param amount the amount of GCC to commit
     * @dev there may be a slight difference between the actual impact power earned and the estimated impact power
     *     - A max .5% divergence should be accounted for when using this function
     * @return impactPowerExpected - the amount of impact power expected to be earned from the commitment
     */
    function _estimateGCCCommitImpactPower(uint256 amount) internal view returns (uint256 impactPowerExpected) {
        //Get the reserves of GCC and USDC in the GCC-USDC pool
        (uint256 reserveA, uint256 reserveB,) = IUniswapV2Pair(UNISWAP_V2_PAIR).getReserves();

        //Get GCC Reserve
        uint256 reserveGCC = GCC < USDC ? reserveA : reserveB;
        //Get USDC Reserve
        uint256 reserveUSDC = USDC < GCC ? reserveA : reserveB;

        //Calculate the optimal amount of GCC to swap for USDC
        uint256 optimalSwapAmount =
            findOptimalAmountToSwap(amount * GCC_MAGNIFICATION, reserveGCC * GCC_MAGNIFICATION) / GCC_MAGNIFICATION;

        //Since we commit GCC, we want to simulate how much USDC we would get from the swap
        uint256 usdcEstimate = UniswapV2Library.getAmountOut(optimalSwapAmount, reserveGCC, reserveUSDC);

        //This is the amount of GCC to add in the LP, which is the amount-optimalSwapAmount
        uint256 amountGCCToAddInLiquidity = amount - optimalSwapAmount;

        //The new reserves of GCC and USDC after the swap
        //We add the optimalSwapAmount to GCC reserves, since we used it to swap for USDC
        //and, we subtract the usdcEstimate from USDC reserves, since it was used when we swapped our GCC
        uint256 reserveGCC_afterSwap = reserveGCC + optimalSwapAmount;
        uint256 reserveUSDC_afterSwap = reserveUSDC - usdcEstimate;

        //Get the total supply of LP tokens
        uint256 totalSupply = IUniswapV2Pair(UNISWAP_V2_PAIR).totalSupply();

        //Calculate the amount of LP tokens that would be generated from adding liquidity
        //This mirrors how uniswapV2 calculates the amount of LP tokens to mint
        //Check out UniswapV2Pair contract for more info
        //Link at time of deployment: https://github.com/Uniswap/v2-core/blob/ee547b17853e71ed4e0101ccfd52e70d5acded58/contracts/UniswapV2Pair.sol
        //  -   lines 110-131 in the `mint` function in link above
        uint256 liquidity = min(
            (amountGCCToAddInLiquidity * totalSupply) / reserveGCC_afterSwap,
            (usdcEstimate * totalSupply) / reserveUSDC_afterSwap
        );

        //Set impactPowerExpected to the amount of LP tokens generated
        impactPowerExpected = liquidity;
        return impactPowerExpected;
    }

    /* -------------------------------------------------------------------------- */
    /*                                    utils                                   */
    /* -------------------------------------------------------------------------- */
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
     * @notice returns the minimum of two numbers
     * @param a - the first number
     * @param b - the second number
     * @return the minimum of a and b
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
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

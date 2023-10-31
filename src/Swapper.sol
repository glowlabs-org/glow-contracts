// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";
import {UniswapV2Library} from "@/libraries/UniswapV2Library.sol";
import {IUniswapV2Pair} from "@/interfaces/IUniswapV2Pair.sol";

contract Swapper {
    address public immutable GCC;
    address public immutable USDC;
    IUniswapRouterV2 public immutable UNISWAP_ROUTER;
    address public immutable UNISWAP_V2_FACTORY;
    address public immutable UNISWAP_V2_PAIR;

    constructor(address _usdc, address router, address factory, address pair) payable {
        GCC = msg.sender;
        USDC = _usdc;
        UNISWAP_V2_FACTORY = factory;
        UNISWAP_ROUTER = IUniswapRouterV2(router);
        UNISWAP_V2_PAIR = pair;
    }

    function retireGCC(uint256 amount) external returns (uint256 usdcReceivedTimesTwo) {
        if (msg.sender != GCC) {
            revert("Only GCC can retire GCC");
        }
        (uint256 reserveA, uint256 reserveB,) = IUniswapV2Pair(UNISWAP_V2_PAIR).getReserves();
        uint256 reserveGCC = GCC < USDC ? reserveA : reserveB;

        //x = (sqrt(b) sqrt(3988000 a + 3988009 b) - 1997 b)/1994
        uint256 amountToSwap = findOptimalAmountToRetire(amount, reserveGCC);
        uint256 amountToAddInLiquidity = amount - amountToSwap;
        IERC20(GCC).approve(address(UNISWAP_ROUTER), amount);
        address[] memory path = new address[](2);
        path[0] = GCC;
        path[1] = USDC;
        uint256[] memory amounts =
            UNISWAP_ROUTER.swapExactTokensForTokens(amountToSwap, 0, path, address(this), block.timestamp);
        uint256 amountUSDCReceived = amounts[1];
        IERC20(USDC).approve(address(UNISWAP_ROUTER), amountUSDCReceived);

        console.log("amounts[0]", amounts[0]);
        console.log("amounts[1]", amounts[1]);
        UNISWAP_ROUTER.addLiquidity(
            GCC, USDC, amountToAddInLiquidity, amountUSDCReceived, 0, 0, address(this), block.timestamp
        );
        // console.log("[Swapper GCC] USDC Balance After Add Event", IERC20(USDC).balanceOf(address(this)));
        // console.log("[Swapper GCC] GCC Balance After Add Event", IERC20(GCC).balanceOf(address(this)));
        usdcReceivedTimesTwo = amountUSDCReceived * 2;
    }

    function retireUSDC(uint256 amount) external {
        if (msg.sender != GCC) {
            revert("Only GCC can retire GCC");
        }
        (uint256 reserveA, uint256 reserveB,) = IUniswapV2Pair(UNISWAP_V2_PAIR).getReserves();
        uint256 reserveUSDC = USDC < GCC ? reserveA : reserveB;
        //Magnify by 1e12 to increase precision on sqrt
        uint256 amountToSwap = findOptimalAmountToRetire(amount * 1e12, reserveUSDC * 1e12);
        amountToSwap /= 1e12;
        uint256 amountToAddInLiquidity = amount - amountToSwap;
        IERC20(USDC).approve(address(UNISWAP_ROUTER), amount);
        address[] memory path = new address[](2);
        path[0] = USDC;
        path[1] = GCC;
        uint256[] memory amounts =
            UNISWAP_ROUTER.swapExactTokensForTokens(amountToSwap, 0, path, address(this), block.timestamp);
        IERC20(GCC).approve(address(UNISWAP_ROUTER), amounts[1]);
        UNISWAP_ROUTER.addLiquidity(USDC, GCC, amountToAddInLiquidity, amounts[1], 0, 0, address(this), block.timestamp);
    }

    function findOptimalAmountToRetire(uint256 amountToRetire, uint256 totalReservesOfToken)
        public
        pure
        returns (uint256)
    {
        return (
            sqrt(totalReservesOfToken) * sqrt(3988000 * amountToRetire + 3988009 * totalReservesOfToken)
                - 1997 * totalReservesOfToken
        ) / 1994;
    }

    // function doSomeStuff()

    // function retireUSDC(uint amount) external {
    //     if(msg.sender != GCC) {
    //         revert("Only GCC can retire USDC");
    //     }
    //     IERC20(USDC).transfer(GCC, amount);
    // }

    /// @dev forked from solady library
    /// @param x - the number to calculate the square root of
    /// @return z - the square root of x
    function sqrt(uint256 x) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
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
}

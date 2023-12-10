import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@/testing/TestGCC.sol";
import "forge-std/StdUtils.sol";
import {UniswapV2Library} from "@/libraries/UniswapV2Library.sol";

contract MinImpactPowerEstimationTest is Test {
    uint256 MINIMUM_LIQUIDITY = 1e3;
    string file = "logs/MinImpactPowerEstimationTest.csv";

    function setUp() public {
        // string memory headers = "shortFormLiquidity,uniswapLiquidity,diff";
        // if (vm.exists(file)) {
        //     vm.removeFile(file);
        // }
        // vm.writeLine(file, headers);
    }

    // /**
    //     * forge-config: default.fuzz.runs = 1
    //     * forge-config: default.fuzz.depth = 100
    //  */
    function testFuzz_sanityCheck_simplifiedEstimationDoesNotDiverge(
        uint256 lpTokensTotalSupply,
        uint256 reservesA,
        uint256 reservesB,
        uint256 amountAToAdd,
        uint256 amountBToAdd
    ) public {
        reservesA = bound(reservesA, MINIMUM_LIQUIDITY, type(uint104).max);
        reservesB = bound(reservesB, MINIMUM_LIQUIDITY, type(uint104).max);
        amountAToAdd = bound(amountAToAdd, MINIMUM_LIQUIDITY, type(uint104).max);
        amountBToAdd = bound(amountBToAdd, MINIMUM_LIQUIDITY, type(uint104).max);
        lpTokensTotalSupply = bound(lpTokensTotalSupply, MINIMUM_LIQUIDITY, type(uint112).max);

        uint256 shortFormLiquidity = sqrt(amountAToAdd * amountBToAdd);
        uint256 uniswapLiquidity =
            min((amountAToAdd * lpTokensTotalSupply) / reservesA, (amountBToAdd * lpTokensTotalSupply) / reservesB);
        uint256 diff = shortFormLiquidity > uniswapLiquidity
            ? shortFormLiquidity - uniswapLiquidity
            : uniswapLiquidity - shortFormLiquidity;

        // string memory headers = "lpTokensTotalSupply,reservesA,reservesB,amountAToAdd,amountBToAdd,shortFormLiquidity,uniswapLiquidity,diff";
        string memory values = string(
            abi.encodePacked(
                // uintToString(lpTokensTotalSupply),
                // ",",
                // uintToString(reservesA),
                // ",",
                // uintToString(reservesB),
                // ",",
                // uintToString(amountAToAdd),
                // ",",
                // uintToString(amountBToAdd),
                // ",",
                uintToString(shortFormLiquidity),
                ",",
                uintToString(uniswapLiquidity),
                ",",
                uintToString(diff)
            )
        );

        vm.writeLine(file, values);
    }
    //---------------------------------------------------/s/
    //                       utils                        //
    //---------------------------------------------------//

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

    function uintToString(uint256 v) internal pure returns (string memory) {
        return vm.toString(v);
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

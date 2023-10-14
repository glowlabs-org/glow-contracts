// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "@/libraries/ABDKMath64x64.sol";

library HalfLifeCarbonCreditAuction {
    /// @dev 1 week in seconds
    uint256 constant SECONDS_IN_YEAR = uint256(7 days);

    /**
     * @notice calculates the value remaining after a given amount of time has elapsed
     *         - using a half-life of 52 weeks
     * @param initialValue the initial value
     * @param elapsedSeconds the number of seconds that have elapsed
     * @return value - the value remaining given a half-life of 52 weeks
     */
    function calculateHalfLifeValue(uint256 initialValue, uint256 elapsedSeconds) public pure returns (uint256) {
        // Convert the half-life from months to seconds
        uint256 halfLifeSeconds = SECONDS_IN_YEAR;

        // Calculate the ratio of elapsed time to half-life in fixed point format
        int128 tOverT =
            ABDKMath64x64.div(ABDKMath64x64.fromUInt(elapsedSeconds), ABDKMath64x64.fromUInt(halfLifeSeconds));

        // Calculate (1/2)^(t/T) using the fact that e^(ln(0.5)*t/T) = (0.5)^(t/T)
        int128 halfPowerTOverT =
            ABDKMath64x64.exp(ABDKMath64x64.mul(ABDKMath64x64.ln(ABDKMath64x64.divu(1, 2)), tOverT));

        // Calculate the final amount
        uint256 finalValue = ABDKMath64x64.mulu(halfPowerTOverT, initialValue);

        return finalValue;
    }
}

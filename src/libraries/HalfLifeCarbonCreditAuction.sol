// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ABDKMath64x64} from "@/libraries/ABDKMath64x64.sol";

library HalfLifeCarbonCreditAuction {
    /**
     * @dev the halving period in seconds (7 days)
     * @dev the price of the carbon credit auction decays with a half-life or 7 days
     *         - the price will shrink exponentially every 7 days unless there are purchases
     */
    uint256 constant HALVING_PERIOD = uint256(7 days);

    /**
     * @notice calculates the value remaining after a given amount of time has elapsed
     *         - using a half-life of 52 weeks
     * @param initialValue the initial value
     * @param elapsedSeconds the number of seconds that have elapsed
     * @return value - the value remaining given a half-life of 52 weeks
     */
    function calculateHalfLifeValue(uint256 initialValue, uint256 elapsedSeconds) public pure returns (uint256) {
        if (elapsedSeconds == 0) {
            return initialValue;
        }
        // Convert the half-life from months to seconds
        uint256 halfLifeSeconds = HALVING_PERIOD;

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

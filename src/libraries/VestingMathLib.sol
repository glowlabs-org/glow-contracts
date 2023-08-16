// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

library VestingMathLib {
    /// @dev the maximum amount of seconds a second can vest for
    /// @dev this is to prevent a second from over-vesting in payout
    /// @dev since rewards vest at 1% per week, this is 100 weeks
    uint256 public constant MAX_VESTING_SECONDS = uint256(7 days) * 100;

    /**
     * @dev Find total owed now and slashable balance using the summation of an arithmetic series
     * @dev formula = n/2 * (2a + (n-1)d) or n/2 * (a + l)
     * @dev read more about this  https://github.com/glowlabs-org/glow-docs/issues/4
     * @dev SB stands for slashable balance
     * @param secondsSinceLastPayout - the  amount of seconds since the last payout
     * @param shares - the amount of shares the gca has
     * @param totalShares - the total amount of shares
     * @param rewardsPerSecondForAll - the amount of glow per second all agents earn in total
     * @param vestingRewardsPerSecondForAll - the amount of vesting glow per second for all  agents
     * @return amountNow - the amount of glow owed now
     * @return slashableBalance - the amount of glow that is added to the slashable balance
     */
    function getAmountNowAndSB(
        uint256 secondsSinceLastPayout,
        uint256 shares,
        uint256 totalShares,
        uint256 rewardsPerSecondForAll,
        uint256 vestingRewardsPerSecondForAll
    ) internal pure returns (uint256 amountNow, uint256 slashableBalance) {
        //Add 1 second to ensure last second is counted
        //TODO: double check with {test_amountNowAndSb} in tests
        // secondsSinceLastPayout += 1;
        uint256 totalRewards = secondsSinceLastPayout * rewardsPerSecondForAll * shares / totalShares;

        uint256 fullyVestedSeconds;
        if (secondsSinceLastPayout > MAX_VESTING_SECONDS) {
            fullyVestedSeconds = secondsSinceLastPayout - MAX_VESTING_SECONDS;
            amountNow += fullyVestedSeconds * rewardsPerSecondForAll * shares / totalShares;
            secondsSinceLastPayout -= fullyVestedSeconds;
        }
        amountNow +=
            secondsSinceLastPayout * (secondsSinceLastPayout * vestingRewardsPerSecondForAll * shares / totalShares) / 2;
        slashableBalance = totalRewards - amountNow;
    }
}

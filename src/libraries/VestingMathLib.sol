// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

uint256 constant VESTING_PERIODS = 100;
/// @dev the maximum amount of seconds a second can vest for
/// @dev this is to prevent a second from over-vesting in payout
/// @dev since rewards vest at 1% per week, this is 100 weeks
uint256 constant MAX_VESTING_SECONDS = uint256(7 days) * 100;

library VestingMathLib {
    /**
     * @dev Find total owed now and slashable balance using the summation of an arithmetic series
     * @dev formula = n/2 * (2a + (n-1)d) or n/2 * (a + l)
     * @dev read more about this  https://github.com/glowlabs-org/glow-docs/issues/4
     * @param rewardsPerSecond - the amount of glow per second the agent earns
     * @param secondsActive - the amount of seconds the agent has worked on a given shift
     * @param secondsStopped - the amount of seconds since the agent has stopped working on their shift
     * @param amountAlreadyWithdrawn - the amount of glow already withdrawn by the agent
     * @return withdrawableAmount - the amount of glow owed now
     * @return slashableAmount - the total slashable amount of glow (total owed - withdrawableAmount)
     */
    function calculateWithdrawableAmountAndSlashableAmount(
        uint256 rewardsPerSecond,
        uint256 secondsActive,
        uint256 secondsStopped,
        uint256 amountAlreadyWithdrawn
    ) internal pure returns (uint256 withdrawableAmount, uint256 slashableAmount) {
        //Placeholder for fully vested seconds.
        uint256 fullyVestedSeconds;

        //If (secondsActive + secondsStopped) > MAX_VESTING_SECONDS,
        //That means that there are some seconds that are fully vested.
        if (secondsActive + secondsStopped > MAX_VESTING_SECONDS) {
            //The fully vested seconds are as follows:
            fullyVestedSeconds = secondsActive + secondsStopped - MAX_VESTING_SECONDS;
        }

        //We make sure that the fully vested seconds are not greater than the seconds active.
        //This can happen as secondsStopped grows once the agent stops working
        if (fullyVestedSeconds > secondsActive) {
            fullyVestedSeconds = secondsActive;
        }

        //The fully vested rewards are a result of the fully vested seconds * the rewards per second.
        uint256 fullyVestedRewards = rewardsPerSecond * fullyVestedSeconds;

        //The partially vested seconds are the seconds active minus the fully vested seconds.
        uint256 partiallyVestedSeconds = secondsActive - fullyVestedSeconds;

        uint256 lowestValueSecond = (1 + secondsStopped) * rewardsPerSecond / MAX_VESTING_SECONDS;

        uint256 highestValueSecond = (secondsActive + secondsStopped) * rewardsPerSecond / MAX_VESTING_SECONDS;
        if (highestValueSecond > rewardsPerSecond) {
            highestValueSecond = rewardsPerSecond;
        }

        //Arithmetic series
        uint256 partiallyVestedSecondsValue = partiallyVestedSeconds * (lowestValueSecond + highestValueSecond) / 2;

        uint256 totalRewards = secondsActive * rewardsPerSecond;
        withdrawableAmount = fullyVestedRewards + partiallyVestedSecondsValue;
        slashableAmount = totalRewards - withdrawableAmount;
        withdrawableAmount -= amountAlreadyWithdrawn;

        return (withdrawableAmount, slashableAmount);
    }
}

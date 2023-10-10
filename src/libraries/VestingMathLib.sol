// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/console.sol";

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

        //100 * 100 / 100
        uint256 highestValueSecond = (secondsActive + secondsStopped) * rewardsPerSecond / MAX_VESTING_SECONDS;
        if (highestValueSecond > rewardsPerSecond) {
            highestValueSecond = rewardsPerSecond;
        }

        //Arithmetic series
        uint256 partiallyVestedSecondsValue = partiallyVestedSeconds * (lowestValueSecond + highestValueSecond) / 2;

        uint256 totalRewards = secondsActive * rewardsPerSecond;
        withdrawableAmount = fullyVestedRewards + partiallyVestedSecondsValue - amountAlreadyWithdrawn;
        slashableAmount = totalRewards - withdrawableAmount;

        return (withdrawableAmount, slashableAmount);
    }
}

contract ProofOfConceptVestingLib {
    uint256 private constant REWARDS_PER_SECOND = uint256(10_000 ether) / uint256(7 days);

    struct PayoutHelper {
        uint64 shiftStartTimestamp;
        uint64 shiftEndTimestamp;
        uint64 rewardPerSecond;
        uint256 amountAlreadyWithdrawn;
    }

    //Address -> nonce -> PayoutHelper
    //A nonce occurs every time the salary changes.
    struct Status {
        bool isSlashed;
        bool isAgent;
    }

    mapping(address => mapping(uint256 => PayoutHelper)) private _payoutHelpers;
    mapping(address => uint256) public currentPayoutNonce;
    mapping(address => Status) public status;

    //First time addittion
    function addAgent(address agent) public {
        require(!status[agent].isAgent, "Agent already added");
        require(!status[agent].isSlashed, "Agent is slashed");
        uint256 userCurrentPayoutNonce = currentPayoutNonce[agent];
        _payoutHelpers[agent][userCurrentPayoutNonce] = PayoutHelper({
            shiftStartTimestamp: uint64(block.timestamp),
            shiftEndTimestamp: 0, //means shift hasn't ended
            rewardPerSecond: uint64(REWARDS_PER_SECOND),
            amountAlreadyWithdrawn: 0
        });

        status[agent] = Status({isSlashed: false, isAgent: true});
    }

    function removeAgent(address agent) public {
        if (!status[agent].isAgent) revert("Agent doesn't exist");
        if (status[agent].isSlashed) revert("Agent is slashed");
        ++currentPayoutNonce[agent];
        status[agent].isAgent = false;
    }

    function getDataToCalculatePayout(address agent, uint256 nonce)
        internal
        view
        returns (uint256 rewardPerSecond, uint256 secondsActive, uint256 secondsStopped, uint256 amountAlreadyWithdrawn)
    {
        PayoutHelper memory payoutHelper = _payoutHelpers[agent][nonce];
        rewardPerSecond = payoutHelper.rewardPerSecond;
        if (payoutHelper.shiftStartTimestamp == 0) revert("Shift hasn't started yet");
        if (payoutHelper.shiftEndTimestamp != 0) {
            secondsStopped = block.timestamp - payoutHelper.shiftEndTimestamp;
            secondsActive = payoutHelper.shiftEndTimestamp - payoutHelper.shiftStartTimestamp;
        } else {
            secondsActive = block.timestamp - payoutHelper.shiftStartTimestamp;
        }
        amountAlreadyWithdrawn = payoutHelper.amountAlreadyWithdrawn;
        return (rewardPerSecond, secondsActive, secondsStopped, amountAlreadyWithdrawn);
    }

    function payoutData(address agent, uint256 nonce) public view returns (uint256, uint256) {
        (uint256 rewardPerSecond, uint256 secondsActive, uint256 secondsStopped, uint256 amountAlreadyWithdrawn) =
            getDataToCalculatePayout(agent, nonce);

        (uint256 withdrawableAmount, uint256 slashableAmount) = VestingMathLib
            .calculateWithdrawableAmountAndSlashableAmount(
            rewardPerSecond, secondsActive, secondsStopped, amountAlreadyWithdrawn
        );

        return (withdrawableAmount, slashableAmount);
    }

    function nextPayoutAmount(address agent, uint256 nonce) public view returns (uint256) {
        (uint256 withdrawableAmount,) = payoutData(agent, nonce);
        return withdrawableAmount;
    }

    function claimPayout(address agent, uint256 nonce) public {
        uint256 withdrawableAmount = nextPayoutAmount(agent, nonce);
        _payoutHelpers[agent][nonce].amountAlreadyWithdrawn += withdrawableAmount;
    }

    function payoutHelper(address agent, uint256 nonce) public view returns (PayoutHelper memory) {
        return _payoutHelpers[agent][nonce];
    }
}

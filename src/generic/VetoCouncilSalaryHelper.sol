// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {VestingMathLib} from "@/libraries/VestingMathLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";


//TODO: Error logic bug where the payout wont carry over when a new nonce is started.....
/**
 * @param rewardPerSecond - the amount of tokens to be distributed per second
 * @param lastApplicableTimestamp - the last time the rewardPerSecond is applicable
 * @dev all agents share the same `rewardPerSecond` for each `nonce` since they all earn at the same rate
 *             - so it's not necessary to track rewardPerSecond on an individual basis.
 */
struct NonceHelper {
    uint64 rewardPerSecond;
    uint64 lastApplicableTimestamp;
}

/**
 * @param shiftStartTimestamp - marks the start of a shift
 * @param shiftEndTimestamp - marks the end of a shift
 * @param amountAlreadyWithdrawn - the amount of tokens an agent has already withdrawn from this shift
 */
struct PayoutHelper {
    uint64 shiftStartTimestamp;
    uint64 shiftEndTimestamp;
    uint128 amountAlreadyWithdrawn;
}
//amount already withdrawn can be packed into 128 bits
//2**128-1 / 1e18 = 3.4e20. It would take 1307692307692307.8 years to overflow at 5000 glow per week

/**
 * @param isActive - whether or not the agent is active
 * @param isSlashed - whether or not the agent is slashed
 * @param currentPaymentNonce - the nonce at which the agent's current shift started
 */
struct Status {
    bool isActive;
    bool isSlashed;
    uint120 currentPaymentNonce;
}

/**
 * @title VetoCouncilSalaryHelper
 * @notice A library to help with the salary of the Veto Council
 *         -  handles the salary and payout of the Veto Council
 * @author DavidVorick
 * @author 0xSimon(twitter) - 0xSimbo(github)
 * @dev a nonce is a unique identifier for a shift and is incremented every time the salary rate changes
 *         - if an agent is removed before the rate has changed, they will earn until their `shiftEndTimestamp`
 *  @dev payouts vest linearly at 1% per week.
 *         - It takes 100 weeks for a payout to fully vest
 */
contract VetoCouncilSalaryHelper {
    error HashesNotUpdated();
    error CannotSetNonceToZero();

    /**
     * @notice The nonce at which the current shift started
     * @dev store as 1 to avoid cold sstore for the first proposal
     */
    uint256 public paymentNonce = 1;

    /**
     * @dev (Nonce -> NonceHelper)
     */
    mapping(uint256 => NonceHelper) internal _nonceHelper;

    /**
     * @dev (Agent -> Payout Nonce -> PayoutHelper)
     */
    mapping(address => mapping(uint256 => PayoutHelper)) private _payoutHelpers;

    /**
     * @dev (Agent -> Status)
     */
    mapping(address => Status) private _status;

    /**
     * ----------------------------------------------
     */
    /**
     * ----------       EXTERNAL VIEW --------------
     */
    /**
     * ----------------------------------------------
     */

    /**
     * @notice Returns the payout data for an agent
     * @dev if the `shiftEndTimestamp` is 0, then the shift hasn't ended yet
     * @param agent - the address of the agents
     * @param nonce - the nonce of the payout
     */
    function payoutHelper(address agent, uint256 nonce) public view returns (PayoutHelper memory) {
        return _payoutHelpers[agent][nonce];
    }

    /**
     * @notice Returns the (withdrawableAmount, slashableAmount) for an agent for a given nonce
     * @param agent - the address of the agents
     * @param nonce - the nonce of the payout
     * @return (withdrawableAmount, slashableAmount) - the amount of tokens that can be withdrawn and the amount that are still vesting
     */
    function payoutData(address agent, uint256 nonce) external view returns (uint256, uint256) {
        if (_status[agent].isSlashed) {
            return (0, 0);
        }
        return _payoutData(agent, nonce);
    }

    /**
     * ----------------------------------------------
     */
    /**
     * -------     INTERNAL STATE CHANGING ---------
     */
    /**
     * ----------------------------------------------
     */

    /**
     * @dev Adds a new salary for an agent at the current payment nonce.
     * @dev should not be used independently, it should only be used in the election function
     * @param agent - the address of the agent
     *     TODO: is it possible for an agent to be added twice in the same payment nonce? (i think it is, make sure to double check)
     */
    function addSalary(address agent) internal {
        _payoutHelpers[agent][paymentNonce] = PayoutHelper({
            shiftStartTimestamp: uint64(block.timestamp),
            shiftEndTimestamp: 0, //means shift hasn't ended
            amountAlreadyWithdrawn: 0
        });
    }

    //Only usable in constructor
    function setAgentActive(address agent) internal {
        _status[agent] = Status({isActive: true, isSlashed: false, currentPaymentNonce: uint64(paymentNonce)});
        return;
    }

    function _removeSalary(address agent) internal {
        uint256 currentNonce = _status[agent].currentPaymentNonce;
        _payoutHelpers[agent][currentNonce].shiftEndTimestamp = uint64(block.timestamp);
    }

    function claimPayout(address agent, uint256 nonce, IERC20 token) internal {
        uint256 withdrawableAmount = nextPayoutAmount(agent, nonce);
        _payoutHelpers[agent][nonce].amountAlreadyWithdrawn += uint128(withdrawableAmount);
        SafeERC20.safeTransfer(token, agent, withdrawableAmount);
    }

    /**
     * ----------------------------------------------
     */
    /**
     * -------     INTERNAL VIEW ---------
     */
    /**
     * ----------------------------------------------
     */
    function getDataToCalculatePayout(address agent, uint256 nonce)
        internal
        view
        returns (uint256 rewardPerSecond, uint256 secondsActive, uint256 secondsStopped, uint256 amountAlreadyWithdrawn)
    {
        PayoutHelper memory payoutHelper = _payoutHelpers[agent][nonce];
        NonceHelper memory nonceHelper = _nonceHelper[nonce];

        rewardPerSecond = nonceHelper.rewardPerSecond;
        if (payoutHelper.shiftStartTimestamp == 0) revert("Shift hasn't started yet");
        uint256 shiftEndTimestamp = payoutHelper.shiftEndTimestamp;
        if (nonceHelper.lastApplicableTimestamp != 0) {
            shiftEndTimestamp = nonceHelper.lastApplicableTimestamp;
        }
        //This means the shift has ended
        if (shiftEndTimestamp != 0) {
            secondsStopped = block.timestamp - shiftEndTimestamp;
            secondsActive = shiftEndTimestamp - payoutHelper.shiftStartTimestamp;
        } else {
            secondsActive = block.timestamp - payoutHelper.shiftStartTimestamp;
        }
        amountAlreadyWithdrawn = payoutHelper.amountAlreadyWithdrawn;
        return (rewardPerSecond, secondsActive, secondsStopped, amountAlreadyWithdrawn);
    }

    function _payoutData(address agent, uint256 nonce) private view returns (uint256, uint256) {
        (uint256 rewardPerSecond, uint256 secondsActive, uint256 secondsStopped, uint256 amountAlreadyWithdrawn) =
            getDataToCalculatePayout(agent, nonce);
        // console.log("rewardPerSecond", rewardPerSecond);
        // console.log("secondsActive", secondsActive);
        // console.log("secondsStopped", secondsStopped);
        // console.log("amountAlreadyWithdrawn", amountAlreadyWithdrawn);
        (uint256 withdrawableAmount, uint256 slashableAmount) = VestingMathLib
            .calculateWithdrawableAmountAndSlashableAmount(
            rewardPerSecond, secondsActive, secondsStopped, amountAlreadyWithdrawn
        );

        return (withdrawableAmount, slashableAmount);
    }

    function nextPayoutAmount(address agent, uint256 nonce) internal view returns (uint256) {
        (uint256 withdrawableAmount,) = _payoutData(agent, nonce);
        return withdrawableAmount;
    }

    function removeAgent(address agent, uint256 agentPayoutNonce, uint256 shiftEndTimestamp, bool slash) internal {
        uint256 _paymentNonce = paymentNonce;

        //1 hot sstore
        if (slash) {
            _status[agent] = Status({isActive: false, isSlashed: true, currentPaymentNonce: type(uint120).max});
        } else {
            _status[agent] = Status({isActive: false, isSlashed: false, currentPaymentNonce: type(uint120).max});
        }

        //1 hot sstore
        _payoutHelpers[agent][agentPayoutNonce].shiftEndTimestamp = uint64(shiftEndTimestamp);
        return;
    }

    function agentStatus(address agent) public view returns (Status memory) {
        return _status[agent];
    }

    /**
     * @param agent The address of the agent to be checked
     */
    function _isCouncilMember(address agent) internal view returns (bool) {
        return _status[agent].isActive;
    }

    function nonceHelper(uint256 nonce) public view returns (NonceHelper memory) {
        return _nonceHelper[nonce];
    }

    function setRewardPerSecondAtNonce(uint256 nonce, uint256 rewardPerSecond) internal {
        if (nonce == 0) _revert(CannotSetNonceToZero.selector);
        _nonceHelper[nonce] = NonceHelper({rewardPerSecond: uint64(rewardPerSecond), lastApplicableTimestamp: 0});
    }

    function handlePotentialSalaryRateChange(address agentThatIsBeingAdded, uint256 newRewardsPerSecond) internal {
        uint256 _paymentNonce = paymentNonce;
        //If the reward per second hasnt changed
        if (newRewardsPerSecond == _nonceHelper[_paymentNonce].rewardPerSecond) {
            //If the agentThatIsBeingAdded already had a shift that ended on that nonce
            //Then we have to start a new nonce and end the lastApplicableTimestamp 
            if (_payoutHelpers[agentThatIsBeingAdded][_paymentNonce].shiftEndTimestamp != 0) {
                _nonceHelper[_paymentNonce].lastApplicableTimestamp = uint64(block.timestamp);
                ++_paymentNonce;
                paymentNonce = _paymentNonce;
            }
            return;
        }
        _nonceHelper[_paymentNonce].lastApplicableTimestamp = uint64(block.timestamp);
        ++_paymentNonce;
        _nonceHelper[_paymentNonce] =
            NonceHelper({rewardPerSecond: uint64(newRewardsPerSecond), lastApplicableTimestamp: 0});
        paymentNonce = _paymentNonce;
    }

    /**
     * @notice More efficiently reverts with a bytes4 selector
     * @param selector The selector to revert with
     */
    function _revert(bytes4 selector) internal pure {
        assembly {
            mstore(0x0, selector)
            revert(0x0, 0x04)
        }
    }
}

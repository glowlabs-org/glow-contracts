// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {VestingMathLib} from "@/libraries/VestingMathLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVetoCouncil} from "@/interfaces/IVetoCouncil.sol";
import "forge-std/console.sol";

//TODO: Error logic bug where the payout wont carry over when a new nonce is started.....

/// @dev we use a > 0 value as the null address
//      - to avoid deleting a slot and having to reinitialize it with a cold sstore
address constant NULL_ADDRESS = 0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF;
uint8 constant NULL_INDEX = type(uint8).max;

/**
 * @param isActive - whether or not the agent is active
 * @param isSlashed - whether or not the agent is slashed
 * @param indexInArray - the index inside the veto council agents array
 */
struct Status {
    bool isActive;
    bool isSlashed;
    uint8 indexInArray;
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
    error MaxSevenVetoCouncilMembers();

    /**
     * @notice The nonce at which the current shift started
     * @dev store as 1 to avoid cold sstore for the first proposal
     */
    uint256 public paymentNonce = 1;

    /**
     * @dev (Agent -> Status)
     */
    mapping(address => Status) private _status;

    /**
     * @notice an array containing all the veto council agents
     * @dev the null address is represented as 0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF
     */
    address[7] private _vetoCouncilAgents;

    /**
     * @notice paymentNonce -> keccak256(abi.encodePacked(vetoCouncilAgents))
     * @dev used in withdrawing rewards
     */
    mapping(uint256 => bytes32) public paymentNonceToAgentsHash;

    /**
     * @dev payment nonce -> shift start timestamp
     */
    mapping(uint256 => uint256) private _paymentNonceToShiftStartTimestamp;

    uint256 private constant REWARDS_PER_SECOND = 5000 ether / uint256(7 days);

    mapping(address => mapping(uint256 => uint256)) public amountAlreadyWithdrawnFromPaymentNonce;
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
     * @notice Returns the (withdrawableAmount, slashableAmount) for an agent for a given nonce
     * @param agent - the address of the agents
     * @param nonce - the nonce of the payout
     * @return (withdrawableAmount, slashableAmount) - the amount of tokens that can be withdrawn and the amount that are still vesting
     */
    function payoutData(address agent, uint256 nonce, address[] memory agents)
        external
        view
        returns (uint256, uint256)
    {
        if (_status[agent].isSlashed) {
            return (0, 0);
        }
        return _payoutData(agent, nonce, agents);
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

    function initializeAgents(address[] memory agents, uint256 genesisTimestamp) internal {
        address[7] memory initAgents;
        if (agents.length > type(uint8).max) {
            _revert(MaxSevenVetoCouncilMembers.selector);
        }
        uint8 len = uint8(agents.length);
        unchecked {
            for (uint8 i; i < len; ++i) {
                if (isZero(agents[i])) {
                    _revert(IVetoCouncil.ZeroAddressInConstructor.selector);
                }
                initAgents[i] = agents[i];
                _status[agents[i]] = Status({isActive: true, isSlashed: false, indexInArray: i});
            }
            for (uint8 i = len; i < 7; ++i) {
                initAgents[i] = NULL_ADDRESS;
            }
        }
        _vetoCouncilAgents = initAgents;
        paymentNonceToAgentsHash[1] = keccak256(abi.encodePacked(agents));
        _paymentNonceToShiftStartTimestamp[1] = genesisTimestamp;
    }

    function replaceAgent(address oldAgent, address newAgent, bool slashOldAgent) internal returns (bool) {
        uint256 paymentNonceToWriteTo = paymentNonce;
        uint8 agentOldIndex;
        ++paymentNonceToWriteTo;
        bool isOldAgentZeroAddress = isZero(oldAgent);
        bool isNewAgentZeroAddress = isZero(newAgent);
        //If the old agent is the zero addres,
        //We need to loop until we find the first position in the array
        //Until we find a null address as that's where
        //we'll write the new agent to
        if (isOldAgentZeroAddress) {
            for (uint8 i = 1; i <= 7; ++i) {
                uint8 index = 7 - i;
                address _vetoAgent = _vetoCouncilAgents[i];
                if (_vetoAgent == NULL_ADDRESS) {
                    agentOldIndex = index;
                    break;
                }
            }
        } else {
            //load in the old agent status
            Status memory oldAgentStatus = _status[oldAgent];
            //A slashed agent can never become an agent again
            if (oldAgentStatus.isSlashed) {
                return false;
            }
            if (!oldAgentStatus.isActive) {
                //Old Agent cannot be inactive if they're not the zero address
                return false;
            }
            //find old agent index to insert the new agent
            agentOldIndex = oldAgentStatus.indexInArray;
            //Remove the old agent
            _status[oldAgent] = Status({isActive: false, isSlashed: slashOldAgent, indexInArray: NULL_INDEX});
            //If the new agent isnt the empty address, we set the status to active
            if (!isZero(newAgent)) {
                //A new agent cannot be active
                Status memory newAgentStatus = _status[newAgent];
                if (newAgentStatus.isActive) {
                    return false;
                }
                _status[newAgent] = Status({isActive: true, isSlashed: false, indexInArray: agentOldIndex});
            }
            // return;
        }
        _vetoCouncilAgents[agentOldIndex] = isZero(newAgent) ? NULL_ADDRESS : newAgent;
        if (!isZero(newAgent)) {
            _status[newAgent] = Status({isActive: true, isSlashed: false, indexInArray: agentOldIndex});
        }
        paymentNonceToAgentsHash[paymentNonceToWriteTo] =
            keccak256(abi.encodePacked(arrayWithoutNulls(_vetoCouncilAgents)));
        _paymentNonceToShiftStartTimestamp[paymentNonceToWriteTo] = block.timestamp;
        paymentNonce = paymentNonceToWriteTo;
        return true;
    }

    function claimPayout(address agent, uint256 nonce, IERC20 token, address[] memory agents) internal {
        uint256 withdrawableAmount = nextPayoutAmount(agent, nonce, agents);
        amountAlreadyWithdrawnFromPaymentNonce[agent][nonce] += withdrawableAmount;
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
    function getDataToCalculatePayout(address agent, uint256 nonce, address[] memory agents)
        internal
        view
        returns (uint256 rewardPerSecond, uint256 secondsActive, uint256 secondsStopped, uint256 amountAlreadyWithdrawn)
    {
        if (keccak256(abi.encodePacked(agents)) != paymentNonceToAgentsHash[nonce]) {
            revert("Hashes not updated");
        }

        {
            bool found;
            for (uint256 i; i < agents.length; ++i) {
                if (agents[i] == agent) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                revert("Agent not found");
            }
        }
        uint256 rewardPerSecond = REWARDS_PER_SECOND / agents.length;
        uint256 shiftStartTimestamp = _paymentNonceToShiftStartTimestamp[nonce];
        if (shiftStartTimestamp == 0) {
            revert("shift has not started");
        }

        uint256 shiftEndTimestamp = _paymentNonceToShiftStartTimestamp[nonce + 1];

        //This means the shift has ended
        if (shiftEndTimestamp != 0) {
            secondsStopped = block.timestamp - shiftEndTimestamp;
            secondsActive = shiftEndTimestamp - shiftStartTimestamp;
        } else {
            secondsActive = block.timestamp - shiftStartTimestamp;
        }
        amountAlreadyWithdrawn = amountAlreadyWithdrawnFromPaymentNonce[agent][nonce];
        return (rewardPerSecond, secondsActive, secondsStopped, amountAlreadyWithdrawn);
    }

    function _payoutData(address agent, uint256 nonce, address[] memory agents)
        private
        view
        returns (uint256, uint256)
    {
        (uint256 rewardPerSecond, uint256 secondsActive, uint256 secondsStopped, uint256 amountAlreadyWithdrawn) =
            getDataToCalculatePayout(agent, nonce, agents);
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

    function nextPayoutAmount(address agent, uint256 nonce, address[] memory agents) internal view returns (uint256) {
        (uint256 withdrawableAmount,) = _payoutData(agent, nonce, agents);
        return withdrawableAmount;
    }

    // function removeAgent(address agent, bool slash) private {
    //     uint256 _paymentNonce = paymentNonce;

    //     //1 hot sstore
    //     if (slash) {
    //         _status[agent] = Status({isActive: false, isSlashed: true, indexInArray: NULL_INDEX});
    //     } else {
    //         _status[agent] = Status({isActive: false, isSlashed: false, indexInArray: NULL_INDEX});
    //     }

    //     //1 hot sstore
    //     return;
    // }

    function agentStatus(address agent) public view returns (Status memory) {
        return _status[agent];
    }

    function paymentNonceToShiftStartTimestamp(uint256 nonce) public view returns (uint256) {
        return _paymentNonceToShiftStartTimestamp[nonce];
    }

    /**
     * @param agent The address of the agent to be checked
     */
    function _isCouncilMember(address agent) internal view returns (bool) {
        return _status[agent].isActive;
    }

    function vetoCouncilAgents() external view returns (address[] memory) {
        return arrayWithoutNulls(_vetoCouncilAgents);
    }

    // function nonceHelper(uint256 nonce) public view returns (NonceHelper memory) {
    //     return _nonceHelper[nonce];
    // }

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

    function isZero(address a) private pure returns (bool res) {
        assembly {
            res := iszero(a)
        }
    }

    function arrayWithoutNulls(address[] memory arr) internal pure returns (address[] memory) {
        address[] memory sanitizedArray = new address[](arr.length);
        uint256 numNotNulls;
        unchecked {
            for (uint256 i; i < arr.length; ++i) {
                if (!isZero(arr[i]) && !isNull(arr[i])) {
                    sanitizedArray[numNotNulls] = arr[i];
                    ++numNotNulls;
                }
            }
        }
        assembly ("memory-safe") {
            mstore(sanitizedArray, numNotNulls)
        }

        return sanitizedArray;
    }

    function arrayWithoutNulls(address[7] memory arr) internal pure returns (address[] memory) {
        address[] memory sanitizedArray = new address[](arr.length);
        uint256 numNotNulls;
        unchecked {
            for (uint256 i; i < arr.length; ++i) {
                if (!isZero(arr[i]) && !isNull(arr[i])) {
                    sanitizedArray[numNotNulls] = arr[i];
                    ++numNotNulls;
                }
            }
        }
        assembly ("memory-safe") {
            mstore(sanitizedArray, numNotNulls)
        }

        return sanitizedArray;
    }

    function isNull(address a) internal pure returns (bool res) {
        address _null = NULL_ADDRESS;
        assembly {
            res := eq(a, _null)
        }
    }
}

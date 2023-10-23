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
    error AgentNotFound();
    error ShiftHasNotStarted();
    error HashMismatch();

    /**
     * @dev The amount of GLOW that is awarded per second
     *          -   for the entire veto council
     */
    uint256 private constant REWARDS_PER_SECOND = 5000 ether / uint256(7 days);

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
     * @notice returns the `Status` struct for a given agent
     * @param agent The address of the agent to get the `Status` struct for
     * @return status - the `Status` struct for the given agent
     */
    function agentStatus(address agent) public view returns (Status memory) {
        return _status[agent];
    }

    /**
     * @notice returns the `shiftStartTimestamp` for a given nonce
     * @param nonce The nonce to get the `shiftStartTimestamp` for
     * @return shiftStartTimestamp - the `shiftStartTimestamp` for the given nonce
     */
    function paymentNonceToShiftStartTimestamp(uint256 nonce) public view returns (uint256) {
        return _paymentNonceToShiftStartTimestamp[nonce];
    }

    /**
     * @notice returns the array of veto council agents without null addresses
     * @return sanitizedArray - all currently active veto council agents
     */
    function vetoCouncilAgents() external view returns (address[] memory) {
        return arrayWithoutNulls(_vetoCouncilAgents);
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
     * @dev Initializes the Veto Council
     * @dev should only be used in the constructor
     * @param agents The addresses of the starting council members
     * @param genesisTimestamp The timestamp of the genesis block
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

    /**
     * @dev Add or remove a council member
     * @param oldAgent The address of the agent to be slashed or removed
     * @param newAgent The address of the new agent (0 = no new agent)
     * @param slashOldAgent Whether to slash the agent or not
     * @return - true if the council member was added or removed, false if nothing was done
     */
    function replaceAgent(address oldAgent, address newAgent, bool slashOldAgent) internal returns (bool) {
        //cache the payment nonce
        uint256 paymentNonceToWriteTo = paymentNonce;
        //Cache the old agent index
        uint8 agentOldIndex;
        //Increment the cached payment nonce
        ++paymentNonceToWriteTo;

        bool isOldAgentZeroAddress = isZero(oldAgent);
        bool isNewAgentZeroAddress = isZero(newAgent);
        //If the old agent is the zero addres,
        //We need to loop until we find the first position in the array
        //Until we find a null address as that's where
        //we'll write the new agent to
        //We start from the back of the array as that's where the null address will most likely be
        if (isOldAgentZeroAddress) {
            unchecked {
                for (uint8 i; i < 7; ++i) {
                    uint8 index = 6 - i;
                    address _vetoAgent = _vetoCouncilAgents[index];
                    if (_vetoAgent == NULL_ADDRESS) {
                        agentOldIndex = index;
                        break;
                    }
                }
            }
        } else {
            //load in the old agent status
            Status memory oldAgentStatus = _status[oldAgent];

            //Old Agent cannot be inactive if they're not the zero address
            if (!oldAgentStatus.isActive) {
                return false;
            }
            //find old agent index to insert the new agent
            agentOldIndex = oldAgentStatus.indexInArray;
            //Remove the old agent
            //If the new agent isnt the empty address, we set the status to active
            if (!isNewAgentZeroAddress) {
                //A new agent cannot be active
                Status memory newAgentStatus = _status[newAgent];
                //A slashed agent can never become an agent again
                if (newAgentStatus.isSlashed) {
                    return false;
                }
                //A new agent cannot already be active
                if (newAgentStatus.isActive) {
                    return false;
                }
                //Update the new agent status
                _status[newAgent] = Status({isActive: true, isSlashed: false, indexInArray: agentOldIndex});
            }
            //Set the old agent to inactive as it's not the zero address
            //State changes need to happen after all conditions clear,
            //So we put this change after checking the new agent conditions
            _status[oldAgent] = Status({isActive: false, isSlashed: slashOldAgent, indexInArray: NULL_INDEX});
        }
        _vetoCouncilAgents[agentOldIndex] = isNewAgentZeroAddress ? NULL_ADDRESS : newAgent;

        //Set the hash for the new payment nonce
        paymentNonceToAgentsHash[paymentNonceToWriteTo] =
            keccak256(abi.encodePacked(arrayWithoutNulls(_vetoCouncilAgents)));
        //Set the shift start timestamp for the new payment nonce
        _paymentNonceToShiftStartTimestamp[paymentNonceToWriteTo] = block.timestamp;
        //Set the new payment nonce
        paymentNonce = paymentNonceToWriteTo;
        return true;
    }

    /**
     * @dev Used to payout the council member for their work at a given nonce
     * @param agent The address of the council member
     * @param nonce The payout nonce to claim from
     * @param token The token to pay out (GLOW)
     * @param agents The addresses of the council members that were active at `nonce`
     *         -   This is used to verify that the agent was active at the nonce
     *         -   By comparing the hash of the agents at the nonce to the hash stored in the contract
     */
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

    /**
     * @dev a helper function to get (rewardPerSecond, secondsActive, secondsStopped, amountAlreadyWithdrawn)
     * @param agent The address of the agent to get the data for
     * @param nonce The nonce to get the data for
     * @param agents The addresses of the council members that were active at `nonce`
     *         -   This is used to verify that the agent was active at the nonce
     *         -   By comparing the hash of the agents at the nonce to the hash stored in the contract
     */

    function getDataToCalculatePayout(address agent, uint256 nonce, address[] memory agents)
        internal
        view
        returns (uint256 rewardPerSecond, uint256 secondsActive, uint256 secondsStopped, uint256 amountAlreadyWithdrawn)
    {
        if (keccak256(abi.encodePacked(agents)) != paymentNonceToAgentsHash[nonce]) {
            _revert(HashMismatch.selector);
        }

        {
            bool found;
            unchecked {
                for (uint256 i; i < agents.length; ++i) {
                    if (agents[i] == agent) {
                        found = true;
                        break;
                    }
                }
            }
            if (!found) {
                _revert(AgentNotFound.selector);
            }
        }

        //Should not get a divison by zero error,
        //Since found should have reverted beforehand.
        uint256 rewardPerSecond = REWARDS_PER_SECOND / agents.length;
        uint256 shiftStartTimestamp = _paymentNonceToShiftStartTimestamp[nonce];
        if (shiftStartTimestamp == 0) {
            _revert(ShiftHasNotStarted.selector);
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

    /**
     * @dev a helper function to get (rewardPerSecond, secondsActive, secondsStopped, amountAlreadyWithdrawn)
     * @param agent The address of the agent to get the data for
     * @param nonce The nonce to get the data for
     * @param agents The addresses of the council members that were active at `nonce`
     *         -   This is used to verify that the agent was active at the nonce
     *         -   By comparing the hash of the agents at the nonce to the hash stored in the contract
     */
    function _payoutData(address agent, uint256 nonce, address[] memory agents)
        private
        view
        returns (uint256, uint256)
    {
        (uint256 rewardPerSecond, uint256 secondsActive, uint256 secondsStopped, uint256 amountAlreadyWithdrawn) =
            getDataToCalculatePayout(agent, nonce, agents);
        (uint256 withdrawableAmount, uint256 slashableAmount) = VestingMathLib
            .calculateWithdrawableAmountAndSlashableAmount(
            rewardPerSecond, secondsActive, secondsStopped, amountAlreadyWithdrawn
        );

        return (withdrawableAmount, slashableAmount);
    }

    /**
     * @dev returns the amount of tokens that can be withdrawn by an agent for a given nonce
     * @param agent The address of the agent to get the withdrawable amount for
     * @param nonce The nonce to get the withdrawable amount for
     * @param agents The addresses of the council members that were active at `nonce`
     *         -   This is used to verify that the agent was active at the nonce
     *         -   By comparing the hash of the agents at the nonce to the hash stored in the contract
     * @return withdrawableAmount - the amount of tokens that can be withdrawn by the agent
     */
    function nextPayoutAmount(address agent, uint256 nonce, address[] memory agents) internal view returns (uint256) {
        (uint256 withdrawableAmount,) = _payoutData(agent, nonce, agents);
        return withdrawableAmount;
    }

    /**
     * @param agent The address of the agent to be checked
     */
    function _isCouncilMember(address agent) internal view returns (bool) {
        return _status[agent].isActive;
    }

    /**
     * @dev efficiently determines if an address is the zero address
     * @param a the address to check
     * @return res - true if the address is the zero address
     */
    function isZero(address a) private pure returns (bool res) {
        assembly {
            res := iszero(a)
        }
    }

    /**
     * @dev removes all null addresses from an array
     * @param arr the array to sanitize
     * @dev used to sanitize _vetoCouncilAgents before encoding and hashing
     * @return sanitizedArray - the sanitized array
     */
    function arrayWithoutNulls(address[7] memory arr) internal pure returns (address[] memory) {
        address[] memory sanitizedArray = new address[](arr.length);
        uint256 numNotNulls;
        unchecked {
            for (uint256 i; i < arr.length; ++i) {
                if (!isNull(arr[i])) {
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

    /**
     * @dev efficiently determines if an address is null address
     * @param a the address to check
     * @return res - true if the address is the null address, false otherwise
     */
    function isNull(address a) internal pure returns (bool res) {
        address _null = NULL_ADDRESS;
        assembly {
            res := eq(a, _null)
        }
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

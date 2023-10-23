// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IVetoCouncil} from "@/interfaces/IVetoCouncil.sol";
import {VestingMathLib} from "@/libraries/VestingMathLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGlow} from "@/interfaces/IGlow.sol";
import {VetoCouncilSalaryHelper, Status} from "@/generic/VetoCouncilSalaryHelper.sol";

/**
 * @title VetoCouncil
 * @notice A contract for managing the Glow veto council
 * @dev This contract is used to manage the Glow veto council. The council is made up of maximum 7 members
 *             - council members can be added and removed by the governance contract
 *             - council member payouts are vested over 100 weeks
 *             - council members can veto proposals inside {Governance}
 */
contract VetoCouncil is IVetoCouncil, VetoCouncilSalaryHelper {
    /// @notice the address of the governance contract
    address public immutable GOVERNANCE;

    /// @notice the address of the GLOW token
    IERC20 public immutable GLOW_TOKEN;

    /// @notice the veto council is awared 10_000 GLOW per week
    uint256 public constant REWARDS_PER_SECOND_FOR_ALL = 5_000 ether / uint256(7 days);

    /// @dev 1% of the rewards vest per week
    uint256 public constant VESTING_REWARDS_PER_SECOND_FOR_ALL = REWARDS_PER_SECOND_FOR_ALL / (100 * 86400 * 7);

    /// @notice the maximum number of council members
    uint256 public constant MAX_COUNCIL_MEMBERS = 7;

    /// @notice the genesis timestamp of the glow protocol
    uint256 public immutable GENESIS_TIMESTAMP;

    /**
     * @notice the number of council members
     * @dev this is equivalent to `vetoCouncilAgents`.length
     * @dev we use this variable to avoid having to call `vetoCouncilAgents.length` in the `addAndRemoveCouncilMember` function
     *         - it reduces gas by not having to iterate over the _vetoCouncilAgents array in VetoCouncilSalaryHelper
     *         - To find the true number of council members
     */
    uint256 public numberOfCouncilMembers;

    //-------------- CONSTRUCTOR -----------------

    /**
     * @param governance the address of the governance contract
     * @param _glowToken the address of the GLOW token
     * @param _startingAgents the addresses of the starting council members
     * @dev starting with zero agents will cause a divide by zero error
     *     - It's expected that _startingAgents will never be empty
     */
    constructor(address governance, address _glowToken, address[] memory _startingAgents) payable {
        if (_isZeroAddress(governance)) {
            _revert(IVetoCouncil.ZeroAddressInConstructor.selector);
        }
        if (_isZeroAddress(_glowToken)) {
            _revert(IVetoCouncil.ZeroAddressInConstructor.selector);
        }

        numberOfCouncilMembers = _startingAgents.length;

        //Impossible to have more than 7 council members
        //No risk of large array allocation
        if (_startingAgents.length > MAX_COUNCIL_MEMBERS) {
            _revert(IVetoCouncil.MaxCouncilMembersExceeded.selector);
        }

        //Set governance
        GOVERNANCE = governance;

        //Set GLOW token
        GLOW_TOKEN = IERC20(_glowToken);

        //Pull the Genesis timestamp from the GLOW token
        GENESIS_TIMESTAMP = IGlow(_glowToken).GENESIS_TIMESTAMP();

        initializeAgents(_startingAgents, GENESIS_TIMESTAMP);
    }

    /// @inheritdoc IVetoCouncil
    function addAndRemoveCouncilMember(address oldAgent, address newAgent, bool slashOldAgent)
        external
        override
        returns (bool)
    {
        if (msg.sender != GOVERNANCE) {
            _revert(IVetoCouncil.CallerNotGovernance.selector);
        }
        uint256 _numCouncilMembers = numberOfCouncilMembers;

        //Should already be filtered by the governance contract.
        if (oldAgent == newAgent) {
            return false;
        }

        bool isOldAgentZeroAddress = _isZeroAddress(oldAgent);
        bool isNewAgentZeroAddress = _isZeroAddress(newAgent);
        //if old agent is the zero address, we arent removing an agent
        //however, it it's not, then we are removing an agent
        uint256 numAgentsRemoving = isOldAgentZeroAddress ? 0 : 1;
        //if new agent is the zero address, we arent adding an agent
        //however, if it's not, then we are adding an agent
        uint256 numAgentsAdding = isNewAgentZeroAddress ? 0 : 1;
        if (_numCouncilMembers == 0) {
            //If we don't check this, there can be an underflow
            //and the entire system can freeze;
            //We should not be able to remove an agent if there are no agents
            if (numAgentsRemoving > 0) {
                return false;
            }
        }

        _numCouncilMembers = _numCouncilMembers - numAgentsRemoving + numAgentsAdding;
        if (_numCouncilMembers > MAX_COUNCIL_MEMBERS) {
            return false;
        }

        if (!replaceAgent(oldAgent, newAgent, slashOldAgent)) {
            return false;
        }

        numberOfCouncilMembers = _numCouncilMembers;
        emit IVetoCouncil.VetoCouncilSeatsEdited(oldAgent, newAgent, slashOldAgent);
        return true;
    }

    /// @inheritdoc IVetoCouncil
    function claimPayout(address agent, uint256 nonce, bool sync, address[] memory agents) public {
        if (sync) {
            pullGlowFromInflation();
        }
        VetoCouncilSalaryHelper.claimPayout(agent, nonce, GLOW_TOKEN, agents);
    }

    //----------------- GETTERS -----------------

    /// @inheritdoc IVetoCouncil
    function isCouncilMember(address agent) public view override returns (bool) {
        return VetoCouncilSalaryHelper._isCouncilMember(agent);
    }

    function pullGlowFromInflation() public {
        IGlow(address(GLOW_TOKEN)).claimGLWFromVetoCouncil();
    }

    //----------------- PRIVATE -----------------

    //----------------- UTILS -----------------

    /**
     * @dev efficiently determines if an address is the zero address
     * @param a the address to check
     * @return isZero if the address is the zero address
     */
    function _isZeroAddress(address a) private pure returns (bool isZero) {
        assembly {
            isZero := iszero(a)
        }
    }
}

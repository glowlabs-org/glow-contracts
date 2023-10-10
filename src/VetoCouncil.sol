// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {IVetoCouncil} from "@/interfaces/IVetoCouncil.sol";
import {VestingMathLib} from "@/libraries/VestingMathLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGlow} from "@/interfaces/IGlow.sol";
import "forge-std/console.sol";
import {VetoCouncilSalaryHelper, PayoutHelper, Status} from "@/generic/VetoCouncilSalaryHelper.sol";
//todo: vesting algorith for payout.....

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

    uint256 public numberOfCouncilMembers;

    //-------------- CONSTRUCTOR -----------------

    /**
     * @param governance the address of the governance contract
     * @param _glowToken the address of the GLOW token
     * @param _startingAgents the addresses of the starting council members
     */
    constructor(address governance, address _glowToken, address[] memory _startingAgents) {
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

        //Unchecked block for gas efficiency
        // It's impossible to overflow
        uint256 len = _startingAgents.length;
        uint256 rewardPerSecond = REWARDS_PER_SECOND_FOR_ALL / len;
        VetoCouncilSalaryHelper.setRewardPerSecondAtNonce(1, rewardPerSecond);
        unchecked {
            for (uint256 i; i < len; ++i) {
                address agent = _startingAgents[i];
                if (_isZeroAddress(agent)) {
                    _revert(IVetoCouncil.ZeroAddressInConstructor.selector);
                }
                VetoCouncilSalaryHelper.setAgentActive(agent);
                VetoCouncilSalaryHelper.addSalary(agent);
            }
        }
    }

    //TODO: handle payouts + vesting
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

        if (oldAgent == newAgent) {
            return false;
        }

        Status memory oldAgentData = VetoCouncilSalaryHelper.agentStatus(oldAgent);
        Status memory newAgentData = VetoCouncilSalaryHelper.agentStatus(newAgent);

        //The new agent cannot be an existing veto council member.
        //We check later if the old agent is an existing veto council member
        //We only need to check if the old agent is an existing veto council member
        //  -if the old agent is not the zero address
        // If the old agent is the zero address, we dont need to check if they're active
        if (newAgentData.isActive) {
            return false;
        }

        bool isOldAgentZeroAddress = _isZeroAddress(oldAgent);
        bool isNewAgentZeroAddress = _isZeroAddress(newAgent);
        uint256 numAgentsRemoving = isOldAgentZeroAddress ? 1 : 0;
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

        uint256 newAgentRewardPerSecond = REWARDS_PER_SECOND_FOR_ALL / _numCouncilMembers;
        if (!isOldAgentZeroAddress) {
            if (!oldAgentData.isActive) {
                return false;
            }

            VetoCouncilSalaryHelper.removeAgent(
                oldAgent, oldAgentData.currentPaymentNonce, block.timestamp, slashOldAgent, newAgentRewardPerSecond
            );
        }

        if (!isNewAgentZeroAddress) {
            addSalary(newAgent);
            setAgentActive(newAgent);
        }

        numberOfCouncilMembers = _numCouncilMembers;
        emit IVetoCouncil.VetoCouncilSeatsEdited(oldAgent, newAgent, slashOldAgent);
        return true;
    }

    /// @inheritdoc IVetoCouncil
    function payoutCouncilMember() external {
        _payoutCouncilMember(msg.sender, true);
    }
    //----------------- GETTERS -----------------

    /// @inheritdoc IVetoCouncil
    function isCouncilMember(address agent) public view override returns (bool) {
        return VetoCouncilSalaryHelper._isCouncilMember(agent);
    }

    function pullGlowFromInflation() public {
        IGlow(address(GLOW_TOKEN)).claimGLWFromVetoCouncil();
    }

    // function vetoAgentData(address agent) public view returns (IVetoCouncil.MemberData memory data) {
    //     data = _vetoAgent[agent];
    //     return data;
    // }

    // /// @inheritdoc IVetoCouncil
    // function nextReward(address account) public view returns (uint256 rewardNow, uint256 vestingAmount) {
    //     uint256 totalShares = numberOfCouncilMembers;
    //     uint256 shares = 1;
    //     //TODO: figure out the seconds since last payout in the comp algo
    //     uint256 secondsSinceLastPayout = block.timestamp - _vetoAgent[account].lastUpdatedTimestamp;
    //     //Shares are distributed evenly among council members
    //     (rewardNow, vestingAmount) = VestingMathLib.getAmountNowAndSB(
    //         secondsSinceLastPayout, shares, totalShares, REWARDS_PER_SECOND_FOR_ALL, VESTING_REWARDS_PER_SECOND_FOR_ALL
    //     );
    // }

    //----------------- PRIVATE -----------------

    /**
     * @dev handles the payout according to the vesting algorithm
     */
    function _payoutCouncilMember(address account, bool claimFromInflation) private {
        if (claimFromInflation) {
            pullGlowFromInflation();
        }

        // emit IVetoCouncil.CouncilMemberPayout(account, rewardNow, vestingAmount);
    }

    function claimPayout(address agent, uint256 nonce, bool sync) public {
        if (sync) {
            pullGlowFromInflation();
        }
        VetoCouncilSalaryHelper.claimPayout(agent, nonce, GLOW_TOKEN);
    }

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

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {IVetoCouncil} from "@/interfaces/IVetoCouncil.sol";
import {VestingMathLib} from "@/libraries/VestingMathLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGlow} from "@/interfaces/IGlow.sol";
import "forge-std/console.sol";
//todo: vesting algorith for payout.....

/**
 * @title VetoCouncil
 * @notice A contract for managing the Glow veto council
 * @dev This contract is used to manage the Glow veto council. The council is made up of maximum 7 members
 *             - council members can be added and removed by the governance contract
 *             - council member payouts are vested over 100 weeks
 *             - council members can veto proposals inside {Governance}
 */
contract VetoCouncil is IVetoCouncil {
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

    /// @dev the data for a council member , reference IVetoCouncil for more info
    mapping(address => IVetoCouncil.MemberData) private _vetoAgent;

    /// @dev the list of all council members
    address[] public vetoAgents;

    //-------------- CONSTRUCTOR -----------------
    constructor(address governance, address _glowToken, address[] memory _startingAgents) {
        if (_isZeroAddress(governance)) {
            _revert(IVetoCouncil.ZeroAddressInConstructor.selector);
        }
        if (_isZeroAddress(_glowToken)) {
            _revert(IVetoCouncil.ZeroAddressInConstructor.selector);
        }
        if (_startingAgents.length > MAX_COUNCIL_MEMBERS) {
            _revert(IVetoCouncil.MaxCouncilMembersExceeded.selector);
        }
        GOVERNANCE = governance;
        GLOW_TOKEN = IERC20(_glowToken);
        GENESIS_TIMESTAMP = IGlow(_glowToken).GENESIS_TIMESTAMP();
        unchecked {
            for (uint256 i; i < _startingAgents.length; ++i) {
                if (_isZeroAddress(_startingAgents[i])) {
                    _revert(IVetoCouncil.ZeroAddressInConstructor.selector);
                }
                _vetoAgent[_startingAgents[i]] = IVetoCouncil.MemberData({
                    isActive: true,
                    vestingAmount: 0,
                    lastUpdatedTimestamp: uint64(GENESIS_TIMESTAMP)
                });
            }
        }
        vetoAgents = _startingAgents;
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
        if (oldAgent == newAgent) {
            return false;
        }

        if (!isCouncilMember(oldAgent)) {
            return false;
        }

        if (isCouncilMember(newAgent)) {
            return false;
        }

        bool isOldAgentZeroAddress = _isZeroAddress(oldAgent);
        if (!_isZeroAddress(newAgent)) {
            // we need to figure out if we are replacing or simply adding
            // if we are simply adding that means the new length of the arr will be 1 more than the old
            // if we are replacing, the length will be the same
            // if the old agent is the zero address, we are adding, so we need to add 1 to the length
            // if it isn't the zero address, we are replacing, so we don't need to add 1
            // with this logic, we pessimistically check to ensure we don't go over the limit of max council members
            uint256 amountToAdd = isOldAgentZeroAddress ? 1 : 0;
            // pessimistic check to ensure we don't go over the limit
            if ((vetoAgents.length + amountToAdd) > MAX_COUNCIL_MEMBERS) {
                return false;
            }
            _vetoAgent[newAgent].isActive = true;
            vetoAgents.push(newAgent);
        }
        if (!isOldAgentZeroAddress) {
            //Remove it
            _vetoAgent[newAgent].isActive = false;
            _removeFromVetoCouncilArray(oldAgent);
            if (slashOldAgent) {
                delete _vetoAgent[oldAgent];
            } else {
                _vetoAgent[oldAgent].isActive = false;
            }
        }
        emit IVetoCouncil.VetoCouncilSeatsEdited(oldAgent, newAgent, slashOldAgent);
    }

    /// @inheritdoc IVetoCouncil
    function payoutCouncilMember() external {
        _payoutCouncilMember(msg.sender, true);
    }
    //----------------- GETTERS -----------------

    /// @inheritdoc IVetoCouncil
    function isCouncilMember(address agent) public view override returns (bool) {
        return _vetoAgent[agent].isActive;
    }

    function pullGlowFromInflation() public {
        IGlow(address(GLOW_TOKEN)).claimGLWFromVetoCouncil();
    }

    function vetoAgentData(address agent) public view returns (IVetoCouncil.MemberData memory data) {
        data = _vetoAgent[agent];
        return data;
    }

    function allVetoAgents() public view returns (address[] memory) {
        return vetoAgents;
    }

    /// @inheritdoc IVetoCouncil
    function nextReward(address account) public view returns (uint256 rewardNow, uint256 vestingAmount) {
        uint256 totalShares = vetoAgents.length;
        uint256 shares = 1;
        //TODO: figure out the seconds since last payout in the comp algo
        uint256 secondsSinceLastPayout = block.timestamp - _vetoAgent[account].lastUpdatedTimestamp;
        //Shares are distributed evenly among council members
        (rewardNow, vestingAmount) = VestingMathLib.getAmountNowAndSB(
            secondsSinceLastPayout, shares, totalShares, REWARDS_PER_SECOND_FOR_ALL, VESTING_REWARDS_PER_SECOND_FOR_ALL
        );
    }

    //----------------- PRIVATE -----------------

    function _removeFromVetoCouncilArray(address agent) private {
        uint256 index;
        unchecked {
            for (uint256 i; i < vetoAgents.length; ++i) {
                if (vetoAgents[i] == agent) {
                    index = i;
                    break;
                }
            }
        }
        vetoAgents[index] = vetoAgents[vetoAgents.length - 1];
        vetoAgents.pop();
    }

    /**
     * @dev handles the payout according to the vesting algorithm
     */
    function _payoutCouncilMember(address account, bool claimFromInflation) private {
        if (claimFromInflation) {
            pullGlowFromInflation();
        }
        (uint256 rewardNow, uint256 vestingAmount) = nextReward(account);
        if (rewardNow == 0 && vestingAmount == 0) {
            _revert(IVetoCouncil.NoRewards.selector);
        }
        SafeERC20.safeTransfer(GLOW_TOKEN, account, rewardNow);
        IVetoCouncil.MemberData memory memberData = _vetoAgent[account];
        _vetoAgent[account] = IVetoCouncil.MemberData({
            isActive: memberData.isActive,
            vestingAmount: uint184(vestingAmount + memberData.vestingAmount),
            lastUpdatedTimestamp: uint64(block.timestamp)
        });
        console.log("new vesting amount", _vetoAgent[account].vestingAmount);
        emit IVetoCouncil.CouncilMemberPayout(account, rewardNow, vestingAmount);
    }

    //----------------- UTILS -----------------
    /**
     * @notice More efficiently reverts with a bytes4 selector
     * @param selector The selector to revert with
     */

    function _revert(bytes4 selector) private pure {
        assembly {
            mstore(0x0, selector)
            revert(0x0, 0x04)
        }
    }

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
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IVetoCouncil} from "@/interfaces/IVetoCouncil.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGlow} from "@/interfaces/IGlow.sol";
import {VetoCouncilSalaryHelper} from "@/generic/VetoCouncilSalaryHelper.sol";
/**
 * @title VetoCouncil
 * @notice A contract for managing the Glow veto council
 * @dev This contract is used to manage the Glow veto council. The council is made up of maximum 7 members
 *             - council members can be added and removed by the governance contract
 *             - council member payouts are vested over 100 weeks
 *             - council members can veto proposals inside {Governance}
 */

contract VetoCouncil is IVetoCouncil, VetoCouncilSalaryHelper {
    /* -------------------------------------------------------------------------- */
    /*                                  constants                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice the veto council is awared 5_000 GLOW per week
    uint256 public constant REWARDS_PER_SECOND_FOR_ALL = 5_000 ether / uint256(7 days);

    /// @dev 1% of the rewards vest per week
    uint256 public constant VESTING_REWARDS_PER_SECOND_FOR_ALL = REWARDS_PER_SECOND_FOR_ALL / (100 * 86400 * 7);

    /// @notice the maximum number of council members
    uint256 public constant MAX_COUNCIL_MEMBERS = 7;

    /* -------------------------------------------------------------------------- */
    /*                                 immutables                                 */
    /* -------------------------------------------------------------------------- */
    /// @notice the address of the governance contract
    address public immutable GOVERNANCE;

    /// @notice the address of the GLOW token
    IERC20 public immutable GLOW_TOKEN;

    /// @notice the genesis timestamp of the glow protocol
    uint256 public immutable GENESIS_TIMESTAMP;

    /* -------------------------------------------------------------------------- */
    /*                                 state vars                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice the number of council members
     * @dev this is equivalent to `vetoCouncilMembers`.length
     * @dev we use this variable to avoid having to call `vetoCouncilMembers.length` in the `addAndRemoveCouncilMember` function
     *         - it reduces gas by not having to iterate over the _vetoCouncilMembers array in VetoCouncilSalaryHelper
     *         - To find the true number of council members
     */
    uint256 public numberOfCouncilMembers;

    /* -------------------------------------------------------------------------- */
    /*                                 constructor                                */
    /* -------------------------------------------------------------------------- */
    /**
     * @param governance the address of the governance contract
     * @param _glowToken the address of the GLOW token
     * @param _startingMembers the addresses of the starting council members
     * @dev starting with zero members will cause a divide by zero error
     *     - It's expected that _startingMembers will never be empty
     */
    constructor(address governance, address _glowToken, address[] memory _startingMembers) payable {
        if (_isZeroAddress(governance)) {
            _revert(IVetoCouncil.ZeroAddressInConstructor.selector);
        }
        if (_isZeroAddress(_glowToken)) {
            _revert(IVetoCouncil.ZeroAddressInConstructor.selector);
        }

        numberOfCouncilMembers = _startingMembers.length;

        //Impossible to have more than 7 council members
        //No risk of large array allocation
        if (_startingMembers.length > MAX_COUNCIL_MEMBERS) {
            _revert(IVetoCouncil.MaxCouncilMembersExceeded.selector);
        }

        //Set governance
        GOVERNANCE = governance;

        //Set GLOW token
        GLOW_TOKEN = IERC20(_glowToken);

        //Pull the Genesis timestamp from the GLOW token
        GENESIS_TIMESTAMP = IGlow(_glowToken).GENESIS_TIMESTAMP();

        initializeMembers(_startingMembers, GENESIS_TIMESTAMP);
    }

    /* -------------------------------------------------------------------------- */
    /*                            adding/removing members                         */
    /* -------------------------------------------------------------------------- */
    /// @inheritdoc IVetoCouncil
    function addAndRemoveCouncilMember(address oldMember, address newMember, bool slashOldMember)
        external
        override
        returns (bool)
    {
        if (msg.sender != GOVERNANCE) {
            _revert(IVetoCouncil.CallerNotGovernance.selector);
        }
        uint256 _numCouncilMembers = numberOfCouncilMembers;

        //Should already be filtered by the governance contract.
        if (oldMember == newMember) {
            return false;
        }

        bool isoldMemberZeroAddress = _isZeroAddress(oldMember);
        bool isnewMemberZeroAddress = _isZeroAddress(newMember);
        //if old member is the zero address, we arent removing an member
        //however, it it's not, then we are removing an member
        uint256 numMembersRemoving = isoldMemberZeroAddress ? 0 : 1;
        //if new member is the zero address, we arent adding an member
        //however, if it's not, then we are adding an member
        uint256 numMembersAdding = isnewMemberZeroAddress ? 0 : 1;
        if (_numCouncilMembers == 0) {
            //If we don't check this, there can be an underflow
            //and the entire system can freeze;
            //We should not be able to remove an member if there are no members
            if (numMembersRemoving > 0) {
                return false;
            }
        }

        _numCouncilMembers = _numCouncilMembers - numMembersRemoving + numMembersAdding;
        if (_numCouncilMembers > MAX_COUNCIL_MEMBERS) {
            return false;
        }
        if (!replaceMember(oldMember, newMember, slashOldMember)) {
            return false;
        }

        numberOfCouncilMembers = _numCouncilMembers;
        emit IVetoCouncil.VetoCouncilSeatsEdited(oldMember, newMember, slashOldMember);
        return true;
    }

    /* -------------------------------------------------------------------------- */
    /*                               claiming payouts                             */
    /* -------------------------------------------------------------------------- */
    /// @inheritdoc IVetoCouncil
    function claimPayout(address member, uint256 nonce, bool sync, address[] memory members) public {
        if (sync) {
            pullGlowFromInflation();
        }
        VetoCouncilSalaryHelper.claimPayout(member, nonce, GLOW_TOKEN, members);
    }

    /* -------------------------------------------------------------------------- */
    /*                                view functions                              */
    /* -------------------------------------------------------------------------- */
    /// @inheritdoc IVetoCouncil
    function isCouncilMember(address member) public view override returns (bool) {
        return VetoCouncilSalaryHelper._isCouncilMember(member);
    }

    /// @notice pulls glow from inflation for the veto council contract
    function pullGlowFromInflation() public {
        IGlow(address(GLOW_TOKEN)).claimGLWFromVetoCouncil();
    }

    /* -------------------------------------------------------------------------- */
    /*                               private utils                                */
    /* -------------------------------------------------------------------------- */
    /**
     * @dev efficiently determines if an address is the zero address
     * @param a the address to check
     * @return isZero if the address is the zero address
     */
    function _isZeroAddress(address a) private pure returns (bool isZero) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            isZero := iszero(a)
        }
    }
}

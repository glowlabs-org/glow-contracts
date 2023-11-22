// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IVetoCouncil {
    /* -------------------------------------------------------------------------- */
    /*                                   errors                                    */
    /* -------------------------------------------------------------------------- */
    error CallerNotGovernance();
    error NoRewards();
    error ZeroAddressInConstructor();
    error MaxCouncilMembersExceeded();

    /* -------------------------------------------------------------------------- */
    /*                                   events                                    */
    /* -------------------------------------------------------------------------- */

    /**
     * @param oldMember The address of the member to be slashed or removed
     * @param newMember The address of the new member (0 = no new member)
     * @param slashOldMember Whether to slash the member or not
     */
    event VetoCouncilSeatsEdited(address indexed oldMember, address indexed newMember, bool slashOldMember);

    /**
     * @dev emitted when a council member is paid out
     * @param account The address of the council member
     * @param amountNow The amount paid out now
     * @param amountToBeVested The amount to be vested
     */
    event CouncilMemberPayout(address indexed account, uint256 amountNow, uint256 amountToBeVested);
    /* -------------------------------------------------------------------------- */
    /*                                 state-changing                             */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice Add or remove a council member
     * @param oldMember The address of the member to be slashed or removed
     * @param newMember The address of the new member (0 = no new member)
     * @param slashOldMember Whether to slash the member or not
     * @return - true if the council member was added or removed, false if nothing was done
     *                 - the function should return false if the new member is already a council member
     *                 - if the old member is not a council member, the function should return false
     *                 - if the old member is a council member and the new member is the same as the old member, the function should return false
     *                 - by adding a new member there would be more than 7 council members, the function should return false
     */

    function addAndRemoveCouncilMember(address oldMember, address newMember, bool slashOldMember)
        external
        returns (bool);

    /**
     * @notice Payout the council member
     * @param member The address of the council member
     * @param nonce The payout nonce to claim from
     * @param sync Whether to sync the vesting schedule or not
     * @param members The addresses of the council members that were active at `nonce`
     */
    function claimPayout(address member, uint256 nonce, bool sync, address[] memory members) external;

    /* -------------------------------------------------------------------------- */
    /*                                   view                                    */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice returns true if the member is a council member
     * @param member The address of the member to be checked
     * @return - true if the member is a council member
     */
    function isCouncilMember(address member) external view returns (bool);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IVetoCouncil {
    error CallerNotGovernance();
    error NoRewards();
    error NotInArray(); //see if we need this....
    error ZeroAddressInConstructor();
    error MaxCouncilMembersExceeded();

    /**
     * @notice Add or remove a council member
     * @param oldAgent The address of the agent to be slashed or removed
     * @param newAgent The address of the new agent (0 = no new agent)
     * @param slashOldAgent Whether to slash the agent or not
     * @return - true if the council member was added or removed, false if nothing was done
     *                 - the function should return false if the new agent is already a council member
     *                 - if the old agent is not a council member, the function should return false
     *                 - if the old agent is a council member and the new agent is the same as the old agent, the function should return false
     *                 - by adding a new agent there would be more than 7 council members, the function should return false
     */
    function addAndRemoveCouncilMember(address oldAgent, address newAgent, bool slashOldAgent)
        external
        returns (bool);

    /**
     * @notice Payout the council member
     * @param agent The address of the council member
     * @param nonce The payout nonce to claim from
     * @param sync Whether to sync the vesting schedule or not
     * @param agents The addresses of the council members that were active at `nonce`
     */
    function claimPayout(address agent, uint256 nonce, bool sync, address[] memory agents) external;

    /**
     * @notice returns true if the agent is a council member
     * @param agent The address of the agent to be checked
     * @return - true if the agent is a council member
     */
    function isCouncilMember(address agent) external view returns (bool);

    /**
     * @param oldAgent The address of the agent to be slashed or removed
     * @param newAgent The address of the new agent (0 = no new agent)
     * @param slashOldAgent Whether to slash the agent or not
     */
    event VetoCouncilSeatsEdited(address indexed oldAgent, address indexed newAgent, bool slashOldAgent);

    /**
     * @dev emitted when a council member is paid out
     * @param account The address of the council member
     * @param amountNow The amount paid out now
     * @param amountToBeVested The amount to be vested
     */
    event CouncilMemberPayout(address indexed account, uint256 amountNow, uint256 amountToBeVested);
}

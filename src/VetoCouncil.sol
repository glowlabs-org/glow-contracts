// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract VetoCouncil {
    /// @dev should only be called by the governance contract
    /// @dev must always maintain at least 3 council members
    /// @dev at max 7 council members
    /// @dev while removing a council member, all votes cast by the member should be cancelled.
    function addAndRemoveCouncilMembers(address[] calldata oldMembers, address[] calldata newMembers) external {}

    /// @notice should return true if the account is a council member
    /// @param account the account to check
    /// @return true if the account is a council member
    function isCouncilMember(address account) public view returns (bool) {
        return true;
    }

    /// @notice will payout the council member their respective amount
    /// @param account the address of the council member
    function payoutCouncilMember(address account) external {}

    /// @notice should return the next reward for the council member
    /// @param account the address of the council member
    /// @return the next reward for the council member
    function nextReward(address account) public view returns (uint256) {
        return 0;
    }
}

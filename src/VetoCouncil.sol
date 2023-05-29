// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract VetoCouncil {
    /*
    – Replace existing seat(s) with new council member(s).
    – Remove a veto council member(s).
    – An occupied seat can’t be replaced with an empty seat if the total number of seats is
    3 or fewer.
    – Veto council elections bypass t*/
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
}

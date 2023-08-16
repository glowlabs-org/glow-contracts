// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {IGovernance} from "@/interfaces/IGovernance.sol";

//TEMP!
contract Governance is IGovernance {
    /**
     * @notice Allows the GCC contract to grant nominations to {to} when they retire GCC
     * @param to the address to grant nominations to
     * @param amount the amount of nominations to grant
     */
    function grantNominations(address to, uint256 amount) external override {
        return;
    }

    /// @inheritdoc IGovernance
    function getProposalWithStatus(uint256 proposalId)
        public
        view
        returns (Proposal memory proposal, IGovernance.ProposalStatus)
    {}
}

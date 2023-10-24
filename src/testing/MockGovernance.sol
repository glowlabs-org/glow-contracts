// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@/Governance.sol";
import {IGovernance} from "@/interfaces/IGovernance.sol";

contract MockGovernance is Governance {
    function setProposalStatus(uint256 weekId, IGovernance.ProposalStatus status) public {
        _setProposalStatus(weekId, status);
    }

    function getNominationCostForProposalCreation(uint256 numActiveProposals) public pure returns (uint256) {
        return super._getNominationCostForProposalCreation(numActiveProposals);
    }

    function createSpendNominationsOnProposalDigest(
        IGovernance.ProposalType proposalType,
        uint256 nominationsToSpend,
        uint256 nonce,
        uint256 deadline,
        bytes memory data
    ) external view returns (bytes32) {
        return _createSpendNominationsOnProposalDigest(proposalType, nominationsToSpend, nonce, deadline, data);
    }
}

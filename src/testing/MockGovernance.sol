// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@glow/Governance.sol";
import {IGovernance} from "@glow/interfaces/IGovernance.sol";

contract MockGovernance is Governance {
    /**
     * @param gcc - the GCC contract
     * @param gca - the GCA contract
     * @param vetoCouncil - the Veto Council contract
     * @param grantsTreasury - the Grants Treasury contract
     * @param glw - the GLW contract
     */
    constructor(address gcc, address gca, address vetoCouncil, address grantsTreasury, address glw)
        payable
        Governance(gcc, gca, vetoCouncil, grantsTreasury, glw)
    {}

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

    function getLastExpiredProposalId() public view returns (uint256) {
        return lastExpiredProposalId;
    }

    function getLastExecutedWeek() public view returns (uint256) {
        return lastExecutedWeek;
    }
}

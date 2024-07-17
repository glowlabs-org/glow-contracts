// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {GovernanceV2 as Governance} from "@/GovernanceV2.sol";
import {IGovernanceV2} from "@/interfaces/IGovernanceV2.sol";

contract MockGovernanceV2 is Governance {
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

    function setProposalStatus(uint256 weekId, IGovernanceV2.ProposalStatus status) public {
        _setProposalStatus(weekId, status);
    }

    function getNominationCostForProposalCreation(uint256 numActiveProposals) public pure returns (uint256) {
        return super._getNominationCostForProposalCreation(numActiveProposals);
    }

    function getLastExpiredProposalId() public view returns (uint256) {
        return lastExpiredProposalId;
    }

    function getLastExecutedWeek() public view returns (uint256) {
        return lastExecutedWeek;
    }
}

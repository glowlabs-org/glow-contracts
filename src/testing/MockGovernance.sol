// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@/Governance.sol";
import {IGovernance} from "@/interfaces/IGovernance.sol";

contract MockGovernance is Governance {
    function setMostPopularProposalStatus(uint256 weekId, IGovernance.ProposalStatus status) public {
        _setMostPopularProposalStatus(weekId, status);
    }

    function getNominationCostForProposalCreation(uint256 numActiveProposals) public pure returns (uint256) {
        return super._getNominationCostForProposalCreation(numActiveProposals);
    }
}

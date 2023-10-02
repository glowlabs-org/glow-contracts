// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@/Governance.sol";
import {IGovernance} from "@/interfaces/IGovernance.sol";

contract MockGovernance is Governance {
    function setMostPopularProposalStatus(uint256 weekId, IGovernance.ProposalStatus status) public {
        _setMostPopularProposalStatus(weekId, status);
    }
}

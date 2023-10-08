// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdCheats.sol";
import "forge-std/console.sol";
import {IGovernance} from "@/interfaces/IGovernance.sol";
import {MockGovernance} from "@/testing/MockGovernance.sol";

contract SetMostPopularProposalHandler is Test {
    MockGovernance immutable g;
    mapping(uint256 => IGovernance.ProposalStatus) public mostPopularProposalStatus;

    uint256[] private ghost_proposalIds;
    mapping(uint256 => bool) private ghost_proposalIds_set;

    constructor(address _g) {
        g = MockGovernance(_g);
    }

    function setStatus(uint256 proposalId, IGovernance.ProposalStatus status) external {
        //Keep it contained into 3 keys to test for incorrect masking or shifting
        vm.assume(proposalId < 600);
        g.setProposalStatus(proposalId, status);
        mostPopularProposalStatus[proposalId] = status;
        setGhostproposalId(proposalId);
    }

    function setGhostproposalId(uint256 proposalId) internal {
        if (ghost_proposalIds_set[proposalId]) {
            return;
        }
        ghost_proposalIds.push(proposalId);
        ghost_proposalIds_set[proposalId] = true;
    }

    function allIds() external view returns (uint256[] memory) {
        return ghost_proposalIds;
    }
}

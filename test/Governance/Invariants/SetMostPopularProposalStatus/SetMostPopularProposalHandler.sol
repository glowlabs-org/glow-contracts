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

    uint256[] private ghost_weekIds;
    mapping(uint256 => bool) private ghost_weekIds_set;

    constructor(address _g) {
        g = MockGovernance(_g);
    }

    function setStatus(uint256 weekId, IGovernance.ProposalStatus status) external {
        //Keep it contained into 3 keys to test for incorrect masking or shifting
        vm.assume(weekId < 600);
        g.setMostPopularProposalStatus(weekId, status);
        mostPopularProposalStatus[weekId] = status;
        setGhostWeekId(weekId);
    }

    function setGhostWeekId(uint256 weekId) internal {
        if (ghost_weekIds_set[weekId]) {
            return;
        }
        ghost_weekIds.push(weekId);
        ghost_weekIds_set[weekId] = true;
    }

    function allIds() external view returns (uint256[] memory) {
        return ghost_weekIds;
    }
}

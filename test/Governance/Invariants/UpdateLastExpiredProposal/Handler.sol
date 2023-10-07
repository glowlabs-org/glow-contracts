// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdCheats.sol";
import "forge-std/console.sol";
import {IGovernance} from "@/interfaces/IGovernance.sol";
import {MockGovernance} from "@/testing/MockGovernance.sol";
import {IGCC} from "@/interfaces/IGCC.sol";

interface IMintable is IGCC {
    function mint(address to, uint256 amount) external;
}

contract Handler is Test {
    MockGovernance immutable g;
    IMintable immutable gcc;

    uint256[] private ghost_weekIds;
    mapping(uint256 => bool) private ghost_weekIds_set;

    constructor(address _g, address _gcc) {
        g = MockGovernance(_g);
        gcc = IMintable(_gcc);
    }

    function createProposal() public {
        address oldAgent = address(0x1);
        address newAgent = address(0x2);
        bool slashOldAgent = true;
        uint256 nominationCost = g.costForNewProposal();
        createVetoCouncilElectionOrSlashProposal(address(this), oldAgent, newAgent, slashOldAgent);
        vm.warp(1 weeks);
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

    function createVetoCouncilElectionOrSlashProposal(
        address proposer,
        address oldAgent,
        address newAgent,
        bool slashOldAgent
    ) internal {
        vm.startPrank(proposer);
        uint256 nominationsToUse = g.costForNewProposal();
        gcc.mint(proposer, nominationsToUse);
        gcc.retireGCC(nominationsToUse, proposer);
        g.createVetoCouncilElectionOrSlash(oldAgent, newAgent, slashOldAgent, nominationsToUse);
        vm.stopPrank();
    }
}

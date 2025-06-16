// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@/testing/TestGCC.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";
import {MockGovernance} from "@/testing/MockGovernance.sol";
import {IGovernance} from "@/interfaces/IGovernance.sol";
import {SetMostPopularProposalHandler} from "./SetMostPopularProposalHandler.sol";

contract SetMostPopularProposalTest is Test {
    MockGovernance governance;
    SetMostPopularProposalHandler handler;
    FakeGlow glow;
    FakeGCC gcc;

    function setUp() public {
        //Make sure we don't start at 0
        glow = new FakeGlow();
        gcc = new FakeGCC();
        governance = new MockGovernance({
            gcc: address(gcc),
            gca: address(0x12),
            vetoCouncil: address(0x13),
            grantsTreasury: address(0x14),
            glw: address(glow)
        });
        handler = new SetMostPopularProposalHandler(address(governance));
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SetMostPopularProposalHandler.setStatus.selector;
        FuzzSelector memory fs = FuzzSelector({selectors: selectors, addr: address(handler)});
        targetContract(address(handler));
    }

    /**
     * forge-config: default.invariant.runs = 100
     * forge-config: default.invariant.depth = 10
     *     Side Note For Self: This may break once I add dynamic statuses
     */
    function invariant_setProposalStatus_shouldCorrectlySet() public {
        uint256[] memory proposalIds = handler.allIds();
        unchecked {
            for (uint256 i = 0; i < proposalIds.length; ++i) {
                uint256 proposalId = proposalIds[i];
                IGovernance.ProposalStatus statusFromHandler = handler.mostPopularProposalStatus(proposalId);
                IGovernance.ProposalStatus statusFromGovernance = governance.getProposalStatus(proposalId);
                assertEq(uint256(statusFromHandler), uint256(statusFromGovernance));
            }
        }
    }
}

contract FakeGlow {
    function GENESIS_TIMESTAMP() external view returns (uint256) {
        return block.timestamp;
    }
}

contract FakeGCC {
    function USDC() external view returns (address) {
        return address(0x1);
    }
}

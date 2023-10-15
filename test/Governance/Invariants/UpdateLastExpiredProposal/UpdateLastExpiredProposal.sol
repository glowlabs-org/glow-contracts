// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "@/testing/TestGCC.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";
import {MockGovernance} from "@/testing/MockGovernance.sol";
import {IGovernance} from "@/interfaces/IGovernance.sol";
import {Handler} from "./Handler.sol";
import {TestGCC} from "@/testing/TestGCC.sol";

contract UpdateLastExpiredProposal is Test {
    MockGovernance governance;
    TestGCC gcc;
    Handler handler;

    function setUp() public {
        //Make sure we don't start at 0
        governance = new MockGovernance();
        gcc = new TestGCC(address(10),address(11),address(governance),address(0x12));
        handler = new  Handler(address(governance),address(gcc));
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = Handler.createProposal.selector;
        FuzzSelector memory fs = FuzzSelector({selectors: selectors, addr: address(handler)});
        targetContract(address(handler));
    }

    /**
     * forge-config: default.invariant.runs = 100
     * forge-config: default.invariant.depth = 10
     */
    function invariant_setProposalStatus_shouldCorrectlySet() public {
        uint256[] memory weekIds = handler.allIds();
        if (weekIds.length == 0) {
            return;
        }
        uint256 lastId = weekIds[weekIds.length - 1];
        vm.warp(16 weeks);
        governance.updateLastExpiredProposalId();
        assertEq(governance.lastExpiredProposalId(), lastId);
    }

    function invariant_setProposalStatus_badInvariant_shouldNotCorrectlySet() public {
        uint256[] memory weekIds = handler.allIds();
        if (weekIds.length == 0) {
            return;
        }
        uint256 lastId = weekIds[weekIds.length - 1];
        vm.warp(16 weeks);
        governance.updateLastExpiredProposalId();
        assert(governance.lastExpiredProposalId() != lastId + 1);
        assert(governance.lastExpiredProposalId() != lastId - 1);
    }
}

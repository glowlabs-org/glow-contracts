// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@/testing/TestGCC.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";
import {MockGovernance} from "@/testing/MockGovernance.sol";
import {IGovernance} from "@/interfaces/IGovernance.sol";
import {Handler} from "./Handler.sol";
import {TestGCC} from "@/testing/TestGCC.sol";
import {UnifapV2Factory} from "@unifapv2/UnifapV2Factory.sol";
import {UnifapV2Router} from "@unifapv2/UnifapV2Router.sol";
import {WETH9} from "@/UniswapV2/contracts/test/WETH9.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";

contract UpdateLastExpiredProposal is Test {
    UnifapV2Factory public uniswapFactory;
    WETH9 public weth;
    UnifapV2Router public uniswapRouter;
    MockUSDC usdc;
    MockGovernance governance;
    TestGCC gcc;
    Handler handler;

    function setUp() public {
        //Make sure we don't start at 0
        //Make sure we don't start at 0
        vm.warp(10);
        uniswapFactory = new UnifapV2Factory();
        weth = new WETH9();
        uniswapRouter = new UnifapV2Router(address(uniswapFactory));
        usdc = new MockUSDC();
        governance = new MockGovernance();
        gcc = new TestGCC(address(11),address(governance),address(0x12),address(usdc),address(uniswapRouter));
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
        assertEq(governance.getLastExpiredProposalId(), lastId);
    }

    function invariant_setProposalStatus_badInvariant_shouldNotCorrectlySet() public {
        uint256[] memory weekIds = handler.allIds();
        if (weekIds.length == 0) {
            return;
        }
        uint256 lastId = weekIds[weekIds.length - 1];
        vm.warp(16 weeks);
        governance.updateLastExpiredProposalId();
        assert(governance.getLastExpiredProposalId() != lastId + 1);
        assert(governance.getLastExpiredProposalId() != lastId - 1);
    }
}

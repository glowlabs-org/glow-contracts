// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
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
    FakeGlow glow;
    address vetoCouncil = address(0xfff);
    address grantsTreasury = address(0xdddd);
    address deployer = tx.origin;

    function setUp() public {
        //Make sure we don't start at 0
        //Make sure we don't start at 0
        vm.startPrank(deployer);
        vm.warp(10);
        uint256 deployerNonce = vm.getNonce(deployer);
        address precomputedGCC = computeCreateAddress(deployer, deployerNonce + 6);
        glow = new FakeGlow(); //deployerNonce
        uniswapFactory = new UnifapV2Factory(); //deployerNonce + 1
        weth = new WETH9(); //deployerNonce + 2
        uniswapRouter = new UnifapV2Router(address(uniswapFactory)); //deployerNonce + 3
        usdc = new MockUSDC(); //deployerNonce + 4
        governance = new MockGovernance({
            gcc: address(precomputedGCC),
            gca: address(0x11),
            vetoCouncil: address(vetoCouncil),
            grantsTreasury: address(grantsTreasury),
            glw: address(glow)
        }); //deployerNonce + 5
        gcc = new TestGCC(address(11), address(governance), address(0x12), address(usdc), address(uniswapRouter)); //deployerNonce + 6
        handler = new Handler(address(governance), address(gcc)); //deployerNonce + 7
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = Handler.createProposal.selector;
        FuzzSelector memory fs = FuzzSelector({selectors: selectors, addr: address(handler)});
        targetContract(address(handler));
        vm.stopPrank();
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

contract FakeGlow {
    function GENESIS_TIMESTAMP() public view returns (uint256) {
        return block.timestamp;
    }
}

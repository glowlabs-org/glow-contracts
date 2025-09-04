// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {Forwarder} from "@/Forwarder.sol";
import {USDG} from "@/USDG.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";
import {USDG} from "@/USDG.sol";

contract ForwarderForkSepoliaTest is Test {
    USDG usdg = USDG(0x2a085A3aEA8982396533327c854753Ce521B666d);
    MockUSDC usdc = MockUSDC(0x93C898be98cD2618bA84a6dccF5003d3bBE40356);
    Forwarder forwarder = Forwarder(0x497A3F2d47C716Fe502CD1f82D5B1b16CDfDDC5c);
    address me = address(0x5e230FED487c86B90f6508104149F087d9B1B0A7);

    function setUp() public {
        uint256 fork = vm.createFork(vm.envString("SEPOLIA_RPC_URL"));
        vm.selectFork(fork);
    }

    function test_ForkForwarder() public {
        vm.startPrank(me);
        usdc.mint(me, 100000000 * 1e6);
        usdc.approve(address(forwarder), 100000000 * 1e6);
        assertEq(address(usdg.USDC()), address(usdc), "USDC should be the same");
        // forwarder.swapUSDCAndForwardUSDG(100000000 * 1e6, me, "test");
        // vm.stopPrank();
    }
}

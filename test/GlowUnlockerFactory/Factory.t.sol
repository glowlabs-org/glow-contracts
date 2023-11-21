// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@/testing/TestGCC.sol";
import "forge-std/console.sol";
import {GlowUnlockerFactory} from "@/GlowUnlockerFactory.sol";
import {GlowUnlocker2} from "@/GlowUnlocker2.sol";
import {Glow} from "@/GLOW.sol";

contract GlowUnlockerFactoryTest is Test {
    GlowUnlockerFactory factory;
    address[] accounts;
    uint256[] amounts;
    Glow mockGlow;
    address deployEOA = address(0x111111111111);

    function setUp() public {
        mockGlow = new Glow(address(0x1),address(0x2));
        for (uint256 i = 1; i < 10; i++) {
            accounts.push(address(uint160(i)));
            amounts.push(i);
        }
        vm.startPrank(deployEOA);
        factory = new GlowUnlockerFactory();
        vm.stopPrank();
    }

    function test_DeployUnlocker() public {
        vm.startPrank(deployEOA);
        address unlocker = factory.deployUnlocker(address(mockGlow), accounts, amounts);
        address expectedAddress = factory.computeUnlockerAddress();
        console.log("unlocker address: %s", unlocker);
        console.log("expected address: %s", expectedAddress);
        assertEq(unlocker, expectedAddress);
        vm.stopPrank();
    }
}

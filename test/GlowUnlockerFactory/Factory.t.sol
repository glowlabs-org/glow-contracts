// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@/testing/TestGCC.sol";
import "forge-std/console.sol";
import {GlowUnlockerFactory} from "@/GlowUnlockerFactory.sol";
import {GlowUnlocker2} from "@/GlowUnlocker2.sol";
import {Glow} from "@/GLOW.sol";

contract GlowUnlockerFactoryTest is Test {
    uint256 constant EXPECTED_GLOW = 90_000_000 ether;
    GlowUnlockerFactory factory;
    address[] accounts;
    uint256[] amounts;
    address factoryOwner = address(0x123456789);
    Glow mockGlow;
    GlowUnlocker2 unlocker;

    function setUp() public {
        mockGlow = new Glow(address(0x1),address(0x2));
        uint256 totalGlow;
        for (uint256 i = 1; i < 10; i++) {
            accounts.push(address(uint160(i)));
            //Each address gets 10 million GLOW as the expected amount to be unlocked is 90 million
            amounts.push(10_000_000 ether);
            totalGlow += 10_000_000 ether;
        }
        if (totalGlow != EXPECTED_GLOW) {
            revert("totalGlow does not match expected glow");
        }
        factory = new GlowUnlockerFactory(factoryOwner);
    }

    function test_DeployUnlocker() public {
        vm.startPrank(factoryOwner);
        address unlocker = factory.deployUnlocker(address(mockGlow), accounts, amounts);
        address expectedAddress = factory.computeUnlockerAddress();
        console.log("unlocker address: %s", unlocker);
        console.log("expected address: %s", expectedAddress);
        assertEq(unlocker, expectedAddress);
        vm.stopPrank();
    }
}

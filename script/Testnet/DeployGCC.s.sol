// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {GCC} from "@/GCC.sol";
import {TestGLOW} from "@/testing/TestGLOW.sol";
import {Governance} from "@/Governance.sol";
import {TestGCC} from "@/testing/TestGCC.sol";

contract DeployGCC is Script {
    address gcaAndMinerPool = address(0xffff);
    address earlyLiquidityAddress = address(0x14444);
    address vestingContract = address(0x15555);
    address vetoCouncil = address(0x16666);
    address grantsTreasury = address(0x17777);
    address rewardAddress = address(0x18888);

    function run() external {
        vm.startBroadcast();
        Governance governance = new Governance();
        TestGLOW glow = new TestGLOW(gcaAndMinerPool, vestingContract);
        glow.mint(tx.origin, 100 ether);
        TestGCC gcc = new TestGCC(gcaAndMinerPool, address(governance), address(glow));
        gcc.mint(tx.origin, 100 ether);
        governance.setContractAddresses(address(gcc), gcaAndMinerPool, vetoCouncil, grantsTreasury, address(glow));
        vm.stopBroadcast();
    }
}

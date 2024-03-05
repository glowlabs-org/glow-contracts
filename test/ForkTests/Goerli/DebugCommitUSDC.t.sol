// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {GCC} from "@/GCC.sol";
import {TestGLOW} from "@/testing/TestGLOW.sol";
import {Governance} from "@/Governance.sol";
import {GoerliGCC} from "@/testing/Goerli/GoerliGCC.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";
import {EarlyLiquidity} from "@/EarlyLiquidity.sol";
import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
import {CarbonCreditDescendingPriceAuction} from "@/CarbonCreditDescendingPriceAuction.sol";
import {GoerliMinerPoolAndGCAQuickPeriod} from "@/testing/Goerli/GoerliMinerPoolAndGCA.QuickPeriod.sol";
import {VetoCouncil} from "@/VetoCouncil/VetoCouncil.sol";
import {SafetyDelay} from "@/SafetyDelay.sol";
import {GrantsTreasury} from "@/GrantsTreasury.sol";
import {BatchCommit} from "@/BatchCommit.sol";
import {USDG} from "@/USDG.sol";
import "forge-std/Test.sol";

string constant fileToWriteTo = "deployedContractsGoerli.json";

contract DebugCommitUSDC is Test {
    string mainnetForkUrl = vm.envString("MAINNET_RPC");
    uint256 mainnetFork;
    GCC gcc = GCC(0x21C46173591f39AfC1d2B634b74c98F0576A272B);
    Governance governance = Governance(0x8d01a258bC1ADB728322499E5D84173EA971d665);
    address multisig = 0xc5174BBf649a92F9941e981af68AaA14Dd814F85;
    address other = address(0x32131);
    USDG usdg = USDG(0xe010ec500720bE9EF3F82129E7eD2Ee1FB7955F2);
    USDG usdc = USDG(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    function setUp() public {
        mainnetFork = vm.createFork(mainnetForkUrl);
        vm.selectFork(mainnetFork);
    }

    function test_logAmount() public {
        vm.startPrank(multisig);
        uint256 amount = 175438596;
        usdc.transfer(other, amount);
        vm.stopPrank();

        vm.startPrank(other);
        usdc.approve(address(usdg), amount);
        usdg.swap(other, amount);
        usdg.approve(address(gcc), type(uint256).max);
        gcc.commitUSDC(amount, other, 0);
        uint256 nominations = governance.nominationsOf(other);
        console.log("nominations: ", nominations);
        vm.stopPrank();
    }
}

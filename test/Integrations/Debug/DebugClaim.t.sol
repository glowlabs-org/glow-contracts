// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
// import {GCC} from "@/GCC.sol";
// import {TestGLOW} from "@/testing/TestGLOW.sol";
// import {GoerliGovernanceQuickPeriod} from "@/testing/Goerli/GoerliGovernance.QuickPeriod.sol";
// import {GoerliGCC} from "@/testing/Goerli/GoerliGCC.sol";
// import {MockUSDC} from "@/testing/MockUSDC.sol";
// import {EarlyLiquidity} from "@/EarlyLiquidity.sol";
// import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
// import {CarbonCreditDutchAuction} from "@/CarbonCreditDutchAuction.sol";
// import {GoerliMinerPoolAndGCAQuickPeriod} from "@/testing/Goerli/GoerliMinerPoolAndGCA.QuickPeriod.sol";
// import {VetoCouncil} from "@/VetoCouncil.sol";
// import {HoldingContract} from "@/HoldingContract.sol";
// import {GrantsTreasury} from "@/GrantsTreasury.sol";
// import {BatchCommit} from "@/BatchCommit.sol";
import {MinerPoolAndGCA} from "@/MinerPoolAndGCA/MinerPoolAndGCA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Governance} from "@/Governance.sol";
import {SafetyDelay} from "@/SafetyDelay.sol";
import "forge-std/Test.sol";

contract Debug2 is Test {
    string mainnetForkUrl = vm.envString("MAINNET_RPC");
    uint256 mainnetFork;
    address gca = 0x63a74612274FbC6ca3f7096586aF01Fd986d69cE;
    address farm = 0xD8E3164744916b8c0D1d6cc01ad82F76ec94058e;
    MinerPoolAndGCA minerPoolAndGCA = MinerPoolAndGCA(0x6Fa8C7a89b22bf3212392b778905B12f3dBAF5C4);
    SafetyDelay safetyDelay = SafetyDelay(0xd5970622b740a2eA5A5574616c193968b10e1297);
    address usdg = 0xe010ec500720bE9EF3F82129E7eD2Ee1FB7955F2;
    IERC20 glow = IERC20(0xf4fbC617A5733EAAF9af08E1Ab816B103388d8B6);
    Governance gov = Governance(0x8d01a258bC1ADB728322499E5D84173EA971d665);

    function setUp() public {
        mainnetFork = vm.createFork(mainnetForkUrl);
        vm.selectFork(mainnetFork);
    }

    function test_debug_gov() public {
        gov.syncProposals();
    }
}

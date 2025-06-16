// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.17;

// import "forge-std/Script.sol";
// import "forge-std/console.sol";
// import {GCC} from "@glow/GCC.sol";
// import {TestGLOW} from "@glow/testing/TestGLOW.sol";
// import {Governance} from "@glow/Governance.sol";
// import {GoerliGCC} from "@glow/testing/Goerli/GoerliGCC.sol";
// import {MockUSDC} from "@glow/testing/MockUSDC.sol";
// import {IUniswapRouterV2} from "@glow/interfaces/IUniswapRouterV2.sol";

// //Carbon Credit Auction and Impact Catalyst Are Both Deployed By GCC
// contract DeployGCC is Script {
//     address gcaAndMinerPool = address(0xffff);
//     address earlyLiquidityAddress = address(0x14444);
//     address vestingContract = address(0x15555);
//     address vetoCouncil = address(0x16666);
//     address grantsTreasury = address(0x17777);
//     address rewardAddress = address(0x18888);
//     MockUSDC mockUSDC;
//     address uniswapV2Router = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

//     function run() external {
//         vm.startBroadcast();
//         mockUSDC = new MockUSDC();
//         mockUSDC.mint(tx.origin, 1000000 * 1e6);
//         Governance governance = new Governance();
//         TestGLOW glow = new TestGLOW(gcaAndMinerPool, vestingContract);
//         glow.mint(tx.origin, 100 ether);
//         GoerliGCC gcc =
//             new GoerliGCC(gcaAndMinerPool, address(governance), address(glow), address(mockUSDC), uniswapV2Router);
//         gcc.mint(tx.origin, 1000 ether);
//         gcc.approve(uniswapV2Router, 100 ether);
//         mockUSDC.approve(uniswapV2Router, 20000 * 1e6);
//         IUniswapRouterV2(uniswapV2Router).addLiquidity(
//             address(gcc), address(mockUSDC), 100 ether, 2000 * 1e6, 0, 0, tx.origin, block.timestamp + 1 days
//         );
//         governance.setContractAddresses(address(gcc), gcaAndMinerPool, vetoCouncil, grantsTreasury, address(glow));
//         gcc.commitGCC(5 ether, tx.origin, 0);
//         uint256 nextNominationCost = governance.costForNewProposal();
//         governance.createChangeGCARequirementsProposal(keccak256("new requiremenents hash"), nextNominationCost);
//         nextNominationCost = governance.costForNewProposal();
//         governance.createVetoCouncilElectionOrSlash(address(0x444), address(0x123), true, nextNominationCost);
//         vm.stopBroadcast();
//     }
// }

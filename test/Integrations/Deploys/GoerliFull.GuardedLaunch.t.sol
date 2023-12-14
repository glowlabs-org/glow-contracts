// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.17;

// import "forge-std/Script.sol";
// import "forge-std/console.sol";
// import {GoerliGlowGuardedLaunch} from "@/testing/GuardedLaunch/GoerliGLOW.GuardedLaunch.sol";
// import {Governance} from "@/Governance.sol";
// import {GoerliGCCGuardedLaunch} from "@/testing/GuardedLaunch/GoerliGCC.GuardedLaunch.sol";
// import {MockUSDC} from "@/testing/MockUSDC.sol";
// import {EarlyLiquidity} from "@/EarlyLiquidity.sol";
// import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
// import {CarbonCreditDutchAuction} from "@/CarbonCreditDutchAuction.sol";
// import {MinerPoolAndGCA} from "@/MinerPoolAndGCA/MinerPoolAndGCA.sol";
// import {VetoCouncil} from "@/VetoCouncil.sol";
// import {HoldingContract} from "@/HoldingContract.sol";
// import {GrantsTreasury} from "@/GrantsTreasury.sol";
// import {BatchCommit} from "@/BatchCommit.sol";
// import "forge-std/Test.sol";
// import {USDG} from "@/USDG.sol";

// string constant fileToWriteTo = "deployedContractsGoerli.json";

// contract DeployFullGoerliGuarded is Test, Script {
//     bytes32 gcaRequirementsHash = keccak256("my hash good ser");
//     address vestingContract = address(0xE414D49268837291fde21c33AD7e30233b7041C2);

//     MockUSDC mockUSDC;
//     EarlyLiquidity earlyLiquidity;
//     MinerPoolAndGCA gcaAndMinerPoolContract;
//     VetoCouncil vetoCouncilContract;
//     HoldingContract holdingContract;
//     GrantsTreasury treasury;
//     USDG usdg;
//     address uniswapV2Router = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
//     address uniswapV2Factory = address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
//     address me = address(0x412412412421431);

//     address usdgOwner = me;
//     address usdcReceiver = address(0xfdafafdafafa124412f);
//     string forkUrl = vm.envString("GOERLI_RPC_URL");
//     uint256 goerliFork;

//     address deployer = tx.origin;

//     function setUp() public {
//         goerliFork = vm.createFork(forkUrl);
//     }

//     function test_guarded_deployRun() external {
//         vm.selectFork(goerliFork);
//         vm.startPrank(me);
//         address[] memory startingAgents = new address[](1);
//         startingAgents[0] = me;
//         address[] memory startingVetoCouncilAgents = new address[](1);
//         startingVetoCouncilAgents[0] = me;
//         mockUSDC = new MockUSDC();
//         usdg = new USDG({
//             _usdc: address(mockUSDC),
//             _usdcReceiver: usdcReceiver,
//             _owner: usdgOwner,
//             _univ2Factory: uniswapV2Factory
//         });

//         mockUSDC.mint(me, 1000000 * 1e6);
//         mockUSDC.approve(address(usdg), 1000000 * 1e6);
//         usdg.swap(me, 1000000 * 1e6);
//         console.log("my balance of usdg = ", usdg.balanceOf(me));

//         earlyLiquidity = new EarlyLiquidity(address(usdg), address(holdingContract));
//         Governance governance = new Governance();

//         GoerliGlowGuardedLaunch glow = new GoerliGlowGuardedLaunch({
//             _earlyLiquidityAddress: address(earlyLiquidity),
//             _vestingContract: vestingContract,
//             _owner: me,
//             _usdg: address(usdg),
//             _uniswapV2Factory: uniswapV2Factory
//         });

//         vetoCouncilContract = new VetoCouncil(address(glow), address(glow), startingVetoCouncilAgents);
//         holdingContract = new HoldingContract(address(vetoCouncilContract));
//         treasury = new GrantsTreasury(address(glow), address(governance));
//         gcaAndMinerPoolContract = new MinerPoolAndGCA(
//             startingAgents,
//             address(glow),
//             address(governance),
//             gcaRequirementsHash,
//             address(earlyLiquidity),
//             address(usdg),
//             address(vetoCouncilContract),
//             address(holdingContract)
//         );
//         glow.mint(me, 100 ether);
//         GoerliGCCGuardedLaunch gcc = new GoerliGCCGuardedLaunch({
//             _gcaAndMinerPoolContract: address(gcaAndMinerPoolContract),
//             _governance: address(governance),
//             _glowToken: address(glow),
//             _usdg: address(usdg),
//             _vetoCouncilAddress: address(vetoCouncilContract),
//             _uniswapRouter: uniswapV2Router,
//             _uniswapFactory: uniswapV2Factory
//         });
//         gcc.allowlistPostConstructionContracts();
//         gcaAndMinerPoolContract.setGCC(address(gcc));

//         //TODO: set these addresses
//         // glow.setContractAddresses(address(gcaAndMinerPoolContract), address(vetoCouncilContract), address(treasury));
//         // usdg.setAllowlistedContracts({
//         //     _glow: address(glow),
//         //     _gcc: address(gcc),
//         //     _holdingContract: address(holdingContract),
//         //     _vetoCouncilContract: address(vetoCouncilContract),
//         //     _impactCatalyst: address(gcc.IMPACT_CATALYST())
//         // });
//         BatchCommit batchCommit = new BatchCommit(address(gcc), address(usdg));
//         gcc.mint(me, 1000 ether);
//         gcc.approve(uniswapV2Router, 100 ether);
//         usdg.approve(uniswapV2Router, 20000 * 1e6);
//         console.log("my balance of usdg = ", usdg.balanceOf(me));
//         console.log("usdg approval of uni router = ", usdg.allowance(me, uniswapV2Router));
//         IUniswapRouterV2(uniswapV2Router).addLiquidity(
//             address(gcc), address(usdg), 100 ether, 2000 * 1e6, 0, 0, me, block.timestamp + 1 days
//         );
//         governance.setContractAddresses(
//             address(gcc),
//             address(gcaAndMinerPoolContract),
//             address(vetoCouncilContract),
//             address(treasury),
//             address(glow)
//         );

//         gcc.approve(me, 100 ether);
//         gcc.commitGCC(5 ether, me, 0);
//         uint256 nextNominationCost = governance.costForNewProposal();
//         governance.createChangeGCARequirementsProposal(keccak256("new requiremenents hash"), nextNominationCost);
//         nextNominationCost = governance.costForNewProposal();
//         governance.createVetoCouncilElectionOrSlash(address(0x444), address(0x123), true, nextNominationCost);
//         vm.stopPrank();
//     }
// }

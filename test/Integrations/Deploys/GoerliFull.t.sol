// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";
import {GCC} from "@/GCC.sol";
import {TestGLOW} from "@/testing/TestGLOW.sol";
import {Governance} from "@/Governance.sol";
import {GoerliGCC} from "@/testing/GoerliGCC.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";
import {EarlyLiquidity} from "@/EarlyLiquidity.sol";
import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
import {CarbonCreditDutchAuction} from "@/CarbonCreditDutchAuction.sol";
import {MinerPoolAndGCA} from "@/MinerPoolAndGCA/MinerPoolAndGCA.sol";
import {VetoCouncil} from "@/VetoCouncil.sol";
import {HoldingContract} from "@/HoldingContract.sol";
import {GrantsTreasury} from "@/GrantsTreasury.sol";

contract GoerliFullDeploy is Test {
    address rewardAddress = address(0x18888);
    bytes32 gcaRequirementsHash = keccak256("my hash good ser");
    address vestingContract = tx.origin;
    string forkUrl = vm.envString("GOERLI_RPC_URL");
    uint256 mainnetFork;

    MockUSDC mockUSDC;
    EarlyLiquidity earlyLiquidity;
    MinerPoolAndGCA gcaAndMinerPoolContract;
    VetoCouncil vetoCouncilContract;
    HoldingContract holdingContract;
    GrantsTreasury treasury;
    address uniswapV2Router = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    function setUp() public {
        mainnetFork = vm.createFork(forkUrl);
    }

    function test_deploy() external {
        vm.selectFork(mainnetFork);
        address[] memory startingAgents = new address[](1);
        startingAgents[0] = tx.origin;
        address[] memory startingVetoCouncilAgents = new address[](1);
        startingVetoCouncilAgents[0] = tx.origin;

        mockUSDC = new MockUSDC();
        mockUSDC.mint(tx.origin, 1000000 * 1e6);
        earlyLiquidity = new EarlyLiquidity(address(mockUSDC),address(holdingContract));
        vm.startBroadcast();
        Governance governance = new Governance();

        TestGLOW glow = new TestGLOW(address(earlyLiquidity), vestingContract);
        vetoCouncilContract = new VetoCouncil(address(glow), address(glow), startingVetoCouncilAgents);
        holdingContract = new HoldingContract(address(vetoCouncilContract));
        treasury = new GrantsTreasury(address(glow),address(governance));
        gcaAndMinerPoolContract = new MinerPoolAndGCA(
            startingAgents, 
            address(glow), 
            address(governance), 
            gcaRequirementsHash,
            address(earlyLiquidity),
            address(mockUSDC),
            address(vetoCouncilContract),
            address(holdingContract));

        glow.setContractAddresses(address(gcaAndMinerPoolContract), address(vetoCouncilContract), address(treasury));
        glow.mint(tx.origin, 100 ether);
        GoerliGCC gcc = new GoerliGCC(address(gcaAndMinerPoolContract), address(governance), address(glow),
            address(mockUSDC), uniswapV2Router);
        gcc.mint(tx.origin, 1000 ether);
        gcc.approve(uniswapV2Router, 100 ether);
        mockUSDC.approve(uniswapV2Router, 20000 * 1e6);
        IUniswapRouterV2(uniswapV2Router).addLiquidity(
            address(gcc), address(mockUSDC), 100 ether, 2000 * 1e6, 0, 0, tx.origin, block.timestamp + 1 days
        );
        governance.setContractAddresses(
            address(gcc),
            address(gcaAndMinerPoolContract),
            address(vetoCouncilContract),
            address(treasury),
            address(glow)
        );
        gcc.commitGCC(5 ether, tx.origin, 0);
        uint256 nextNominationCost = governance.costForNewProposal();
        governance.createChangeGCARequirementsProposal(keccak256("new requiremenents hash"), nextNominationCost);
        nextNominationCost = governance.costForNewProposal();
        governance.createVetoCouncilElectionOrSlash(address(0x444), address(0x123), true, nextNominationCost);
        vm.stopBroadcast();
    }
}

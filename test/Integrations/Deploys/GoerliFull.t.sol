// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";
import {GCC} from "@glow/GCC.sol";
import {TestGLOW} from "@glow/testing/TestGLOW.sol";
import {Governance} from "@glow/Governance.sol";
import {GoerliGCC} from "@glow/testing/Goerli/GoerliGCC.sol";
import {MockUSDC} from "@glow/testing/MockUSDC.sol";
import {EarlyLiquidity} from "@glow/EarlyLiquidity.sol";
import {IUniswapRouterV2} from "@glow/interfaces/IUniswapRouterV2.sol";
import {MinerPoolAndGCA} from "@glow/MinerPoolAndGCA/MinerPoolAndGCA.sol";
import {VetoCouncil} from "@glow/VetoCouncil/VetoCouncil.sol";
import {SafetyDelay} from "@glow/SafetyDelay.sol";
import {GrantsTreasury} from "@glow/GrantsTreasury.sol";

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
    SafetyDelay holdingContract;
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
        vm.startBroadcast();
        address deployer = tx.origin;
        uint256 deployerNonce = vm.getNonce(deployer);
        address precomputedGlow = computeCreateAddress(deployer, deployerNonce + 1);
        address precomputedHoldingContract = computeCreateAddress(deployer, deployerNonce + 5);
        address precomputedMinerPool = computeCreateAddress(deployer, deployerNonce + 6);

        earlyLiquidity = new EarlyLiquidity(
            address(mockUSDC), address(precomputedHoldingContract), precomputedGlow, precomputedMinerPool
        ); //deployerNonce

        address precomputedVetoCouncil = computeCreateAddress(deployer, deployerNonce + 3);
        address precomputedTreasury = computeCreateAddress(deployer, deployerNonce + 4);
        address precomputedGCC = computeCreateAddress(deployer, deployerNonce + 7);
        TestGLOW glow = new TestGLOW(
            address(earlyLiquidity), vestingContract, precomputedMinerPool, precomputedVetoCouncil, precomputedTreasury
        ); //deployerNonce + 1
        Governance governance = new Governance({
            gcc: precomputedGCC,
            gca: precomputedMinerPool,
            vetoCouncil: precomputedVetoCouncil,
            grantsTreasury: precomputedTreasury,
            glw: address(glow)
        }); //deployerNonce + 2

        vetoCouncilContract = new VetoCouncil(address(glow), address(glow), startingAgents); //deployerNonce + 3
        treasury = new GrantsTreasury(address(glow), address(governance)); //deployerNonce + 4
        holdingContract = new SafetyDelay(address(vetoCouncilContract), precomputedMinerPool); //deployerNonce + 5
        gcaAndMinerPoolContract = new MinerPoolAndGCA( //deployerNonce + 6
            startingAgents,
            address(glow),
            address(governance),
            gcaRequirementsHash,
            address(earlyLiquidity),
            address(mockUSDC),
            address(vetoCouncilContract),
            address(holdingContract),
            precomputedGCC
        );
        GoerliGCC gcc = new GoerliGCC(
            address(gcaAndMinerPoolContract), address(governance), address(glow), address(mockUSDC), uniswapV2Router
        ); //deployerNonce + 7
        glow.mint(tx.origin, 100 ether);
        gcc.mint(tx.origin, 1000 ether);
        gcc.approve(uniswapV2Router, 100 ether);
        mockUSDC.approve(uniswapV2Router, 20000 * 1e6);
        IUniswapRouterV2(uniswapV2Router).addLiquidity(
            address(gcc), address(mockUSDC), 100 ether, 2000 * 1e6, 0, 0, tx.origin, block.timestamp + 1 days
        );
        // governance.setContractAddresses(
        //     address(gcc),
        //     address(gcaAndMinerPoolContract),
        //     address(vetoCouncilContract),
        //     address(treasury),
        //     address(glow)
        // );
        gcc.commitGCC(5 ether, tx.origin, 0);
        uint256 nextNominationCost = governance.costForNewProposal();
        governance.createChangeGCARequirementsProposal(keccak256("new requiremenents hash"), nextNominationCost);
        nextNominationCost = governance.costForNewProposal();
        governance.createVetoCouncilElectionOrSlash(address(0x444), address(0x123), true, nextNominationCost);
        vm.stopBroadcast();
    }
}

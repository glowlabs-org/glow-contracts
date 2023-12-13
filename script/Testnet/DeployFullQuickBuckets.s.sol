// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {GCC} from "@/GCC.sol";
import {TestGLOW} from "@/testing/TestGLOW.sol";
import {GoerliGovernanceQuickPeriod} from "@/testing/Goerli/GoerliGovernance.QuickPeriod.sol";
import {GoerliGCC} from "@/testing/Goerli/GoerliGCC.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";
import {EarlyLiquidity} from "@/EarlyLiquidity.sol";
import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
import {CarbonCreditDutchAuction} from "@/CarbonCreditDutchAuction.sol";
import {GoerliMinerPoolAndGCAQuickPeriod} from "@/testing/Goerli/GoerliMinerPoolAndGCA.QuickPeriod.sol";
import {VetoCouncil} from "@/VetoCouncil.sol";
import {HoldingContract} from "@/HoldingContract.sol";
import {GrantsTreasury} from "@/GrantsTreasury.sol";
import {BatchCommit} from "@/BatchCommit.sol";
import "forge-std/Test.sol";

string constant fileToWriteTo = "deployedContractsGoerli.json";

contract DeployFullQuickBuckets is Test, Script {
    bytes32 gcaRequirementsHash = keccak256("my hash good ser");
    address vestingContract = address(0xE414D49268837291fde21c33AD7e30233b7041C2);

    address testingOther = 0x1c42C3DC7502aE55Ec4a888a940b2ADB0901a604;
    MockUSDC mockUSDC;
    EarlyLiquidity earlyLiquidity;
    GoerliMinerPoolAndGCAQuickPeriod gcaAndMinerPoolContract;
    VetoCouncil vetoCouncilContract;
    HoldingContract holdingContract;
    GrantsTreasury treasury;
    address uniswapV2Router = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    function run() external {
        address[] memory startingAgents = new address[](2);
        startingAgents[0] = tx.origin;
        startingAgents[1] = testingOther;
        address[] memory startingVetoCouncilAgents = new address[](2);
        startingVetoCouncilAgents[0] = tx.origin;
        startingVetoCouncilAgents[1] = testingOther;
        if (vm.exists(fileToWriteTo)) {
            vm.removeFile(fileToWriteTo);
        }

        vm.startBroadcast();
        mockUSDC = new MockUSDC();
        mockUSDC.mint(tx.origin, 1000000 * 1e6);
        earlyLiquidity = new EarlyLiquidity(address(mockUSDC),address(holdingContract));
        GoerliGovernanceQuickPeriod governance = new GoerliGovernanceQuickPeriod();

        TestGLOW glow = new TestGLOW(address(earlyLiquidity), vestingContract);
        vetoCouncilContract = new VetoCouncil(address(glow), address(glow), startingVetoCouncilAgents);
        holdingContract = new HoldingContract(address(vetoCouncilContract));
        treasury = new GrantsTreasury(address(glow),address(governance));
        gcaAndMinerPoolContract = new GoerliMinerPoolAndGCAQuickPeriod(
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
        BatchCommit batchCommit = new BatchCommit(address(gcc), address(mockUSDC));
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
        gcaAndMinerPoolContract.setGCC(address(gcc));
        glow.mint(address(gcaAndMinerPoolContract), 100_000_000_000 ether); //mint so there's enough for rewards without inflation
        gcc.approve(tx.origin, 100 ether);
        gcc.commitGCC(5 ether, tx.origin, 0);
        uint256 nextNominationCost = governance.costForNewProposal();
        governance.createChangeGCARequirementsProposal(keccak256("new requiremenents hash"), nextNominationCost);
        nextNominationCost = governance.costForNewProposal();
        governance.createVetoCouncilElectionOrSlash(address(0x444), address(0x123), true, nextNominationCost);
        vm.stopBroadcast();
        string memory jsonStringOutput = string("{");
        jsonStringOutput = string(
            abi.encodePacked(
                jsonStringOutput, "\"earlyLiquidity\":", "\"", vm.toString(address(earlyLiquidity)), "\"", ","
            )
        );
        jsonStringOutput = string(
            abi.encodePacked(jsonStringOutput, "\"governance\":", "\"", vm.toString(address(governance)), "\"", ",")
        );
        jsonStringOutput =
            string(abi.encodePacked(jsonStringOutput, "\"glow\":", "\"", vm.toString(address(glow)), "\"", ","));
        jsonStringOutput = string(
            abi.encodePacked(
                jsonStringOutput, "\"vetoCouncilContract\":", "\"", vm.toString(address(vetoCouncilContract)), "\"", ","
            )
        );
        jsonStringOutput = string(
            abi.encodePacked(
                jsonStringOutput, "\"holdingContract\":", "\"", vm.toString(address(holdingContract)), "\"", ","
            )
        );
        jsonStringOutput = string(
            abi.encodePacked(jsonStringOutput, "\"grantsTreasury\":", "\"", vm.toString(address(treasury)), "\"", ",")
        );
        jsonStringOutput = string(
            abi.encodePacked(
                jsonStringOutput,
                "\"gcaAndMinerPoolContract\":",
                "\"",
                vm.toString(address(gcaAndMinerPoolContract)),
                "\"",
                ","
            )
        );
        jsonStringOutput =
            string(abi.encodePacked(jsonStringOutput, "\"gcc\":", "\"", vm.toString(address(gcc)), "\"", ","));
        jsonStringOutput = string(
            abi.encodePacked(jsonStringOutput, "\"batchCommit\":", "\"", vm.toString(address(batchCommit)), "\"", ",")
        );
        jsonStringOutput =
            string(abi.encodePacked(jsonStringOutput, "\"usdc\":", "\"", vm.toString(address(mockUSDC)), "\"", ","));
        jsonStringOutput = string(
            abi.encodePacked(
                jsonStringOutput, "\"impactCatalyst\":", "\"", vm.toString(address(gcc.IMPACT_CATALYST())), "\"", ","
            )
        );
        jsonStringOutput = string(
            abi.encodePacked(
                jsonStringOutput,
                "\"carbonCreditAuction\":",
                "\"",
                vm.toString(address(gcc.CARBON_CREDIT_AUCTION())),
                "\""
            )
        );

        jsonStringOutput = string(abi.encodePacked(jsonStringOutput, "}"));

        vm.writeFile(fileToWriteTo, jsonStringOutput);
    }
}
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
import {GoerliMinerPoolAndGCAQuickPeriod} from "@/testing/Goerli/GoerliMinerPoolAndGCA.QuickPeriod.sol";
import {VetoCouncil} from "@/VetoCouncil/VetoCouncil.sol";
import {SafetyDelay} from "@/SafetyDelay.sol";
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
    SafetyDelay holdingContract;
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
        address deployer = tx.origin;

        uint256 deployerNonce = vm.getNonce(deployer);
        address precomputedMinerPool = computeCreateAddress(deployer, deployerNonce + 7);
        address precomputedGlow = computeCreateAddress(deployer, deployerNonce + 1);
        address precomputedEarlyLiquidity = computeCreateAddress(deployer, deployerNonce + 2);
        address precomputedGovernance = computeCreateAddress(deployer, deployerNonce + 3);
        address precomputedVetoCouncil = computeCreateAddress(deployer, deployerNonce + 4);
        address precomputedGrants = computeCreateAddress(deployer, deployerNonce + 6);
        address precomputedHoldingContract = computeCreateAddress(deployer, deployerNonce + 5);

        // address precomputedMinerPool = 0x1D4810c63e01E647b6B1d11BaC7ff6d739fe0D2c;
        // address precomputedGlow = 0x55A4D4e12247C804b1925A5Cd6359786Af625C8F;
        // address precomputedEarlyLiquidity = 0x9DC680EB586d40000bAEe0626bFC57093f37FFE9;
        // address precomputedGovernance = 0x2cBef5699b5998C517Def581dF0dc78Cd415A2F1;
        // address precomputedVetoCouncil = 0x4e8E51e4D6725e00CbcB5706440D642F5FAFd6b3;
        // address precomputedGrants = 0x2b753380b974aa05f301f25D6EDF186E72712F5A;
        // address precomputedHoldingContract = 0x9ADE8d3D98fD6E813E8fd4B179c3073Ae5788192;

        GoerliGCC gcc = new GoerliGCC({
            _gcaAndMinerPoolContract: precomputedMinerPool,
            _governance: precomputedGovernance,
            _glow: precomputedGlow,
            _usdc: address(mockUSDC),
            _uniswapV2Router: uniswapV2Router
        }); //deployerNonce

        TestGLOW glow = new TestGLOW({
            _earlyLiquidityAddress: precomputedEarlyLiquidity,
            _vestingContract: vestingContract,
            _gcaAndMinerPoolAddress: precomputedMinerPool,
            _vetoCouncilAddress: precomputedVetoCouncil,
            _grantsTreasuryAddress: precomputedGrants
        }); //deployerNonce + 1

        earlyLiquidity = new EarlyLiquidity({
            _usdcAddress: address(mockUSDC),
            _holdingContract: precomputedHoldingContract,
            _glowToken: address(glow),
            _minerPoolAddress: precomputedMinerPool
        }); //deployerNonce + 2

        GoerliGovernanceQuickPeriod governance = new GoerliGovernanceQuickPeriod({
            gcc: address(gcc),
            gca: precomputedMinerPool,
            vetoCouncil: precomputedVetoCouncil,
            grantsTreasury: precomputedGrants,
            glw: address(glow)
        }); //deployerNonce + 3

        vetoCouncilContract = new VetoCouncil(address(glow), address(glow), startingVetoCouncilAgents); //deployerNonce + 4

        holdingContract = new SafetyDelay(address(vetoCouncilContract), precomputedMinerPool); //deployerNonce + 5

        treasury = new GrantsTreasury(address(glow), address(governance)); //deployerNonce + 6
        gcaAndMinerPoolContract = new GoerliMinerPoolAndGCAQuickPeriod(
            startingAgents,
            address(glow),
            address(governance),
            gcaRequirementsHash,
            address(earlyLiquidity),
            address(mockUSDC),
            address(vetoCouncilContract),
            address(holdingContract),
            address(gcc)
        ); //deployerNonce + 7

        //assert all the precomputed addresses are correct
        assertEq(precomputedMinerPool, address(gcaAndMinerPoolContract), "MinerPool address is incorrect");
        assertEq(precomputedGlow, address(glow), "GLOW address is incorrect");
        assertEq(precomputedEarlyLiquidity, address(earlyLiquidity), "EarlyLiquidity address is incorrect");
        assertEq(precomputedGovernance, address(governance), "Governance address is incorrect");
        assertEq(precomputedVetoCouncil, address(vetoCouncilContract), "VetoCouncil address is incorrect");
        assertEq(precomputedGrants, address(treasury), "GrantsTreasury address is incorrect");
        assertEq(precomputedHoldingContract, address(holdingContract), "HoldingContract address is incorrect");

        //TODO: set these addresses
        // glow.setContractAddresses(address(gcaAndMinerPoolContract), address(vetoCouncilContract), address(treasury));
        glow.mint(tx.origin, 100 ether);

        BatchCommit batchCommit = new BatchCommit(address(gcc), address(mockUSDC));
        gcc.mint(tx.origin, 1000 ether);
        gcc.approve(uniswapV2Router, 100 ether);
        mockUSDC.approve(uniswapV2Router, 20000 * 1e6);
        IUniswapRouterV2(uniswapV2Router).addLiquidity(
            address(gcc), address(mockUSDC), 100 ether, 2000 * 1e6, 0, 0, tx.origin, block.timestamp + 1 days
        );

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

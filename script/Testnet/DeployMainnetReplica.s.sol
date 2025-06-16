// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {Governance} from "@/Governance.sol";
import {GlowGuardedLaunch} from "@/GuardedLaunch/Glow.GuardedLaunch.sol";
import {GCCGuardedLaunch} from "@/GuardedLaunch/GCC.GuardedLaunch.sol";
import {EarlyLiquidity} from "@/EarlyLiquidity.sol";
import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
import {MinerPoolAndGCA} from "@/MinerPoolAndGCA/MinerPoolAndGCA.sol";
import {VetoCouncil} from "@/VetoCouncil/VetoCouncil.sol";
import {SafetyDelay} from "@/SafetyDelay.sol";
import {GrantsTreasury} from "@/GrantsTreasury.sol";
import {BatchCommit} from "@/BatchCommit.sol";
import "forge-std/Test.sol";
import {USDG} from "@/USDG.sol";

string constant fileToWriteTo = "deployedContracts-replica.json";

contract DeployGoerliFullReplicaGuardedLaunch is Test, Script {
    bytes32 gcaRequirementsHash = keccak256("GCA Beta Hash");
    address vestingContract = address(0xE414D49268837291fde21c33AD7e30233b7041C2);

    EarlyLiquidity earlyLiquidity;
    MinerPoolAndGCA gcaAndMinerPoolContract;
    VetoCouncil vetoCouncilContract;
    SafetyDelay holdingContract;
    GrantsTreasury treasury;
    USDG usdg;
    address usdc = 0xd35CCeEAD182dcee0F148EbaC9447DA2c4D449c4; // different on mainnet
    address uniswapV2Router = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address uniswapV2Factory = address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    address usdcReceiver = address(0xc5174BBf649a92F9941e981af68AaA14Dd814F85); //2/3 Multisig Gnosis Safe on Mainnet

    function run() external {
        address[] memory startingAgents = new address[](1);
        startingAgents[0] = tx.origin;
        address[] memory startingVetoCouncilAgents = new address[](3);
        startingVetoCouncilAgents[0] = 0x28009e8a27Aa1836d6B4a2E005D35201Aa5269ea; //veto1
        startingVetoCouncilAgents[1] = 0xD70823246D53EE41875B353Df2c7915608279de1; //veto2
        startingVetoCouncilAgents[2] = 0x93ECA9F2dffc5f7Ab3830D413c43E7dbFF681867; //veto3
        startingVetoCouncilAgents[0] = tx.origin;
        if (vm.exists(fileToWriteTo)) {
            vm.removeFile(fileToWriteTo);
        }

        vm.startBroadcast();

        address deployer = tx.origin;
        uint256 deployerNonce = vm.getNonce(deployer);
        address precomputedGlow = computeCreateAddress(deployer, deployerNonce + 1);
        address precomputedUSDG = computeCreateAddress(deployer, deployerNonce + 2);
        address precomputedEarlyLiquidity = computeCreateAddress(deployer, deployerNonce + 3);
        address precomputedGovernance = computeCreateAddress(deployer, deployerNonce + 4);
        address precomputedVetoCouncil = computeCreateAddress(deployer, deployerNonce + 5);
        address precomputedHoldingContract = computeCreateAddress(deployer, deployerNonce + 6);
        address precomputedTreasury = computeCreateAddress(deployer, deployerNonce + 7);
        address precomputedGCAAndMinerPoolContract = computeCreateAddress(deployer, deployerNonce + 8);

        GCCGuardedLaunch gcc = new GCCGuardedLaunch({
            _gcaAndMinerPoolContract: address(precomputedGCAAndMinerPoolContract),
            _governance: address(precomputedGovernance),
            _glowToken: address(precomputedGlow),
            _usdg: address(precomputedUSDG),
            _vetoCouncilAddress: address(precomputedVetoCouncil),
            _uniswapRouter: uniswapV2Router,
            _uniswapFactory: uniswapV2Factory
        }); //deployerNonce

        GlowGuardedLaunch glow = new GlowGuardedLaunch({
            _earlyLiquidityAddress: address(precomputedEarlyLiquidity),
            _vestingContract: vestingContract,
            _gcaAndMinerPoolAddress: address(precomputedGCAAndMinerPoolContract),
            _vetoCouncilAddress: address(precomputedVetoCouncil),
            _grantsTreasuryAddress: address(precomputedTreasury),
            _owner: tx.origin,
            _usdg: address(precomputedUSDG),
            _uniswapV2Factory: uniswapV2Factory,
            _gccContract: address(gcc)
        }); //deployerNonce + 1

        usdg = new USDG({
            _usdc: address(usdc),
            _usdcReceiver: usdcReceiver,
            _owner: deployer,
            _univ2Factory: uniswapV2Factory,
            _glow: address(glow),
            _gcc: address(gcc),
            _holdingContract: address(precomputedHoldingContract),
            _vetoCouncilContract: address(precomputedVetoCouncil),
            _impactCatalyst: address(gcc.IMPACT_CATALYST())
        }); //deployerNonce + 2

        earlyLiquidity = new EarlyLiquidity({
            _usdcAddress: address(usdg),
            _holdingContract: address(precomputedHoldingContract),
            _glowToken: address(glow),
            _minerPoolAddress: address(precomputedGCAAndMinerPoolContract)
        }); //deployerNonce + 3
        Governance governance = new Governance({
            gcc: address(gcc),
            gca: address(precomputedGCAAndMinerPoolContract),
            vetoCouncil: address(precomputedVetoCouncil),
            grantsTreasury: address(precomputedTreasury),
            glw: address(glow)
        }); //deployerNonce + 4

        vetoCouncilContract = new VetoCouncil(address(glow), address(glow), startingVetoCouncilAgents); //deployerNonce + 5
        holdingContract = new SafetyDelay(address(vetoCouncilContract), precomputedGCAAndMinerPoolContract); //deployerNonce + 6
        treasury = new GrantsTreasury(address(glow), address(governance)); //deployerNonce + 7
        gcaAndMinerPoolContract = new MinerPoolAndGCA( //deployerNonce + 8
            startingAgents,
            address(glow),
            address(governance),
            gcaRequirementsHash,
            address(earlyLiquidity),
            address(usdg),
            address(vetoCouncilContract),
            address(holdingContract),
            address(gcc)
        );
        gcc.allowlistPostConstructionContracts();

        //make sure precomputes are equal to original
        assertEq(precomputedGlow, address(glow), "precomputed glow address is not equal to glow address");
        assertEq(precomputedUSDG, address(usdg), "precomputed usdg address is not equal to usdg address");
        assertEq(
            precomputedEarlyLiquidity,
            address(earlyLiquidity),
            "precomputed early liquidity address is not equal to early liquidity address"
        );
        assertEq(
            precomputedGovernance,
            address(governance),
            "precomputed governance address is not equal to governance address"
        );
        assertEq(
            precomputedVetoCouncil,
            address(vetoCouncilContract),
            "precomputed veto council address is not equal to veto council address"
        );
        assertEq(
            precomputedHoldingContract,
            address(holdingContract),
            "precomputed holding contract address is not equal to holding contract address"
        );
        assertEq(
            precomputedTreasury, address(treasury), "precomputed treasury address is not equal to treasury address"
        );
        assertEq(
            precomputedGCAAndMinerPoolContract,
            address(gcaAndMinerPoolContract),
            "precomputed gca and miner pool contract address is not equal to gca and miner pool contract address"
        );

        BatchCommit batchCommit = new BatchCommit(address(gcc), address(usdg));

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
            string(abi.encodePacked(jsonStringOutput, "\"usdc\":", "\"", vm.toString(address(usdc)), "\"", ","));
        jsonStringOutput =
            string(abi.encodePacked(jsonStringOutput, "\"usdg\":", "\"", vm.toString(address(usdg)), "\"", ","));
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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {GovernanceGuardedLaunchV2 as Governance} from "@/GuardedLaunchV2/Governance.GuardedLaunchV2.sol";
import {GlowGuardedLaunchV2 as GlowGuardedLaunch} from "@/GuardedLaunchV2/Glow.GuardedLaunchV2.sol";
import {GCCGuardedLaunchV2 as GCCGuardedLaunch} from "@/GuardedLaunchV2/GCC.GuardedLaunchV2.sol";
import {EarlyLiquidityV2 as EarlyLiquidity} from "@/EarlyLiquidityV2.sol";
import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
import {MinerPoolAndGCAGuardedLaunchV2 as MinerPoolAndGCA} from "@/GuardedLaunchV2/MinerPoolAndGCA.GuardedLaunchV2.sol";
import {VetoCouncilGuardedLaunchV2 as VetoCouncil} from "@/GuardedLaunchV2/VetoCouncil.GuardedLaunchV2.sol";
import {SafetyDelay} from "@/SafetyDelay.sol";
import {GrantsTreasury} from "@/GrantsTreasury.sol";
import {BatchCommit} from "@/BatchCommit.sol";
import "forge-std/Test.sol";
import {USDGGuardedLaunchV2 as USDG} from "@/GuardedLaunchV2/USDG.GuardedLaunchV2.sol";
import {MigrationHelper} from "@/MigrationHelper/MigrationHelper.sol";

contract MigrationHelperTest is Test {
    bytes32 gcaRequirementsHash = keccak256("GCA Beta V2 Hash");
    address vestingContract = address(0xdead); // Guarded Launch Does Not Have A Vesting Contract

    EarlyLiquidity earlyLiquidity;
    MinerPoolAndGCA gcaAndMinerPoolContract;
    VetoCouncil vetoCouncilContract;
    SafetyDelay holdingContract;
    GrantsTreasury treasury;
    USDG usdg;
    GlowGuardedLaunch glow;
    GCCGuardedLaunch gcc;
    Governance governance;
    MigrationHelper migrationHelper;
    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address uniswapV2Router = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address uniswapV2Factory = address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    address usdcReceiver = address(0xc5174BBf649a92F9941e981af68AaA14Dd814F85); //2/3 Multisig Gnosis Safe on Mainnet
    uint256 mainnetFork;
    string forkUrl = vm.envString("MAINNET_RPC");

    function setUp() external {
        mainnetFork = vm.createFork(forkUrl);
        vm.selectFork(mainnetFork);
        if (usdcReceiver == tx.origin) {
            revert("set usdcReceiver to not be tx.origin");
        }
        address[] memory startingAgents = new address[](1);
        startingAgents[0] = address(0xB6D80f51943A9F14e584013F3201436E319ED5F2);
        address[] memory startingVetoCouncilAgents = new address[](3);
        startingVetoCouncilAgents[0] = 0x28009e8a27Aa1836d6B4a2E005D35201Aa5269ea; //veto1
        startingVetoCouncilAgents[1] = 0xD70823246D53EE41875B353Df2c7915608279de1; //veto2
        startingVetoCouncilAgents[2] = 0x93ECA9F2dffc5f7Ab3830D413c43E7dbFF681867; //veto3

        address deployer = tx.origin;
        uint256 deployerNonce = vm.getNonce(deployer);
        address precomputedGCC = computeCreateAddress(deployer, deployerNonce + 1);
        address precomputedGlow = computeCreateAddress(deployer, deployerNonce + 2);
        address precomputedUSDG = computeCreateAddress(deployer, deployerNonce + 3);
        address precomputedEarlyLiquidity = computeCreateAddress(deployer, deployerNonce + 4);
        address precomputedGovernance = computeCreateAddress(deployer, deployerNonce + 5);
        address precomputedVetoCouncil = computeCreateAddress(deployer, deployerNonce + 6);
        address precomputedHoldingContract = computeCreateAddress(deployer, deployerNonce + 7);
        address precomputedTreasury = computeCreateAddress(deployer, deployerNonce + 8);
        address precomputedGCAAndMinerPoolContract = computeCreateAddress(deployer, deployerNonce + 9);
        // address precomputedMigrationContract;
        vm.startPrank(deployer);
        migrationHelper = new MigrationHelper({
            _GLOW: precomputedGlow,
            _GCC: precomputedGCC,
            _USDG: precomputedUSDG,
            _GOVERNANCE: precomputedGovernance,
            _MERKLE_ROOT: bytes32(0x1cf819edb3d4adcfe3e281dc230ec792d37abb71e15cd58ccfb0ae2d65f3ca8f)
        });
        gcc = new GCCGuardedLaunch({
            _gcaAndMinerPoolContract: address(precomputedGCAAndMinerPoolContract),
            _governance: address(precomputedGovernance),
            _glowToken: address(precomputedGlow),
            _usdg: address(precomputedUSDG),
            _vetoCouncilAddress: address(precomputedVetoCouncil),
            _uniswapRouter: uniswapV2Router,
            _uniswapFactory: uniswapV2Factory,
            _allowlistedMultisigContracts: new address[](0),
            migrationContract: address(migrationHelper),
            migrationAmount: 1000 ether
        }); //deployerNonce
        address[] memory allowlistedContracts = new address[](0);
        {
            // [migrationContract,amountToSendToMigrationContract,gcaLastClaimTimestamp,vetoCouncilLastClaimedTimestamp,grantsLastClaimedTimestamp]
            bytes memory extraBytes =
                abi.encode(address(migrationHelper), uint256(100000000000 ether), uint256(10), uint256(20), uint256(30));
            glow = new GlowGuardedLaunch({
                _earlyLiquidityAddress: address(precomputedEarlyLiquidity),
                _vestingContract: vestingContract,
                _gcaAndMinerPoolAddress: address(precomputedGCAAndMinerPoolContract),
                _vetoCouncilAddress: address(precomputedVetoCouncil),
                _grantsTreasuryAddress: address(precomputedTreasury),
                _owner: tx.origin,
                _usdg: address(precomputedUSDG),
                _uniswapV2Factory: uniswapV2Factory,
                _gccContract: address(gcc),
                _allowlistedMultisigContracts: allowlistedContracts,
                _extraBytes: extraBytes
            }); //deployerNonce + 1
        }

        {
            bytes memory usdgExtraBytes = abi.encode(address(migrationHelper), uint256(10_000_000 * 1e6));
            usdg = new USDG({
                _usdc: address(usdc),
                _usdcReceiver: usdcReceiver,
                _owner: deployer,
                _univ2Factory: uniswapV2Factory,
                _glow: address(glow),
                _gcc: address(gcc),
                _holdingContract: address(precomputedHoldingContract),
                _vetoCouncilContract: address(precomputedVetoCouncil),
                _impactCatalyst: address(gcc.IMPACT_CATALYST()),
                _allowlistedMultisigContracts: allowlistedContracts,
                _migrationContractAndAmount: usdgExtraBytes
            }); //deployerNonce + 2
        }

        earlyLiquidity = new EarlyLiquidity({
            _usdcAddress: address(usdg),
            _holdingContract: address(precomputedHoldingContract),
            _glowToken: address(glow),
            _minerPoolAddress: address(precomputedGCAAndMinerPoolContract),
            _totalIncrementsSoldInV1: 600000000 //6,000,000 glow
        }); //deployerNonce + 3
        governance = new Governance({
            gcc: address(gcc),
            gca: address(precomputedGCAAndMinerPoolContract),
            vetoCouncil: address(precomputedVetoCouncil),
            grantsTreasury: address(precomputedTreasury),
            glw: address(glow),
            migrationContract: address(migrationHelper)
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

        BatchCommit batchCommit = new BatchCommit(address(gcc), address(usdg));

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

        assertEq(gcc.MIGRATION_CONTRACT(), address(migrationHelper), "migration contract is not set correctly");

        vm.stopPrank();
    }

    function test_claimFromLeaf1() public {
        address claimer = 0x28009e8a27Aa1836d6B4a2E005D35201Aa5269ea;
        address[] memory accounts = new address[](1);
        accounts[0] = claimer;

        uint256[] memory glowAmounts = new uint256[](1);
        uint256[] memory gccAmounts = new uint256[](1);
        uint256[] memory usdgAmounts = new uint256[](1);
        uint256[] memory nominations = new uint256[](1);
        uint256[] memory impactPowers = new uint256[](1);

        glowAmounts[0] = 1000 ether;
        gccAmounts[0] = 1 ether;
        usdgAmounts[0] = 1000 * 1e6;
        nominations[0] = 4 * 1e12;
        impactPowers[0] = 5 * 1e12;

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bytes32(0x53e991434f67de40bdc178b02cb76b7fa1d52cd4f45fd4dbb2bc2f53b7ac470c);
        bool[] memory flags = new bool[](1);
        //Don't need to make false, since by default they are false, but we add for explicitness
        flags[0] = false;

        migrationHelper.claim(accounts, glowAmounts, gccAmounts, usdgAmounts, nominations, impactPowers, proof, flags);
        //Chek the balances
        assertEq(glow.balanceOf(claimer), 1000 ether, "Glow balance is not correct");
        assertEq(gcc.balanceOf(claimer), 1 ether, "GCC balance is not correct");
        assertEq(usdg.balanceOf(claimer), 1000 * 1e6, "USDG balance is not correct");
        assertEq(governance.nominationsOf(claimer), 4 * 1e12, "Nominations balance is not correct");
        assertEq(gcc.totalImpactPowerEarned(claimer), 5 * 1e12, "Impact Power balance is not correct");
    }

    function test_claimFromLeaf2() public {
        address claimer = 0xD70823246D53EE41875B353Df2c7915608279de1;
        address[] memory accounts = new address[](1);
        accounts[0] = claimer;

        uint256[] memory glowAmounts = new uint256[](1);
        uint256[] memory gccAmounts = new uint256[](1);
        uint256[] memory usdgAmounts = new uint256[](1);
        uint256[] memory nominations = new uint256[](1);
        uint256[] memory impactPowers = new uint256[](1);

        glowAmounts[0] = 2000 ether;
        gccAmounts[0] = 2 ether;
        usdgAmounts[0] = 2000 * 1e6;
        nominations[0] = 8 * 1e12;
        impactPowers[0] = 10 * 1e12;

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = bytes32(0x93592111969b65ce82d048a6edf36c559fa69573fccae4d8dc2769ca663f01d0);
        proof[1] = bytes32(0xd61ebbb0b4c3a61e2d5a3fdd6c57cbed1aedfc493b4ffe5ed0b86859044bad6b);
        bool[] memory flags = new bool[](2);
        //Don't need to make false, since by default they are false, but we add for explicitness
        flags[0] = false;
        flags[1] = false;

        migrationHelper.claim(accounts, glowAmounts, gccAmounts, usdgAmounts, nominations, impactPowers, proof, flags);
        assertEq(glow.balanceOf(claimer), 2000 ether, "Glow balance is not correct");
        assertEq(gcc.balanceOf(claimer), 2 ether, "GCC balance is not correct");
        assertEq(usdg.balanceOf(claimer), 2000 * 1e6, "USDG balance is not correct");
        assertEq(governance.nominationsOf(claimer), 8 * 1e12, "Nominations balance is not correct");
        assertEq(gcc.totalImpactPowerEarned(claimer), 10 * 1e12, "Impact Power balance is not correct");
    }

    function test_claimFromLeafTwiceShouldFail() public {
        address claimer = 0xD70823246D53EE41875B353Df2c7915608279de1;
        address[] memory accounts = new address[](1);
        accounts[0] = claimer;

        uint256[] memory glowAmounts = new uint256[](1);
        uint256[] memory gccAmounts = new uint256[](1);
        uint256[] memory usdgAmounts = new uint256[](1);
        uint256[] memory nominations = new uint256[](1);
        uint256[] memory impactPowers = new uint256[](1);

        glowAmounts[0] = 2000 ether;
        gccAmounts[0] = 2 ether;
        usdgAmounts[0] = 2000 * 1e6;
        nominations[0] = 8 * 1e12;
        impactPowers[0] = 10 * 1e12;

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = bytes32(0x93592111969b65ce82d048a6edf36c559fa69573fccae4d8dc2769ca663f01d0);
        proof[1] = bytes32(0xd61ebbb0b4c3a61e2d5a3fdd6c57cbed1aedfc493b4ffe5ed0b86859044bad6b);
        bool[] memory flags = new bool[](2);
        //Don't need to make false, since by default they are false, but we add for explicitness
        flags[0] = false;
        flags[1] = false;

        migrationHelper.claim(accounts, glowAmounts, gccAmounts, usdgAmounts, nominations, impactPowers, proof, flags);
        vm.expectRevert(MigrationHelper.AlreadyMigrated.selector);
        migrationHelper.claim(accounts, glowAmounts, gccAmounts, usdgAmounts, nominations, impactPowers, proof, flags);
    }

    function test_invalidProof_shouldRevert() public {
        address claimer = 0xD70823246D53EE41875B353Df2c7915608279de1;
        address[] memory accounts = new address[](1);
        accounts[0] = claimer;

        uint256[] memory glowAmounts = new uint256[](1);
        uint256[] memory gccAmounts = new uint256[](1);
        uint256[] memory usdgAmounts = new uint256[](1);
        uint256[] memory nominations = new uint256[](1);
        uint256[] memory impactPowers = new uint256[](1);

        glowAmounts[0] = 2000 ether;
        gccAmounts[0] = 2 ether;
        usdgAmounts[0] = 2000 * 1e6;
        nominations[0] = 8 * 1e12;
        impactPowers[0] = 10 * 1e12;

        bytes32[] memory proof = new bytes32[](1);
        //This is the wrong proof
        proof[0] = bytes32(0xd61ebbb0b4c3a61e2d5a3fdd6c57cbed1aedfc493b4ffe5ed0b86859044bad6a);
        bool[] memory flags = new bool[](1);
        flags[0] = false;

        vm.expectRevert(MigrationHelper.InvalidProof.selector);
        migrationHelper.claim(accounts, glowAmounts, gccAmounts, usdgAmounts, nominations, impactPowers, proof, flags);
    }

    function test_claimFromMultipleAddresses() public {
        //First leaf in the tree is 0xD70823246D53EE41875B353Df2c7915608279de1 which is leaf 2

        address claimer1 = 0xD70823246D53EE41875B353Df2c7915608279de1;
        address claimer2 = 0x28009e8a27Aa1836d6B4a2E005D35201Aa5269ea;

        address[] memory accounts = new address[](2);
        accounts[0] = claimer1;
        accounts[1] = claimer2;

        uint256[] memory glowAmounts = new uint256[](2);
        uint256[] memory gccAmounts = new uint256[](2);
        uint256[] memory usdgAmounts = new uint256[](2);
        uint256[] memory nominations = new uint256[](2);
        uint256[] memory impactPowers = new uint256[](2);

        glowAmounts[0] = 2000 ether;
        gccAmounts[0] = 2 ether;
        usdgAmounts[0] = 2000 * 1e6;
        nominations[0] = 8 * 1e12;
        impactPowers[0] = 10 * 1e12;

        glowAmounts[1] = 1000 ether;
        gccAmounts[1] = 1 ether;
        usdgAmounts[1] = 1000 * 1e6;
        nominations[1] = 4 * 1e12;
        impactPowers[1] = 5 * 1e12;

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = 0x93592111969b65ce82d048a6edf36c559fa69573fccae4d8dc2769ca663f01d0;
        bool[] memory flags = new bool[](2);
        flags[0] = false;
        flags[1] = true;

        migrationHelper.claim(accounts, glowAmounts, gccAmounts, usdgAmounts, nominations, impactPowers, proof, flags);

        //Check the balances for both
        assertEq(glow.balanceOf(claimer1), glowAmounts[0], "Glow balance is not correct");
        assertEq(gcc.balanceOf(claimer1), gccAmounts[0], "GCC balance is not correct");
        assertEq(usdg.balanceOf(claimer1), usdgAmounts[0], "USDG balance is not correct");
        assertEq(governance.nominationsOf(claimer1), nominations[0], "Nominations balance is not correct");
        assertEq(gcc.totalImpactPowerEarned(claimer1), impactPowers[0], "Impact Power balance is not correct");

        assertEq(glow.balanceOf(claimer2), glowAmounts[1], "Glow balance is not correct");
        assertEq(gcc.balanceOf(claimer2), gccAmounts[1], "GCC balance is not correct");
        assertEq(usdg.balanceOf(claimer2), usdgAmounts[1], "USDG balance is not correct");
        assertEq(governance.nominationsOf(claimer2), nominations[1], "Nominations balance is not correct");
        assertEq(gcc.totalImpactPowerEarned(claimer2), impactPowers[1], "Impact Power balance is not correct");
    }
}

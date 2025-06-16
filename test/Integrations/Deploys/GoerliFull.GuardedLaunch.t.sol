// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {GoerliGlowGuardedLaunch} from "@glow/testing/GuardedLaunch/GoerliGLOW.GuardedLaunch.sol";
import {Governance} from "@glow/Governance.sol";
import {GoerliGCCGuardedLaunch} from "@glow/testing/GuardedLaunch/GoerliGCC.GuardedLaunch.sol";
import {MockUSDC} from "@glow/testing/MockUSDC.sol";
import {EarlyLiquidity} from "@glow/EarlyLiquidity.sol";
import {IUniswapRouterV2} from "@glow/interfaces/IUniswapRouterV2.sol";
import {MinerPoolAndGCA} from "@glow/MinerPoolAndGCA/MinerPoolAndGCA.sol";
import {VetoCouncil} from "@glow/VetoCouncil/VetoCouncil.sol";
import {SafetyDelay} from "@glow/SafetyDelay.sol";
import {GrantsTreasury} from "@glow/GrantsTreasury.sol";
import {BatchCommit} from "@glow/BatchCommit.sol";
import "forge-std/Test.sol";
import {USDG} from "@glow/USDG.sol";

string constant fileToWriteTo = "deployedContractsGoerli.json";

contract DeployFullGoerliGuarded is Test, Script {
    bytes32 gcaRequirementsHash = keccak256("my hash good ser");
    address vestingContract = address(0xE414D49268837291fde21c33AD7e30233b7041C2);

    MockUSDC mockUSDC;
    EarlyLiquidity earlyLiquidity;
    MinerPoolAndGCA gcaAndMinerPoolContract;
    VetoCouncil vetoCouncilContract;
    SafetyDelay holdingContract;
    GrantsTreasury treasury;
    USDG usdg;
    address uniswapV2Router = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address uniswapV2Factory = address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    address me = address(0x412412412421431);

    address usdgOwner = me;
    address usdcReceiver = address(0xfdafafdafafa124412f);
    string forkUrl = vm.envString("GOERLI_RPC_URL");
    uint256 goerliFork;

    address deployer = me;

    function setUp() public {
        goerliFork = vm.createFork(forkUrl);
    }

    function test_guarded_deployRun() external {
        vm.selectFork(goerliFork);
        vm.startPrank(me);
        address[] memory startingAgents = new address[](1);
        startingAgents[0] = me;
        address[] memory startingVetoCouncilAgents = new address[](1);
        startingVetoCouncilAgents[0] = me;
        mockUSDC = new MockUSDC();

        uint256 deployerNonce = vm.getNonce(me);

        address precomputedMinerPool = computeCreateAddress(me, deployerNonce + 8);
        address precomputedGovernance = computeCreateAddress(me, deployerNonce + 4);
        address precomputedGCC = computeCreateAddress(me, deployerNonce);
        address precomputedGlow = computeCreateAddress(me, deployerNonce + 1);
        address precomputedUSDG = computeCreateAddress(me, deployerNonce + 2);
        address precomputedEarlyLiquidity = computeCreateAddress(me, deployerNonce + 3);
        address precomputedVeto = computeCreateAddress(me, deployerNonce + 5);
        address precomputedHoldingContract = computeCreateAddress(me, deployerNonce + 6);
        address precomputedGrants = computeCreateAddress(me, deployerNonce + 7);
        GoerliGCCGuardedLaunch gcc = new GoerliGCCGuardedLaunch({
            _gcaAndMinerPoolContract: address(precomputedMinerPool),
            _governance: address(precomputedGovernance),
            _glowToken: address(precomputedGlow),
            _usdg: address(precomputedUSDG),
            _vetoCouncilAddress: address(precomputedVeto),
            _uniswapRouter: uniswapV2Router,
            _uniswapFactory: uniswapV2Factory
        }); //deployerNonce
        gcc.allowlistPostConstructionContracts();

        GoerliGlowGuardedLaunch glow = new GoerliGlowGuardedLaunch({
            _earlyLiquidityAddress: address(precomputedEarlyLiquidity),
            _vestingContract: vestingContract,
            _gcaAndMinerPoolAddress: address(precomputedMinerPool),
            _vetoCouncilAddress: address(precomputedVeto),
            _grantsTreasuryAddress: address(precomputedGrants),
            _owner: me,
            _usdg: address(precomputedUSDG),
            _uniswapV2Factory: uniswapV2Factory,
            _gccContract: address(gcc)
        }); //deployerNonce + 1

        usdg = new USDG({
            _usdc: address(mockUSDC),
            _usdcReceiver: usdcReceiver,
            _owner: usdgOwner,
            _univ2Factory: uniswapV2Factory,
            _glow: address(glow),
            _gcc: address(gcc),
            _holdingContract: address(precomputedHoldingContract),
            _vetoCouncilContract: address(precomputedVeto),
            _impactCatalyst: address(gcc.IMPACT_CATALYST())
        }); //deployerNonce + 2

        earlyLiquidity =
            new EarlyLiquidity(address(usdg), address(holdingContract), address(glow), precomputedMinerPool); //deployerNonce + 3

        mockUSDC.mint(me, 1000000 * 1e6); //deployerNonce + 5
        mockUSDC.approve(address(usdg), 1000000 * 1e6); //deployerNonce + 6
        usdg.swap(me, 1000000 * 1e6); //deployerNonce + 7

        Governance governance = new Governance({
            gcc: address(gcc),
            gca: address(precomputedMinerPool),
            vetoCouncil: address(precomputedVeto),
            grantsTreasury: address(precomputedGrants),
            glw: address(glow)
        }); //deployerNonce + 4

        vetoCouncilContract = new VetoCouncil(address(glow), address(glow), startingVetoCouncilAgents); //deployerNonce + 5
        holdingContract = new SafetyDelay(address(vetoCouncilContract), precomputedMinerPool); //deployerNonce + 6
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
        glow.mint(me, 100 ether);

        BatchCommit batchCommit = new BatchCommit(address(gcc), address(usdg));
        gcc.mint(me, 1000 ether);
        gcc.approve(uniswapV2Router, 100 ether);
        usdg.approve(uniswapV2Router, 20000 * 1e6);
        console.log("my balance of usdg = ", usdg.balanceOf(me));
        console.log("usdg approval of uni router = ", usdg.allowance(me, uniswapV2Router));
        IUniswapRouterV2(uniswapV2Router).addLiquidity(
            address(gcc), address(usdg), 100 ether, 2000 * 1e6, 0, 0, me, block.timestamp + 1 days
        );

        gcc.approve(me, 100 ether);
        gcc.commitGCC(5 ether, me, 0);
        uint256 nextNominationCost = governance.costForNewProposal();
        governance.createChangeGCARequirementsProposal(keccak256("new requiremenents hash"), nextNominationCost);
        nextNominationCost = governance.costForNewProposal();
        governance.createVetoCouncilElectionOrSlash(address(0x444), address(0x123), true, nextNominationCost);
        vm.stopPrank();

        assertEq(address(usdg), precomputedUSDG, "pre computed usdg address should be equal to usdg address");
        assertEq(address(gcc), precomputedGCC, "pre computed gcc address should be equal to gcc address");
        assertEq(
            address(earlyLiquidity),
            precomputedEarlyLiquidity,
            "pre computed early liquidity address should be equal to early liquidity address"
        );
        assertEq(address(glow), precomputedGlow, "pre computed glow address should be equal to glow address");
        assertEq(
            address(vetoCouncilContract),
            precomputedVeto,
            "pre computed veto council address should be equal to veto council address"
        );
        assertEq(
            address(holdingContract),
            precomputedHoldingContract,
            "pre computed holding contract address should be equal to holding contract address"
        );
        assertEq(
            address(gcaAndMinerPoolContract),
            precomputedMinerPool,
            "pre computed gca and miner pool address should be equal to gca and miner pool address"
        );
        assertEq(
            address(governance),
            precomputedGovernance,
            "pre computed governance address should be equal to governance address"
        );
        assertEq(
            address(treasury),
            precomputedGrants,
            "pre computed grants treasury address should be equal to grants treasury address"
        );

        assertEq(
            glow.balanceOf(address(treasury)),
            6_000_000 ether,
            "treasury should have 6_000_000 glow tokens after deployment"
        );

        assertEq(
            glow.balanceOf(address(earlyLiquidity)),
            12_000_000 ether,
            "early liquidity should have 12_000_000 glow tokens after deployment"
        );
    }
}

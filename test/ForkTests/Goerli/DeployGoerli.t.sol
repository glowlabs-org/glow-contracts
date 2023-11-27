// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {GCC} from "@/GCC.sol";
import {TestGLOW} from "@/testing/TestGLOW.sol";
import {Governance} from "@/Governance.sol";
import {GoerliGCC} from "@/testing/GoerliGCC.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";
import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
import "forge-std/Test.sol";

contract DeployGoerliTest is Test {
    address gcaAndMinerPool = address(0xffff);
    address earlyLiquidityAddress = address(0x14444);
    address vestingContract = address(0x15555);
    address vetoCouncil = address(0x16666);
    address grantsTreasury = address(0x17777);
    address rewardAddress = address(0x18888);
    MockUSDC mockUSDC;
    address uniswapV2Router = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address SIMON = address(0xfaffafafafafafa1231);
    string goerliForkUrl = vm.envString("GOERLI_RPC_URL");
    uint256 goerliFork;

    function setUp() public {
        goerliFork = vm.createFork(goerliForkUrl);
    }

    function testDeploy() external {
        vm.startPrank(SIMON);
        vm.selectFork(goerliFork);
        mockUSDC = new MockUSDC();
        mockUSDC.mint(SIMON, 1000000 * 1e6);
        Governance governance = new Governance();
        TestGLOW glow = new TestGLOW(gcaAndMinerPool, vestingContract);
        glow.mint(SIMON, 100 ether);
        GoerliGCC gcc = new GoerliGCC(gcaAndMinerPool, address(governance), address(glow),
            address(mockUSDC), uniswapV2Router);
        gcc.mint(SIMON, 1000 ether);
        gcc.approve(uniswapV2Router, 100 ether);
        mockUSDC.approve(uniswapV2Router, 20000 * 1e6);
        IUniswapRouterV2(uniswapV2Router).addLiquidity(
            address(gcc), address(mockUSDC), 100 ether, 2000 * 1e6, 0, 0, SIMON, block.timestamp + 1 days
        );
        governance.setContractAddresses(address(gcc), gcaAndMinerPool, vetoCouncil, grantsTreasury, address(glow));
        gcc.commitGCC(5 ether, SIMON, 0);
        uint256 nextNominationCost = governance.costForNewProposal();
        governance.createChangeGCARequirementsProposal(keccak256("new requiremenents hash"), nextNominationCost);
        nextNominationCost = governance.costForNewProposal();
        governance.createVetoCouncilElectionOrSlash(address(0x444), address(0x123), true, nextNominationCost);
        vm.stopPrank();
    }
}

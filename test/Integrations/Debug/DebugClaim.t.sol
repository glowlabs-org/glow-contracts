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

contract DebugClaim is Test {
    string goerliForkUrl = vm.envString("GOERLI_RPC_URL");
    uint256 goerliFork;
    address me = 0xD509A9480559337e924C764071009D60aaCA623d;
    address minerPoolGoerli = 0xa2126e06AF1C75686BCBAbb4cD426bE35aEECC0C;

    function setUp() public {
        goerliFork = vm.createFork(goerliForkUrl);
        vm.selectFork(goerliFork);
    }

    function test_goerliClaimBucket_debug() public {
        vm.startPrank(me);
        GoerliMinerPoolAndGCAQuickPeriod minerPool = GoerliMinerPoolAndGCAQuickPeriod(minerPoolGoerli);
        bytes32[] memory proof = new bytes32[](0);
        minerPool.claimRewardFromBucket({
            bucketId: 0,
            glwWeight: 269,
            usdcWeight: 269,
            proof: proof,
            index: 0,
            user: me,
            claimFromInflation: false,
            signature: ""
        });

        vm.stopPrank();
    }
}

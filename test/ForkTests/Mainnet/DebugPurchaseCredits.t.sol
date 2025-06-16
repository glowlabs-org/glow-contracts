/*// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {GCC} from "@/GCC.sol";
import {TestGLOW} from "@/testing/TestGLOW.sol";
import {Governance} from "@/Governance.sol";
import {GoerliGCC} from "@/testing/Goerli/GoerliGCC.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";
import {EarlyLiquidity} from "@/EarlyLiquidity.sol";
import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
import {CarbonCreditDescendingPriceAuction} from "@/CarbonCreditDescendingPriceAuction.sol";
import {GoerliMinerPoolAndGCAQuickPeriod} from "@/testing/Goerli/GoerliMinerPoolAndGCA.QuickPeriod.sol";
import {VetoCouncil} from "@/VetoCouncil/VetoCouncil.sol";
import {SafetyDelay} from "@/SafetyDelay.sol";
import {MinerPoolAndGCA} from "@/MinerPoolAndGCA/MinerPoolAndGCA.sol";
import {GrantsTreasury} from "@/GrantsTreasury.sol";
import {BatchCommit} from "@/BatchCommit.sol";
import {USDG} from "@/USDG.sol";
import "forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

string constant fileToWriteTo = "deployedContractsGoerli.json";

struct ClaimLeaf {
    address payoutWallet;
    uint256 glwWeight;
    uint256 usdcWeight;
}

struct ClaimObj {
    uint256 bucket;
    uint256 glwWeight;
    uint256 usdcWeight;
    bytes32[] proof;
    uint256 reportIndex;
    address leafAddress;
}

contract DebugPurchaseCredits is Test {
    string mainnetForkUrl = vm.envString("MAINNET_RPC");
    uint256 mainnetFork;
    address buyer = (0x77f41144E787CB8Cd29A37413A71F53f92ee050C);
    CarbonCreditDescendingPriceAuction auction =
        CarbonCreditDescendingPriceAuction(0x85fbB04DEBBDEa052a6422E74bFeA57B17e50A80);

    function setUp() public {
        mainnetFork = vm.createFork(mainnetForkUrl);
        vm.selectFork(mainnetFork);
    }

    function test_buyGCC() public {
        vm.startPrank(buyer);

        uint256 unitsForSale = auction.unitsForSale();
        uint256 price = auction.getPricePerUnit();

        auction.buyGCC(1519298972, 99847);

        uint256 gccBalance = auction.GCC().balanceOf(buyer);
        console.log("GCC Balance: ", gccBalance);
        //Commit them all
        GCC(address(auction.GCC())).commitGCC(gccBalance, buyer, 0);
        gccBalance = auction.GCC().balanceOf(buyer);
        console.log("GCC Balance: ", gccBalance);
        vm.stopPrank();
    }
}*/

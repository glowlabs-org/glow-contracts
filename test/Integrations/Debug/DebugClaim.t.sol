// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
// import {GCC} from "@/GCC.sol";
// import {TestGLOW} from "@/testing/TestGLOW.sol";
// import {GoerliGovernanceQuickPeriod} from "@/testing/Goerli/GoerliGovernance.QuickPeriod.sol";
// import {GoerliGCC} from "@/testing/Goerli/GoerliGCC.sol";
// import {MockUSDC} from "@/testing/MockUSDC.sol";
// import {EarlyLiquidity} from "@/EarlyLiquidity.sol";
// import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
// import {CarbonCreditDutchAuction} from "@/CarbonCreditDutchAuction.sol";
// import {GoerliMinerPoolAndGCAQuickPeriod} from "@/testing/Goerli/GoerliMinerPoolAndGCA.QuickPeriod.sol";
// import {VetoCouncil} from "@/VetoCouncil.sol";
// import {HoldingContract} from "@/HoldingContract.sol";
// import {GrantsTreasury} from "@/GrantsTreasury.sol";
// import {BatchCommit} from "@/BatchCommit.sol";
import {MinerPoolAndGCA} from "@/MinerPoolAndGCA/MinerPoolAndGCA.sol";
import "forge-std/Test.sol";

contract Debug2 is Test {
    string mainnetForkUrl = vm.envString("MAINNET_RPC");
    uint256 mainnetFork;
    address gca = 0xB2d687b199ee40e6113CD490455cC81eC325C496;
    address farm = 0x7781182412aC86aC1a1a50686847728002211882;
    MinerPoolAndGCA minerPoolAndGCA = MinerPoolAndGCA(0x6Fa8C7a89b22bf3212392b778905B12f3dBAF5C4);
  /*
  {
  "weekNumber": 19,
  "totalCreditsProduced": 0.4970041288201747,
  "totalCreditsProducedBN": "497004128820174700",
  "totalGlowWeightInFinalized": "350581250",
  "totalGlowWeightHuman": "350.58125",
  "totalGCCWeightInFinalized": "497004",
  "totalGCCWeightHuman": "0.497004",
  "root": "0xc13bb1d37a18d61b0ce3a77ce447936444adf3768e1fdbb0300c34a7db565c43"
}
*/

/*
   {
        "wallet": "0xCB0695C5e231D04a36feb07841e26D44e6D08c9d",
        "glowWeight": "65935096",
        "usdgWeight": "65920",
        "proof": [
            "0x3b3366fa05f2f8045b29f89fa869b7f68385d40acfe190a83951189df12ab6ff",
            "0xa2cab092ec2b91edd76cadb016c3d7b301d4e3e1ed718da9eee197931529150b",
            "0xd10d4cae3a3a3d6a3c74cbd373536eec3998304dc199c02848c8ab114389e278"
        ]
    }
    */
    function setUp() public {
        mainnetFork = vm.createFork(mainnetForkUrl);
        vm.selectFork(mainnetFork);
    }
    
    function testForkChangeGCAs() public {
        address[] memory gcasToSlash = new address[](0);
        address[] memory newGCAs = new address[](2);
        newGCAs[0] = 0xB2d687b199ee40e6113CD490455cC81eC325C496;
        newGCAs[1] = 0x63a74612274FbC6ca3f7096586aF01Fd986d69cE;
        uint256 proposalCreationTimestamp = 1713556415;
        minerPoolAndGCA.executeAgainstHash(gcasToSlash, newGCAs, proposalCreationTimestamp);
    }

    function test_claimWeek23() public {

        vm.startPrank(farm);
        /*

bucketNumber
: 
23
glowWeight
: 
"68627700"
indexOfGCA
: 
0
payoutWallet
: 
"0x7781182412aC86aC1a1a50686847728002211882"
proof
: 
Array(4)
0
: 
"0xed30f9fbb32b7fed702ac387c51155312c5e61e79405dbf1f024585feb0b03d9"
1
: 
"0x4ee0c843256916e4e8787dad8a54cbdc7bc7fcdb602c3741dd07f3ed1ada17ea"
2
: 
"0xeffd64e6c57ead8a5c80b6ffc975be73d313fb6fd70a0a582601d07f3bbb3661"
3
: 
"0x87aa313f618efd96556168344d5721069b30545b4f769f4c49ef1752203eb604"
length
: 
4
[[Prototype]]
: 
Array(0)
usdcWeight
: 
"70555"
*/
        bytes32[] memory proof = new bytes32[](4);
        proof[0] = 0xed30f9fbb32b7fed702ac387c51155312c5e61e79405dbf1f024585feb0b03d9;
        proof[1] = 0x4ee0c843256916e4e8787dad8a54cbdc7bc7fcdb602c3741dd07f3ed1ada17ea;
        proof[2] = 0xeffd64e6c57ead8a5c80b6ffc975be73d313fb6fd70a0a582601d07f3bbb3661;
        proof[3] = 0x87aa313f618efd96556168344d5721069b30545b4f769f4c49ef1752203eb604;

        uint256 farmGlowWeight = 68627700;
        uint256 farmUsdgWeight = 70555;

        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: 23,
            glwWeight: farmGlowWeight,
            usdcWeight: farmUsdgWeight,
            proof: proof,
            index: 0,
            user: farm,
            claimFromInflation: false,
            signature: ""
        });

        vm.stopPrank();


    }
}

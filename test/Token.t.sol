// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.13;

// import "forge-std/Test.sol";
// import {TimelockedWallet} from "../src/TimelockedWallet.sol";
// import "../src/GCC.sol";
// import "forge-std/console.sol";

// contract TokenTest is Test {
//     address simon = address(1);
//     address david = address(2);
//     GCC t;
//     TimelockedWallet tw;

//     function setUp() public {}

//     function testGeneral() public {
//         vm.startPrank(simon);
//         address[] memory approvedSpenders = new address[](2);
//         approvedSpenders[0] = simon;
//         approvedSpenders[1] = david;
//         t = new GCC(approvedSpenders);
//         assertEq(t.name(), "GCC");

//         uint256 balance = t.balanceOf(simon);
//         assertEq(balance, 5000 * 1e18);

//         t.retireGCC(4999 * 1e18);

//         uint256 transferrableBalance = t.getTransferrableBalance(simon);
//         assertEq(transferrableBalance, 1 * 1e18);
//         assertEq(t.balanceOf(simon), balance);

//         t.transfer(david, 1 * 1e18);

//         uint256 transferrableBalanceAfter = t.getTransferrableBalance(simon);
//         console.log("transferrableBalanceAfter: %s", transferrableBalanceAfter);

//         vm.expectRevert();
//         t.transfer(david, 1 * 1e18);

//         vm.stopPrank();
//     }
// }

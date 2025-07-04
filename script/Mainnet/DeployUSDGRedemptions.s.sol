// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";
import {USDG} from "../../src/USDG.sol";
import {USDGRedemption} from "../../src/USDGRedemption.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployUSDGRedemptions is Script {
    USDG _usdg = USDG(0xe010ec500720bE9EF3F82129E7eD2Ee1FB7955F2);
    IERC20 _usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address multisig = 0xc5174BBf649a92F9941e981af68AaA14Dd814F85;

    function run() external {
        vm.startBroadcast();
        USDGRedemption redemption = new USDGRedemption({usdg: _usdg, usdc: _usdc, withdrawGuardian: multisig});
        vm.stopBroadcast();
    }
}

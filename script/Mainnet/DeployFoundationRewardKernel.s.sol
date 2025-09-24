// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "@/testing/MockERC20.sol";
import {Forwarder} from "@/Forwarder.sol";
import {USDG} from "@/USDG.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";
import {USDG} from "@/USDG.sol";
import {CounterfactualHolderFactory} from "@/v2/CounterfactualHolderFactory.sol";
import {OffchainFractions} from "@/v2/OffchainFractions.sol";
import {FoundationRewardKernel} from "@/v2/FoundationRewardKernel.sol";


contract DeployFoundationRewardKernel is Test, Script {
    function run() external {
        vm.startBroadcast();
        address foundationMultisig = 0x5252FdA14A149c01EA5A1D6514a9c1369E4C70b4;
        address rejectionMultisig = 0x5e230FED487c86B90f6508104149F087d9B1B0A7;
        CounterfactualHolderFactory cfhFactory =  CounterfactualHolderFactory(0x2c3AB887746F6f4a8a4b9Db6aC800eb71945509A);

        // CounterfactualHolderFactory cfhFactory = new CounterfactualHolderFactory();
        FoundationRewardKernel foundationRewardKernel =
            new FoundationRewardKernel(foundationMultisig, rejectionMultisig, cfhFactory, 2 weeks);

        vm.stopBroadcast();
    }
}

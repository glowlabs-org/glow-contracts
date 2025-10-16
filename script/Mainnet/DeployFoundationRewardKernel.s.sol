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
        address foundationMultisig = 0x624A89feC195254ec46CcFa04ca3a7F5ABf66803;
        address rejectionMultisig = 0xa8859ce3654aFf520789dFFa0FbAcBB412927437;
        CounterfactualHolderFactory cfhFactory = CounterfactualHolderFactory(0x5bB7eC88cA80146FF47019079Cf0330532A1157F);

        // CounterfactualHolderFactory cfhFactory = new CounterfactualHolderFactory();
        FoundationRewardKernel foundationRewardKernel =
            new FoundationRewardKernel(foundationMultisig, rejectionMultisig, cfhFactory, 2 weeks);

        vm.stopBroadcast();
    }
}

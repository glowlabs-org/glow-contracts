// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IGCC} from "@/interfaces/IGCC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BatchRetire {
    IGCC public immutable GCC;
    IERC20 public immutable USDC;

    constructor(address gcc, address usdc) {
        GCC = IGCC(gcc);
        USDC = IERC20(usdc);
    }

    event GCCEmission(bytes data);
    event USDCEmission(bytes data);

    function retireGCC(uint256 amount, bytes memory data) external {
        GCC.retireGCC(amount, address(this));
        emit GCCEmission(data);
    }

    function retireUSDC(uint256 amount, bytes memory data) external {
        uint256 balBefore = USDC.balanceOf(address(this));
        USDC.transferFrom(msg.sender, address(this), amount);
        uint256 balAfter = USDC.balanceOf(address(this));
        uint256 amountToRetire = balAfter - balBefore;
        GCC.retireUSDC(amountToRetire, address(this));
        emit USDCEmission(data);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdCheats.sol";
import "forge-std/console.sol";
import {IEarlyLiquidity} from "@/interfaces/IEarlyLiquidity.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface Mintable {
    function mint(address to, uint256 amount) external;
}

contract Handler is Test {
    IEarlyLiquidity public earlyLiquidity;
    IERC20 public usdc;

    constructor(address _earlyLiquidity, address _usdc) public {
        earlyLiquidity = IEarlyLiquidity(_earlyLiquidity);
        usdc = IERC20(_usdc);
        Mintable(address(usdc)).mint(address(this), 1_000_000_000 ether);
        usdc.approve(address(earlyLiquidity), 1_000_000_000 ether);
    }

    function buy(uint256 amount, uint256 maxCost) public {
        earlyLiquidity.buy(amount, maxCost);
    }
}

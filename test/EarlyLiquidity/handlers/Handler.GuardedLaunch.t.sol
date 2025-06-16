// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdCheats.sol";
import "forge-std/console.sol";
import {IEarlyLiquidity} from "@glow/interfaces/IEarlyLiquidity.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TestUSDG} from "@glow/testing/TestUSDG.sol";

interface Mintable {
    function mint(address to, uint256 amount) external;
}

contract Handler is Test {
    IEarlyLiquidity public earlyLiquidity;
    IERC20 public usdc;
    TestUSDG public usdg;

    constructor(address _earlyLiquidity, address _usdc, address _usdg) public {
        earlyLiquidity = IEarlyLiquidity(_earlyLiquidity);
        usdc = IERC20(_usdc);
        usdg = TestUSDG(_usdg);
        Mintable(address(usdc)).mint(address(this), 1_000_000_000 ether);
        usdc.approve(address(usdg), 1_000_000_000 ether);
        usdg.swap(address(this), 1_000_000_000 ether);
        usdg.approve(address(earlyLiquidity), 1_000_000_000 ether);
    }

    function buy(uint256 amount, uint256 maxCost) public {
        earlyLiquidity.buy(amount, maxCost);
    }
}

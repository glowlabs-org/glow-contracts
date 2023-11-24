// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {ERC20} from "./ERC20.sol";

contract MockUSDCTax is ERC20 {
    uint256 public taxNumerator = 100; //1% tax
    uint256 public taxDenominator = 10_000;

    constructor() ERC20("USDC", "USDC") {}

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function _transfer(address from, address to, uint256 value) internal override {
        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }

        uint256 tax = value * taxNumerator / taxDenominator;
        uint256 valueToSend = value - tax;
        _update(from, address(this), tax);
        _update(from, to, valueToSend);
    }
}

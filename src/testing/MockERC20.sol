// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract MockERC20 is ERC20Permit {
    uint8 immutable d;

    constructor(string memory name, string memory symbl, uint8 decimals) ERC20(name, symbl) ERC20Permit(symbl) {
        d = decimals;
    }

    function decimals() public view virtual override returns (uint8) {
        return d;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

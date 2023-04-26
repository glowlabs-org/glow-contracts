// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @author Simon
/// @dev --- miscanellanous information
contract Nominations is Ownable {
    uint256 public constant NOMINATION_FEE = 1 ether;
    IERC20 immutable GCC;

    /// @dev should track how many nominations a certain address holds
    mapping(address => uint256) public nominations;

    /// @param _gcc the address of the glow token
    constructor(address _gcc) {
        GCC = IERC20(_gcc);
    }

    // function buyNomination()
}

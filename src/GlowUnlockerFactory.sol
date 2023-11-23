// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {GlowUnlocker2} from "@/GlowUnlocker2.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract GlowUnlockerFactory is Ownable {
    event GlowUnlockerDeployed(address indexed unlocker);

    constructor(address _factoryOwner) Ownable(_factoryOwner) {}

    bytes32 private constant SALT = bytes32(uint256(0xfffff));

    function deployUnlocker(address _glow, address[] memory accounts, uint256[] memory amounts)
        external
        returns (address)
    {
        bytes memory bytecode = type(GlowUnlocker2).creationCode;
        address unlocker = Create2.deploy(0, SALT, bytecode);
        GlowUnlocker2(unlocker).initialize(_glow, accounts, amounts);
        emit GlowUnlockerDeployed(unlocker);
        _transferOwnership(address(0));
        return unlocker;
    }

    function computeUnlockerAddress() external view returns (address) {
        bytes memory bytecode = type(GlowUnlocker2).creationCode;
        bytes32 codeHash = keccak256(abi.encodePacked(bytecode));
        return Create2.computeAddress(SALT, codeHash);
    }
}

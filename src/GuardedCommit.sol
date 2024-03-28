// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract GuardedCommit is Ownable(tx.origin) {
    mapping(address => bool) public auth;

    error NotAuth();
    /**
     * struct Commitment {
     *     address from,
     *     uint256 amountUSDC,
     * }
     *     bytes memory bytes = abi.encode(uint256 totalImpactGenerated,Commitment[])
     */

    event USDCEmission(uint256 amount, bytes32 txHash, bytes data);

    function writeUSDCData(uint256 amount, bytes32 txHash, bytes memory data) public {
        _checkAuth();
        emit USDCEmission(amount, txHash, data);
    }

    function setAuth(address _addr, bool _auth) public onlyOwner {
        auth[_addr] = _auth;
    }

    function _checkAuth() internal {
        if (!auth[msg.sender]) revert NotAuth();
    }
}

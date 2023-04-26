// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "./GCCERC20.sol";

error NotApprovedNominationSpender();

contract Token is ERC20("GCC", "GCC") {
    mapping(address => bool) private _approvedNominationSpenders;
    mapping(address => uint256) public nominatedBalance;

    constructor(address[] memory approvedSpenders) {
        _mint(msg.sender, 5000 * 1e18);
        for (uint256 i; i < approvedSpenders.length;) {
            _approvedNominationSpenders[approvedSpenders[i]] = true;
            unchecked {
                ++i;
            }
        }
    }

    function useNomination(address from, uint256 numToSpend) external {
        if (!_approvedNominationSpenders[msg.sender]) revert NotApprovedNominationSpender();
        _useNomination(from, numToSpend);
    }

    function retireGCC(uint256 numToRetire) external {
        _incrementKarmaBalance(msg.sender, numToRetire);
        _grantNominations(msg.sender, numToRetire);
    }
}

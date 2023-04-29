// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "./GCCERC20.sol";

error NotApprovedNominationSpender();

contract Token is ERC20("GCC", "GCC") {
    //If there's only one spender than we can make it constant or immutable rather than reading from the mapping
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

    /// @dev would be used by the nominations contract to cast votes
    function useNomination(address from, uint256 numToSpend) external {
        if (!_approvedNominationSpenders[msg.sender]) revert NotApprovedNominationSpender();
        _useNomination(from, numToSpend);
    }

    /// @dev is used to retire tokens which does two things
    /// @dev 1. is grants the user Karma (non-transferrable uint mapping) --  1 karma * 1eDECIMALS = the equivalent to 1 metric ton of CO2
    /// @dev 2. it grants nominations which are usable as seen in `useNomination`
    /// TODO: Decide if _retireToken function should burn underlying tokens rather than dealing with transferrableBalance
    /// that would reduce SLOADS in the transfer function
    function retireGCC(uint256 numToRetire) external {
        _retireToken(numToRetire);
    }
}

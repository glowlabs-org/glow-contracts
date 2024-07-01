// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VetoCouncil} from "@/VetoCouncil/VetoCouncil.sol";
import {VetoCouncilSalaryHelper, NULL_ADDRESS, Status} from "@/VetoCouncil/VetoCouncilSalaryHelper.sol";
import {IVetoCouncil} from "@/interfaces/IVetoCouncil.sol";

contract VetoCouncilGuardedLaunchV2 is VetoCouncil {
    /* -------------------------------------------------------------------------- */
    /*                                 constructor                                */
    /* -------------------------------------------------------------------------- */
    /**
     * @param governance the address of the governance contract
     * @param _glowToken the address of the GLOW token
     * @param _startingMembers the addresses of the starting council members
     * @dev starting with zero members will cause a divide by zero error
     *     - It's expected that _startingMembers will never be empty
     */
    constructor(address governance, address _glowToken, address[] memory _startingMembers)
        payable
        VetoCouncil(governance, _glowToken, _startingMembers)
    {}

    /* -------------------------------------------------------------------------- */
    /*                 overrides to set state in constructors                     */
    /* -------------------------------------------------------------------------- */

    /**
     * @dev
     */
    function initializeMembers(address[] memory members, uint256) internal virtual override(VetoCouncilSalaryHelper) {
        address[7] memory initmembers;
        if (members.length > 7) {
            _revert(MaxSevenVetoCouncilMembers.selector);
        }
        uint8 len = uint8(members.length);
        unchecked {
            for (uint8 i; i < len; ++i) {
                if (isZero(members[i])) {
                    _revert(IVetoCouncil.ZeroAddressInConstructor.selector);
                }
                initmembers[i] = members[i];
                _status[members[i]] = Status({isActive: true, isSlashed: false, indexInArray: i});
            }
            for (uint8 i = len; i < 7; ++i) {
                initmembers[i] = NULL_ADDRESS;
            }
        }
        _vetoCouncilMembers = initmembers;
        paymentNonceTomembersHash[1] = keccak256(abi.encodePacked(members));
        //-DIFF Here we are setting the paymentNonceToShiftStartTimestamp to the current block timestamp
        // Instead of genesis. If we set to genesis, it would double count the rewards
        _paymentNonceToShiftStartTimestamp[1] = block.timestamp;
    }
}

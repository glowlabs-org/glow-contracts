// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {VestingMathLib} from "@/libraries/VestingMathLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVetoCouncil} from "@/interfaces/IVetoCouncil.sol";

/// @dev we use a > 0 value as the null address
//      - to avoid deleting a slot and having to reinitialize it with a cold sstore
address constant NULL_ADDRESS = 0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF;

/// @dev since there are no more than 7 veto council members
///     -   we use uint8.max as the null index
uint8 constant NULL_INDEX = type(uint8).max;

/**
 * @param isActive - whether or not the member is active
 * @param isSlashed - whether or not the member is slashed
 * @param indexInArray - the index inside the veto council members array
 */
struct Status {
    bool isActive;
    bool isSlashed;
    uint8 indexInArray;
}

/**
 * @title VetoCouncilSalaryHelper
 * @notice A library to help with the salary of the Veto Council
 *         -  handles the salary and payout of the Veto Council
 * @author DavidVorick
 * @author 0xSimon(twitter) - 0xSimbo(github)
 * @dev a nonce is a unique identifier for a shift and is incremented every time the salary rate changes
 *         - if an member is removed before the rate has changed, they will earn until their `shiftEndTimestamp`
 *  @dev payouts vest linearly at 1% per week.
 *         - It takes 100 weeks for a payout to fully vest
 */
contract VetoCouncilSalaryHelper {
    error HashesNotUpdated();
    error CannotSetNonceToZero();
    error MaxSevenVetoCouncilMembers();
    error MemberNotFound();
    error ShiftHasNotStarted();
    error HashMismatch();

    /**
     * @dev The amount of GLOW that is awarded per second
     *          -   for the entire veto council
     */
    uint256 private constant REWARDS_PER_SECOND = 5000 ether / uint256(7 days);

    /**
     * @notice The nonce at which the current shift started
     * @dev store as 1 to avoid cold sstore for the first payment nonce
     */
    uint256 public paymentNonce = 1;

    /**
     * @dev (member -> Status)
     */
    mapping(address => Status) private _status;

    /**
     * @notice an array containing all the veto council members
     * @dev the null address is represented as 0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF
     */
    address[7] private _vetoCouncilMembers;

    /**
     * @notice paymentNonce -> keccak256(abi.encodePacked(vetoCouncilMembers))
     * @dev used in withdrawing rewards
     */
    mapping(uint256 => bytes32) public paymentNonceTomembersHash;

    /**
     * @dev payment nonce -> shift start timestamp
     */
    mapping(uint256 => uint256) private _paymentNonceToShiftStartTimestamp;

    /**
     * @notice The amount of tokens that have been withdrawn from a given payment nonce for a given member
     */
    mapping(address => mapping(uint256 => uint256)) public amountAlreadyWithdrawnFromPaymentNonce;
    /**
     * ----------------------------------------------
     */
    /**
     * ----------       EXTERNAL VIEW --------------
     */
    /**
     * ----------------------------------------------
     */

    /**
     * @notice Returns the (withdrawableAmount, slashableAmount) for an member for a given nonce
     * @param member - the address of the members
     * @param nonce - the nonce of the payout
     * @return (withdrawableAmount, slashableAmount) - the amount of tokens that can be withdrawn and the amount that are still vesting
     */
    function payoutData(address member, uint256 nonce, address[] memory members)
        external
        view
        returns (uint256, uint256)
    {
        return _payoutData(member, nonce, members);
    }

    /**
     * @notice returns the `Status` struct for a given member
     * @param member The address of the member to get the `Status` struct for
     * @return status - the `Status` struct for the given member
     */
    function memberStatus(address member) public view returns (Status memory) {
        return _status[member];
    }

    /**
     * @notice returns the `shiftStartTimestamp` for a given nonce
     * @param nonce The nonce to get the `shiftStartTimestamp` for
     * @return shiftStartTimestamp - the `shiftStartTimestamp` for the given nonce
     */
    function paymentNonceToShiftStartTimestamp(uint256 nonce) public view returns (uint256) {
        return _paymentNonceToShiftStartTimestamp[nonce];
    }

    /**
     * @notice returns the array of veto council members without null addresses
     * @return sanitizedArray - all currently active veto council members
     */
    function vetoCouncilMembers() external view returns (address[] memory) {
        return arrayWithoutNulls(_vetoCouncilMembers);
    }

    /**
     * ----------------------------------------------
     */
    /**
     * -------     INTERNAL STATE CHANGING ---------
     */
    /**
     * ----------------------------------------------
     */

    /**
     * @dev Initializes the Veto Council
     * @dev should only be used in the constructor
     * @param members The addresses of the starting council members
     * @param genesisTimestamp The timestamp of the genesis block
     */
    function initializeMembers(address[] memory members, uint256 genesisTimestamp) internal {
        address[7] memory initmembers;
        if (members.length > type(uint8).max) {
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
        _paymentNonceToShiftStartTimestamp[1] = genesisTimestamp;
    }

    /**
     * @dev Add or remove a council member
     * @param oldMember The address of the member to be slashed or removed
     * @param newMember The address of the new member (0 = no new member)
     * @param slashOldMember Whether to slash the member or not
     * @return - true if the council member was added or removed, false if nothing was done
     */
    function replaceMember(address oldMember, address newMember, bool slashOldMember) internal returns (bool) {
        //cache the payment nonce
        uint256 paymentNonceToWriteTo = paymentNonce;
        //Cache the old member index
        uint8 memberOldIndex;
        //Increment the cached payment nonce
        ++paymentNonceToWriteTo;

        bool isoldMemberZeroAddress = isZero(oldMember);
        bool isnewMemberZeroAddress = isZero(newMember);
        //If the old member is the zero addres,
        //We need to loop until we find the first position in the array
        //Until we find a null address as that's where
        //we'll write the new member to
        //We start from the back of the array as that's where the null address will most likely be
        if (isoldMemberZeroAddress) {
            for (uint256 i; i < 7;) {
                uint256 index = 6 - i;
                address _vetomember = _vetoCouncilMembers[index];
                if (_vetomember == NULL_ADDRESS) {
                    memberOldIndex = uint8(index);
                    break;
                }
                unchecked {
                    ++i;
                }
            }
        } else {
            //load in the old member status
            Status memory oldMemberStatus = _status[oldMember];
            //Old member cannot be inactive if they're not the zero address
            if (!oldMemberStatus.isActive) {
                return false;
            }
            //find old member index to insert the new member
            memberOldIndex = oldMemberStatus.indexInArray;
        }

        //if the new member is not the zero address
        if (!isnewMemberZeroAddress) {
            Status memory newmemberStatus = _status[newMember];
            //A slashed member can never become an member again
            if (newmemberStatus.isSlashed) {
                return false;
            }
            //A new member cannot already be active
            if (newmemberStatus.isActive) {
                return false;
            }
            //Update the new member status
            _status[newMember] = Status({isActive: true, isSlashed: false, indexInArray: memberOldIndex});
        }

        if (!isoldMemberZeroAddress) {
            //Set the old member to inactive as it's not the zero address
            //State changes need to happen after all conditions clear,
            //So we put this change after checking the new member conditions
            _status[oldMember] = Status({isActive: false, isSlashed: slashOldMember, indexInArray: NULL_INDEX});
        }

        _vetoCouncilMembers[memberOldIndex] = isnewMemberZeroAddress ? NULL_ADDRESS : newMember;

        //Set the hash for the new payment nonce
        paymentNonceTomembersHash[paymentNonceToWriteTo] =
            keccak256(abi.encodePacked(arrayWithoutNulls(_vetoCouncilMembers)));
        //Set the shift start timestamp for the new payment nonce
        _paymentNonceToShiftStartTimestamp[paymentNonceToWriteTo] = block.timestamp;
        //Set the new payment nonce
        paymentNonce = paymentNonceToWriteTo;
        return true;
    }

    /**
     * @dev Used to payout the council member for their work at a given nonce
     * @param member The address of the council member
     * @param nonce The payout nonce to claim from
     * @param token The token to pay out (GLOW)
     * @param members The addresses of the council members that were active at `nonce`
     *         -   This is used to verify that the member was active at the nonce
     *         -   By comparing the hash of the members at the nonce to the hash stored in the contract
     */
    function claimPayout(address member, uint256 nonce, IERC20 token, address[] memory members) internal {
        uint256 withdrawableAmount = nextPayoutAmount(member, nonce, members);
        amountAlreadyWithdrawnFromPaymentNonce[member][nonce] += withdrawableAmount;
        SafeERC20.safeTransfer(token, member, withdrawableAmount);
    }

    /**
     * ----------------------------------------------
     */
    /**
     * -------     INTERNAL VIEW ---------
     */
    /**
     * ----------------------------------------------
     */

    /**
     * @dev a helper function to get (rewardPerSecond, secondsActive, secondsStopped, amountAlreadyWithdrawn)
     * @param member The address of the member to get the data for
     * @param nonce The nonce to get the data for
     * @param members The addresses of the council members that were active at `nonce`
     *         -   This is used to verify that the member was active at the nonce
     *         -   By comparing the hash of the members at the nonce to the hash stored in the contract
     */

    function getDataToCalculatePayout(address member, uint256 nonce, address[] memory members)
        internal
        view
        returns (uint256 rewardPerSecond, uint256 secondsActive, uint256 secondsStopped, uint256 amountAlreadyWithdrawn)
    {
        if (keccak256(abi.encodePacked(members)) != paymentNonceTomembersHash[nonce]) {
            _revert(HashMismatch.selector);
        }

        {
            bool found;
            unchecked {
                for (uint256 i; i < members.length; ++i) {
                    if (members[i] == member) {
                        found = true;
                        break;
                    }
                }
            }
            if (!found) {
                _revert(MemberNotFound.selector);
            }
        }

        //Should not get a divison by zero error
        //Since found should have reverted beforehand.
        uint256 rewardPerSecond = REWARDS_PER_SECOND / members.length;
        uint256 shiftStartTimestamp = _paymentNonceToShiftStartTimestamp[nonce];
        //We dont need to check the shift start timestamp
        //Since the hash for an uninitialized nonce will always be zero
        //and there will be no data
        uint256 shiftEndTimestamp = _paymentNonceToShiftStartTimestamp[nonce + 1];

        //This means the shift has ended
        if (shiftEndTimestamp != 0) {
            secondsStopped = block.timestamp - shiftEndTimestamp;
            secondsActive = shiftEndTimestamp - shiftStartTimestamp;
        } else {
            secondsActive = block.timestamp - shiftStartTimestamp;
        }
        amountAlreadyWithdrawn = amountAlreadyWithdrawnFromPaymentNonce[member][nonce];
        return (rewardPerSecond, secondsActive, secondsStopped, amountAlreadyWithdrawn);
    }

    /**
     * @dev a helper function to get (rewardPerSecond, secondsActive, secondsStopped, amountAlreadyWithdrawn)
     * @param member The address of the member to get the data for
     * @param nonce The nonce to get the data for
     * @param members The addresses of the council members that were active at `nonce`
     *         -   This is used to verify that the member was active at the nonce
     *         -   By comparing the hash of the members at the nonce to the hash stored in the contract
     */
    function _payoutData(address member, uint256 nonce, address[] memory members)
        private
        view
        returns (uint256, uint256)
    {
        if (_status[member].isSlashed) {
            return (0, 0);
        }
        (uint256 rewardPerSecond, uint256 secondsActive, uint256 secondsStopped, uint256 amountAlreadyWithdrawn) =
            getDataToCalculatePayout(member, nonce, members);
        (uint256 withdrawableAmount, uint256 slashableAmount) = VestingMathLib
            .calculateWithdrawableAmountAndSlashableAmount(
            rewardPerSecond, secondsActive, secondsStopped, amountAlreadyWithdrawn
        );

        return (withdrawableAmount, slashableAmount);
    }

    /**
     * @dev returns the amount of tokens that can be withdrawn by an member for a given nonce
     * @param member The address of the member to get the withdrawable amount for
     * @param nonce The nonce to get the withdrawable amount for
     * @param members The addresses of the council members that were active at `nonce`
     *         -   This is used to verify that the member was active at the nonce
     *         -   By comparing the hash of the members at the nonce to the hash stored in the contract
     * @return withdrawableAmount - the amount of tokens that can be withdrawn by the member
     */
    function nextPayoutAmount(address member, uint256 nonce, address[] memory members)
        internal
        view
        returns (uint256)
    {
        (uint256 withdrawableAmount,) = _payoutData(member, nonce, members);
        return withdrawableAmount;
    }

    /**
     * @param member The address of the member to be checked
     */
    function _isCouncilMember(address member) internal view returns (bool) {
        return _status[member].isActive;
    }

    /**
     * @dev efficiently determines if an address is the zero address
     * @param a the address to check
     * @return res - true if the address is the zero address
     */
    function isZero(address a) private pure returns (bool res) {
        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            res := iszero(a)
        }
    }

    /**
     * @dev removes all null addresses from an array
     * @param arr the array to sanitize
     * @dev used to sanitize _vetoCouncilMembers before encoding and hashing
     * @return sanitizedArray - the sanitized array
     */
    function arrayWithoutNulls(address[7] memory arr) internal pure returns (address[] memory) {
        address[] memory sanitizedArray = new address[](arr.length);
        uint256 numNotNulls;
        unchecked {
            for (uint256 i; i < arr.length; ++i) {
                if (!isNull(arr[i])) {
                    sanitizedArray[numNotNulls] = arr[i];
                    ++numNotNulls;
                }
            }
        }
        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            mstore(sanitizedArray, numNotNulls)
        }

        return sanitizedArray;
    }

    /**
     * @dev efficiently determines if an address is null address
     * @param a the address to check
     * @return res - true if the address is the null address, false otherwise
     */
    function isNull(address a) internal pure returns (bool res) {
        address _null = NULL_ADDRESS;
        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            res := eq(a, _null)
        }
    }

    /**
     * @notice More efficiently reverts with a bytes4 selector
     * @param selector The selector to revert with
     */
    function _revert(bytes4 selector) internal pure {
        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            mstore(0x0, selector)
            revert(0x0, 0x04)
        }
    }
}

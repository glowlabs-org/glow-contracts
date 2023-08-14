// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGCC is IERC20 {
    error CallerNotGCAContract();
    error BucketAlreadyMinted();
    error RetiringPermitSignatureExpired();
    error RetiringSignatureInvalid();
    error RetiringAllowanceUnderflow();

    /**
     * @notice allows gca contract to mint GCC to the carbon credit auction
     * @dev must callback to the carbon credit auction contract so it can organize itself
     * @dev a bucket can only be minted from once
     * @param bucketId the id of the bucket to mint from
     * @param amount the amount of GCC to mint
     */
    function mintToCarbonCreditAuction(uint256 bucketId, uint256 amount) external;

    /**
     * @notice returns a boolean indicating if the bucket has been minted
     * @return if the bucket has been minted
     */
    function isBucketMinted(uint256 bucketId) external view returns (bool);

    /**
     * @notice allows a user to retire credits
     * @param amount the amount of credits to retire
     * @param rewardAddress the address to retire the credits to
     *     -   Rewards Address earns:
     *     -       1.  Carbon Neutrality
     *     -       2.  Nominations
     */
    function retireGCC(uint256 amount, address rewardAddress) external;

    /**
     * @notice approves a spender to retire credits on behalf of the caller
     * @param spender the address of the spender
     * @param amount the amount of credits to approve
     */
    function increaseRetiringAllowance(address spender, uint256 amount) external;

    /**
     * @notice decreases a spender's allowance to retire credits on behalf of the caller
     * @param spender the address of the spender
     * @param amount the amount of credits to decrease the allowance by
     */
    function decreaseRetiringAllowance(address spender, uint256 amount) external;

    /**
     * @notice returns the retiring allowance for a user
     * @param account the address of the account to check
     * @param spender the address of the spender to check
     * @return the retiring allowance
     */
    function retiringAllowance(address account, address spender) external view returns (uint256);

    /**
     * @notice returns the next nonce to be used when retiring credits
     *         - only applies when the user is using EIP712 signatures similar to Permit
     * @param account the address of the account to check
     */
    function nextRetiringNonce(address account) external view returns (uint256);

    /**
     * @notice the entry point for an approved entity to retire credits on behalf of a user
     * @param from the address of the user to retire credits from
     * @param rewardAddress the address of the reward address to retire credits to
     *         - Carbon Neutrality
     *         - Nominations
     * @param amount the amount of credits to retire
     */
    function retireGCCFor(address from, address rewardAddress, uint256 amount) external;

    /**
     * @notice the entry point for an approved entity to retire credits on behalf of a user using EIP712 signatures
     * @param from the address of the user to retire credits from
     * @param rewardAddress the address of the reward address to retire credits to
     *         - Carbon Neutrality
     *         - Nominations
     * @param amount the amount of credits to retire
     * @param deadline the deadline for the signature
     * @param signature - the signature
     */
    function retireGCCForAuthorized(
        address from,
        address rewardAddress,
        uint256 amount,
        uint256 deadline,
        bytes calldata signature
    ) external;

    /**
     * @param lastUpdatedTimestamp - the last timestamp a user earned or used nominations
     * @ param amount - the amount of nominations a user has
     */
    struct Nominations {
        uint64 lastUpdatedTimestamp;
        uint192 amount;
    }

    /**
     * @notice is emitted when a user retires credits
     * @param account the account that retired credits
     * @param rewardAddress the address that earned the credits and nominations
     * @param amount the amount of credits retired
     */
    event GCCRetired(address indexed account, address indexed rewardAddress, uint256 amount);

    /**
     * @notice is emitted when a user approves a spender to retire credits on their behalf
     * @param account the account that approved a spender
     * @param spender the address of the spender
     * @param value -  new total allowance
     */
    event RetireGCCAllowance(address indexed account, address indexed spender, uint256 value);
}
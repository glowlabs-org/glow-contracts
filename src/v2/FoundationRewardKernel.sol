// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {MerkleProofLib} from "@solady/utils/MerkleProofLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {LibBitmap} from "@solady/utils/LibBitmap.sol";
import {TransientSlot} from "./utils/TransientBytes/TransientSlot.sol";
import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";
import {CounterfactualHolderFactory} from "./CounterfactualHolderFactory.sol";
import {Call} from "./Structs.sol";

/**
 * @title FoundationRewardKernel
 * @notice A Merkle-tree based reward distribution system for the Glow Foundation
 * @dev This contract enables secure, verifiable token distributions while handlingf guarded tokens
 *      that have transfer restrictions. It works with CounterfactualHolderFactory to distribute
 *      tokens that can only be transferred between EOAs and allowlisted contracts.
 *
 * Key features:
 * - Merkle tree-based reward verification
 * - Multi-signature security model with separation of concerns
 * - Support for both regular and guarded token distributions
 * - Time-delayed finality with rejection mechanism
 * - No custodied funds (tokens held externally)
 *
 * Security model:
 * - Foundation multisig: Posts reward roots and maximum amounts
 * - Rejection multisig: Can reject bad roots within finality period
 * - Hot wallet: Holds actual tokens and approves spending
 */
contract FoundationRewardKernel is ReentrancyGuard, Multicall {
    using LibBitmap for *;
    using TransientSlot for *;
    using SafeERC20 for *;

    /// @dev Thrown when caller is not the foundation multisig
    error NotFoundationMultisig();
    /// @dev Thrown when caller is not the rejection multisig
    error NotRejectionMultisig();
    /// @dev Thrown when trying to reject a nonce that is already finalized
    error AlreadyFinalized();
    /// @dev Thrown when duplicate tokens are found in the token array
    error DuplicateToken();
    /// @dev Thrown when trying to reject a nonce that is already rejected
    error AlreadyRejected();
    /// @dev Thrown when trying to operate on a nonce that doesn't exist
    error NonexistentDataAtNonce();
    /// @dev Thrown when trying to post a zero merkle root
    error CannotPostZeroRoot();
    /// @dev Thrown when trying to claim from a nonce that isn't finalized yet
    error NotYetFinalized();
    /// @dev Thrown when the provided merkle proof is invalid
    error InvalidMerkleProof();
    /// @dev Thrown when user tries to claim from a nonce they've already claimed
    error AlreadyClaimedNonce();
    /// @dev Thrown when total claimed amount would exceed the maximum allowed
    error MaxClaimedExceeded();
    /// @dev Thrown when array lengths don't match
    error LengthsDontMatch();
    /// @dev Thrown when trying to claim from a rejected nonce
    error CannotClaimFromRejectedNonce();

    /// @notice Time period after which a posted root becomes finalized and claimable
    uint256 public immutable FINALITY;

    /**
     * @notice Data structure for storing reward distribution information
     * @param merkleRoot The merkle root for this reward distribution
     * @param pushTimestamp When this root was posted
     * @param maxReward Mapping of token address to maximum claimable amount for this nonce
     * @param amountClaimed Mapping of token address to total amount already claimed for this nonce
     * @param rejected Whether this nonce has been rejected by the rejection multisig
     */
    struct RewardData {
        bytes32 merkleRoot;
        uint48 pushTimestamp;
        mapping(address token => uint256 maxAmountToSend) maxReward;
        mapping(address token => uint256 amountClaimed) amountClaimed;
        bool rejected;
    }

    /**
     * @notice Structure for specifying token and amount pairs
     * @param token The token contract address
     * @param amount The amount of tokens
     */
    struct TokenAndAmount {
        address token;
        uint256 amount;
    }

    /// @notice The foundation multisig that can post reward roots
    address public immutable FOUNDATION_MULTISIG;
    /// @notice The rejection multisig that can reject bad roots (comprised of veto council members)
    address public immutable REJECTION_MULTISIG;
    /// @notice The counterfactual holder factory for handling guarded token transfers
    CounterfactualHolderFactory public immutable CFH_FACTORY;

    /// @notice The next nonce to be used when posting a new reward root
    uint256 public $nextPostNonce;
    /// @notice Bitmap tracking which nonces each user has claimed from
    mapping(address user => LibBitmap.Bitmap) internal $claimedBitmap;
    /// @notice Mapping of nonce to reward distribution data
    mapping(uint256 nonce => RewardData) internal $rewardData;

    /// @notice Emitted when a nonce is rejected by the rejection multisig
    /// @param nonce The nonce that was rejected
    event NonceRejected(uint256 indexed nonce);

    /// @notice Emitted when a new reward root is posted
    /// @param nonce The nonce for this reward distribution
    /// @param root The merkle root for reward verification
    /// @param taa Array of tokens and their maximum claimable amounts
    event RootPosted(uint256 indexed nonce, bytes32 indexed root, TokenAndAmount[] taa);

    /// @notice Emitted when a user successfully claims rewards
    /// @param user The user who claimed the rewards
    /// @param to The address that received the tokens
    /// @param nonce The nonce from which rewards were claimed
    /// @param from The address that provided the tokens
    /// @param taa Array of tokens and amounts that were claimed
    /// @param isGuarded Array indicating which tokens are guarded tokens
    event RewardClaimed(
        address indexed user,
        address indexed to,
        uint256 indexed nonce,
        address from,
        TokenAndAmount[] taa,
        bool[] isGuarded
    );

    /**
     * @notice Constructs the FoundationRewardKernel contract
     * @param _foundationMultisig Address of the foundation multisig that can post reward roots
     * @param _rejectionMultisig Address of the rejection multisig that can reject roots
     * @param f The CounterfactualHolderFactory instance for handling guarded tokens
     * @param _finality The finality period for the reward distribution
     */
    constructor(address _foundationMultisig, address _rejectionMultisig, CounterfactualHolderFactory f, uint256 _finality) payable {
        FOUNDATION_MULTISIG = _foundationMultisig;
        REJECTION_MULTISIG = _rejectionMultisig;
        CFH_FACTORY = f;
        FINALITY = _finality;
    }

    /**
     * @notice Posts a new payout root for reward distribution
     * @dev Only callable by the foundation multisig. Creates a new nonce and stores the merkle root
     *      along with maximum claimable amounts for each token. The root becomes claimable after
     *      the finality period unless rejected by the rejection multisig.
     * @param root The merkle root for this reward distribution (cannot be zero)
     * @param taa Array of tokens and their maximum claimable amounts (no duplicates allowed)
     * @custom:emits RootPosted
     */
    function postPayoutRoot(bytes32 root, TokenAndAmount[] memory taa) external {
        if (msg.sender != FOUNDATION_MULTISIG) {
            revert NotFoundationMultisig();
        }
        if (root == bytes32(0)) {
            revert CannotPostZeroRoot();
        }
        uint256 nonce = $nextPostNonce++;

        RewardData storage rd = $rewardData[nonce];
        rd.merkleRoot = root;
        rd.pushTimestamp = uint48(block.timestamp);

        checkNoDuplicates(taa);
        uint256 l = taa.length;
        for (uint256 i; i < l; ++i) {
            rd.maxReward[taa[i].token] = taa[i].amount;
        }

        emit RootPosted(nonce, root, taa);
    }

    /**
     * @notice Rejects a posted reward root, preventing claims from that nonce
     * @dev Only callable by the rejection multisig (veto council members) and only before
     *      the finality period has passed. This provides a safety mechanism against
     *      malicious or erroneous reward distributions.
     * @param nonce The nonce to reject
     * @custom:emits NonceRejected
     */
    function rejectNonce(uint256 nonce) external {
        if (msg.sender != REJECTION_MULTISIG) {
            revert NotRejectionMultisig();
        }

        RewardData storage rd = $rewardData[nonce];
        if (rd.merkleRoot == bytes32(0)) {
            revert NonexistentDataAtNonce();
        }
        if (rd.rejected) revert AlreadyRejected();
        if (_isTimestampFinalized(rd.pushTimestamp)) {
            revert AlreadyFinalized();
        }

        rd.rejected = true;
        emit NonceRejected(nonce);
    }

    /**
     * @notice Claims rewards from a finalized nonce using a merkle proof
     * @dev Verifies the merkle proof against the stored root and transfers tokens from the
     *      specified 'from' address to the 'to' address. Handles both regular and guarded tokens.
     *      Each user can only claim once per nonce. Total claims cannot exceed maximum amounts.
     * @param nonce The nonce to claim from (must be finalized and not rejected)
     * @param proof Merkle proof demonstrating eligibility for the claimed amounts
     * @param taa Array of tokens and amounts being claimed
     * @param from Address that will provide the tokens (must have approved this contract)
     * @param to Address that will receive the tokens
     * @param isGuardedToken Array indicating which tokens are guarded (need special handling)
     * @param toCounterfactual Array indicating whether to send the tokens to a counterfactual wallet
     * @custom:emits RewardClaimed
     */
    function claimPayout(
        uint256 nonce,
        bytes32[] calldata proof,
        TokenAndAmount[] memory taa,
        address from,
        address to,
        bool[] memory isGuardedToken,
        bool[] memory toCounterfactual
    ) external nonReentrant {
        if (isGuardedToken.length != taa.length) {
            revert LengthsDontMatch();
        }

        if (toCounterfactual.length != taa.length) {
            revert LengthsDontMatch();
        }

        if ($claimedBitmap[msg.sender].get(nonce)) {
            revert AlreadyClaimedNonce();
        }
        $claimedBitmap[msg.sender].set(nonce);

        RewardData storage rd = $rewardData[nonce];
        if (rd.rejected) {
            revert CannotClaimFromRejectedNonce();
        }
        if (!_isTimestampFinalized(rd.pushTimestamp)) {
            revert NotYetFinalized();
        }
        bytes32 taaHash = keccak256(abi.encode(taa));
        bytes32 leaf = keccak256(abi.encode(msg.sender, taaHash));
        bytes32 root = rd.merkleRoot;
        if (!MerkleProofLib.verifyCalldata(proof, root, leaf)) {
            revert InvalidMerkleProof();
        }

        uint256 l = taa.length;
        for (uint256 i; i < l; ++i) {
            address token = taa[i].token;
            uint256 amt = taa[i].amount;
            if (amt == 0) continue;
            uint256 newAmountClaimed = rd.amountClaimed[token] + amt;
            if (newAmountClaimed > rd.maxReward[token]) {
                revert MaxClaimedExceeded();
            }
            rd.amountClaimed[token] = newAmountClaimed;
            handleTokenTransfer(token, from, to, amt, isGuardedToken[i], toCounterfactual[i]);
        }

        emit RewardClaimed(msg.sender, to, nonce, from, taa, isGuardedToken);
    }

    // ========= view accessors =========

    /**
     * @notice Gets metadata for a specific reward nonce
     * @param nonce The nonce to query
     * @return merkleRoot The merkle root for this nonce
     * @return pushTimestamp When this root was posted
     * @return rejected Whether this nonce has been rejected
     */
    function getRewardMeta(uint256 nonce)
        external
        view
        returns (bytes32 merkleRoot, uint48 pushTimestamp, bool rejected)
    {
        RewardData storage rd = $rewardData[nonce];
        return (rd.merkleRoot, rd.pushTimestamp, rd.rejected);
    }

    /**
     * @notice Gets the maximum claimable amount for a token at a specific nonce
     * @param nonce The nonce to query
     * @param token The token address to query
     * @return The maximum amount that can be claimed for this token at this nonce
     */
    function getMaxReward(uint256 nonce, address token) external view returns (uint256) {
        return $rewardData[nonce].maxReward[token];
    }

    /**
     * @notice Gets the total amount already claimed for a token at a specific nonce
     * @param nonce The nonce to query
     * @param token The token address to query
     * @return The total amount already claimed for this token at this nonce
     */
    function getAmountClaimed(uint256 nonce, address token) external view returns (uint256) {
        return $rewardData[nonce].amountClaimed[token];
    }

    /**
     * @notice Checks if a nonce has passed the finality period and is claimable
     * @param nonce The nonce to check
     * @return True if the nonce is finalized (claimable), false otherwise
     */
    function isFinalized(uint256 nonce) external view returns (bool) {
        return _isTimestampFinalized($rewardData[nonce].pushTimestamp);
    }

    /**
     * @notice Checks if a user has already claimed from a specific nonce
     * @param user The user address to check
     * @param nonce The nonce to check
     * @return True if the user has claimed from this nonce, false otherwise
     */
    function isClaimed(address user, uint256 nonce) external view returns (bool) {
        return $claimedBitmap[user].get(nonce);
    }

    // ======== internal ========

    /**
     * @notice Handles token transfers for both regular and guarded tokens
     * @dev For regular tokens, uses standard transferFrom. For guarded tokens,
     *      uses the CounterfactualHolderFactory to execute the transfer through
     *      a counterfactual contract to bypass transfer restrictions.
     * @param token The token contract address
     * @param from The address providing the tokens
     * @param to The address receiving the tokens
     * @param amount The amount to transfer
     * @param isGuardedToken Whether this token has transfer restrictions
     * @param toCounterfactual Whether to send the tokens to a counterfactual wallet
     */
    function handleTokenTransfer(
        address token,
        address from,
        address to,
        uint256 amount,
        bool isGuardedToken,
        bool toCounterfactual
    ) internal {
        if (!isGuardedToken) {
            IERC20(token).safeTransferFrom(from, to, amount);
            return;
        }
        Call[] memory calls = new Call[](1);
        address whoToSendTokensTo = toCounterfactual ? CFH_FACTORY.getCurrentCFH(to, token) : to;
        calls[0] =
            Call({target: token, data: abi.encodeWithSelector(IERC20.transfer.selector, whoToSendTokensTo, amount)});
        CFH_FACTORY.executeFrom(from, token, calls);
    }

    /**
     * @notice Checks that no duplicate tokens exist in the array
     * @dev Uses transient storage to efficiently track seen tokens during validation.
     *      All transient slots are cleared after validation to avoid state pollution.
     * @param taa Array of tokens and amounts to validate
     */
    function checkNoDuplicates(TokenAndAmount[] memory taa) internal {
        uint256 l = taa.length;
        for (uint256 i; i < l; ++i) {
            bytes32 slot = to(taa[i].token);
            if (slot.asBoolean().tload()) {
                revert DuplicateToken();
            }
            slot.asBoolean().tstore(true);
        }

        //Clear the slots
        for (uint256 i; i < l; ++i) {
            bytes32 slot = to(taa[i].token);
            slot.asBoolean().tstore(false);
        }
    }

    /**
     * @notice Checks if a timestamp has passed the finality period
     * @param ts The timestamp to check
     * @return True if the timestamp is finalized (current time >= ts + FINALITY)
     */
    function _isTimestampFinalized(uint256 ts) internal view returns (bool) {
        return block.timestamp >= ts + FINALITY;
    }

    /**
     * @notice Converts an address to bytes32 for use as a storage slot
     * @param a The address to convert
     * @return s The address as bytes32
     */
    function to(address a) internal pure returns (bytes32 s) {
        assembly {
            s := a
        }
    }
}

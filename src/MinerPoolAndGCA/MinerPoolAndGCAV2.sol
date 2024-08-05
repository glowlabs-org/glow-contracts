// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {GCAV2} from "./GCAV2.sol";
import {IGCA} from "@/interfaces/IGCA.sol";
import {IVetoCouncil} from "@/interfaces/IVetoCouncil.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {IMinerPoolV2} from "@/interfaces/IMinerPoolV2.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BucketSubmissionV2} from "./BucketSubmissionV2.sol";
import {MerkleProofLib} from "@solady/utils/MerkleProofLib.sol";
import {ISafetyDelay} from "@/SafetyDelay.sol";
import {IGCC} from "@/interfaces/IGCC.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {_BUCKET_DURATION} from "@/Constants/Constants.sol";
import {LibBitmap} from "@solady/utils/LibBitmap.sol";
import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";

/**
 * @title Miner Pool And GCA
 * @author @DavidVorick
 * @author @0xSimon(twitter) - 0xSimbo(github)
 *  @notice this contract allows veto council members to delay buckets as defined in the `GCA` contract
 * @notice It is the entry point for farms participating in GLOW to claim their rewards for their contributions
 */
contract MinerPoolAndGCAV2 is GCAV2, IMinerPoolV2, BucketSubmissionV2, Multicall {
    /* -------------------------------------------------------------------------- */
    /*                                  constants                                 */
    /* -------------------------------------------------------------------------- */

    using LibBitmap for LibBitmap.Bitmap;

    /**
     * @dev the amount to increase the finalization timestamp of a bucket by
     *             -   only veto council agents can delay a bucket.
     *             -   the delay is 13 weeks
     */
    uint256 private constant _BUCKET_DELAY_DURATION = uint256(7 days) * 13;

    //cast keccak "CLAIM-TOKENS"  = 0x5a2b68280ef3658be6bd388ec714543fc8d9df8f00d7ab7ab3249e364ebfa76d
    bytes32 private constant TOKENS_LEAF_PREFIX = 0x5a2b68280ef3658be6bd388ec714543fc8d9df8f00d7ab7ab3249e364ebfa76d;

    /// @dev a helper used in a bitmap
    uint256 private constant _BITS_IN_UINT = 256;

    /**
     * @notice the total amount of glow rewards available for farms per bucket
     */
    uint256 public constant GLOW_REWARDS_PER_BUCKET = 175_000 ether;

    /* -------------------------------------------------------------------------- */
    /*                                  immutables                                */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice the address of the early liquidity contract
     * @dev used for authorization in {donateTokenToRewardsPoolEarlyLiquidity}
     */
    address private immutable _EARLY_LIQUIDITY;

    /**
     * @dev the address of the veto council contract.
     */
    address private immutable _VETO_COUNCIL;

    /// @notice USDC token address
    address public immutable USDC;

    /// @notice the holding contract where intermediary rewards are stored
    /// @dev when a farm earns a USDC reward, it is sent to the holding contract
    ///     - where it will wait a minimum of 1 week before being sent to the farm
    ///     - this is in place to prevent a large amount of USDC from being sent to a farm
    ///           -   mistakenly or on purpose
    ///     - If such a case happens, the Veto Council can delay the holding contract by 13 weeks
    ///     - This should give enough time to rectify the situation
    ISafetyDelay public immutable HOLDING_CONTRACT;

    /// @notice the GCC contract
    IGCC public immutable GCC;

    /* -------------------------------------------------------------------------- */
    /*                                   mappings                                  */
    /* -------------------------------------------------------------------------- */

    /// @dev A Mapping of (user -> bitmap) to check if a user has claimed from a bucket
    mapping(address => LibBitmap.Bitmap) private _bucketClaimBitmap;

    /// @dev bitmap (bucketId -> bitmap) to check if a bucket has been used to mint to the carbon credit auction
    LibBitmap.Bitmap private _mintedToCarbonCreditAuctionBitmap;

    /// @dev A bitmap of bucketIds that have been delayed
    LibBitmap.Bitmap private _bucketDelayedBitmap;

    /**
     * @dev a mapping of bucketId -> pushed weights
     * - we could split this up into a packed map of pushedGlwWeight and pushedUSDCWeight
     *         and use one slot to fit 4 (uint32 pushedGlwWeight, uint32 pushedUSDCWeight) tuples,
     *         but since this slot will only be cold for the first write of each bucket claim,
     *         it's not worth the additional complexity and gas costs on each subsequent write
     *         to handle the packing and unpacking.
     */
    mapping(uint256 => PushedWeights) internal _weightsPushed;

    /* -------------------------------------------------------------------------- */
    /*                                   structs                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @param pushedGlwWeight - the aggregate amount of glw weight pushed
     * @param pushedUSDCWeight - the aggregate amount of USDC weight pushed
     * @dev meant to be used in conjunction with the _weightsPushed mapping
     *       - when a user claims from a bucket, the pushed weights are added to the total weights
     *       - these are tracked to ensure that the pushed weights don't overflow the total weights
     *       - that were put in place for that specific bucket
     */
    struct PushedWeights {
        uint64 pushedGlwWeight;
        uint64 pushedUSDCWeight;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 constructor                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice constructs a new MinerPoolAndGCA contract
     * @param _gcaAgents the addresses of the gca agents the contract starts with
     * @param _glowToken the address of the glow token
     * @param _governance the address of the governance contract
     * @param _requirementsHash the requirements hash of GCA Agents
     * @param _usdcToken - the USDC token address
     * @param _vetoCouncil - the address of the veto council contract.
     * @param _holdingContract - the address of the holding contract
     * @param _gcc - the address of the gcc contract
     */
    constructor(
        address[] memory _gcaAgents,
        address _glowToken,
        address _governance,
        bytes32 _requirementsHash,
        address _earlyLiquidity,
        address _usdcToken,
        address _vetoCouncil,
        address _holdingContract,
        address _gcc
    ) payable GCAV2(_gcaAgents, _glowToken, _governance, _requirementsHash) {
        _EARLY_LIQUIDITY = _earlyLiquidity;
        _VETO_COUNCIL = _vetoCouncil;
        HOLDING_CONTRACT = ISafetyDelay(_holdingContract);
        USDC = _usdcToken;
        GCC = IGCC(_gcc);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   donations                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @inheritdoc IMinerPoolV2
     */
    function donateTokenToMinerRewardsPool(address token, uint256 amount) external virtual {
        uint256 balBefore = IERC20(token).balanceOf(address(HOLDING_CONTRACT));
        SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(HOLDING_CONTRACT), amount);
        uint256 transferredBalance = IERC20(token).balanceOf(address(HOLDING_CONTRACT)) - balBefore;
        _addToCurrentBucket(token, transferredBalance);
    }

    /**
     * @inheritdoc IMinerPoolV2
     */
    function donateTokenToRewardsPoolEarlyLiquidity(address token, uint256 amount) external virtual {
        if (msg.sender != _EARLY_LIQUIDITY) {
            _revert(IMinerPoolV2.CallerNotEarlyLiquidity.selector);
        }
        _addToCurrentBucket(token, amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                       minting to carbon credit auction                     */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Handles minting to the carbon credit auction in case the bucket is finalized and no one has claimed from it
     * @param bucketId - the id of the bucket
     */
    function handleMintToCarbonCreditAuction(uint256 bucketId) external {
        if (!isBucketFinalized(bucketId)) {
            _revert(IMinerPoolV2.BucketNotFinalized.selector);
        }
        uint256 globalPackedState = getPackedBucketGlobalState(bucketId);
        uint256 amountToMint = globalPackedState & _UINT128_MASK;
        _handleMintToCarbonCreditAuction(bucketId, amountToMint);
    }

    /* -------------------------------------------------------------------------- */
    /*                                 claiming rewards                           */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IMinerPoolV2
    function claimRewardFromBucket(
        uint256 bucketId,
        uint256 glwWeight,
        uint256 usdcWeight,
        bytes32[] memory proof,
        bool[] memory flags,
        address[] memory tokens,
        uint256 index,
        bool claimFromInflation
    ) public virtual {
        if (claimFromInflation) {
            claimGlowFromInflation();
        }
        if (!isBucketFinalized(bucketId)) {
            _revert(IMinerPoolV2.BucketNotFinalized.selector);
        }

        {
            bytes32 root = getBucketRootAtIndexEfficient(bucketId, index);
            _checkClaimMultiProof(msg.sender, glwWeight, usdcWeight, tokens, proof, flags, root);
        }

        uint256 globalStatePackedData = getPackedBucketGlobalState(bucketId);
        /**
         * Bit Layout of packed global state
         *     [0-127] - totalNewGCC
         *     [128-191] - totalGLWRewardsWeight
         *     [192-255] - totalUSDCRewardsWeight
         */
        uint256 totalUSDCWeight = globalStatePackedData >> 192;
        uint256 totalGlwWeight = (globalStatePackedData >> 128) & _UINT64_MASK;
        _checkWeightsForOverflowAndWriteStorage({
            bucketId: bucketId,
            totalGlwWeight: totalGlwWeight,
            totalUSDCWeight: totalUSDCWeight,
            glwWeight: glwWeight,
            usdcWeight: usdcWeight
        });

        _handleMintToCarbonCreditAuction(bucketId, globalStatePackedData & _UINT128_MASK);

        //no need to use a mask since totalUSDCWeight uses the last 64 bits, so we can just shift
        {
            bool alreadyClaimed = _bucketClaimBitmap[msg.sender].get(bucketId);
            if (alreadyClaimed) {
                _revert(IMinerPoolV2.UserAlreadyClaimed.selector);
            }
            _bucketClaimBitmap[msg.sender].set(bucketId);
        }

        //Just in case a faulty report is submitted, we need to choose the min of _glwWeight and totalGlwWeight
        // so that we don't overflow the available USDC rewards
        // and grab rewards from other buckets
        _revertIfGreater(usdcWeight, totalUSDCWeight, IMinerPoolV2.USDCWeightGreaterThanTotalWeight.selector);
        _revertIfGreater(glwWeight, totalGlwWeight, IMinerPoolV2.GlowWeightGreaterThanTotalWeight.selector);
        _handleClaimRewardsTokenLoop(bucketId, msg.sender, tokens, usdcWeight, totalUSDCWeight);

        {
            uint256 amountGlowToSend = (GLOW_REWARDS_PER_BUCKET * glwWeight) / totalGlwWeight;
            if (amountGlowToSend > 0) {
                SafeERC20.safeTransfer(IERC20(address(GLOW_TOKEN)), msg.sender, amountGlowToSend);
            }
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                                 bucket delays                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @inheritdoc IMinerPoolV2
     */
    function delayBucketFinalization(uint256 bucketId) external {
        if (isBucketFinalized(bucketId)) {
            _revert(IGCA.BucketAlreadyFinalized.selector);
        }
        if (!IVetoCouncil(_VETO_COUNCIL).isCouncilMember(msg.sender)) {
            _revert(IMinerPoolV2.CallerNotVetoCouncilMember.selector);
        }

        if (_buckets[bucketId].lastUpdatedNonce != slashNonce) {
            _revert(IMinerPoolV2.CannotDelayBucketThatNeedsToUpdateSlashNonce.selector);
        }

        if (_bucketDelayedBitmap.get(bucketId)) {
            _revert(IMinerPoolV2.BucketAlreadyDelayed.selector);
        }

        _bucketDelayedBitmap.set(bucketId);

        //If the length is zero that means
        // the bucket has never been initialized
        // therefore, the veto council should not be able
        // to delay a bucket that has never been initialized
        if (_buckets[bucketId].reports.length == 0) {
            _revert(IMinerPoolV2.CannotDelayEmptyBucket.selector);
        }

        _buckets[bucketId].finalizationTimestamp += SafeCast.toUint128(bucketDelayDuration());
    }

    /* -------------------------------------------------------------------------- */
    /*                                view functions                              */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice returns the bucket claim bitmap for a user
     * @param bucketId - the bucket id to check
     * @dev Each bit in the 256 bit word is a flag for whether the user has claimed from that bucket.
     * @dev for example, for bitmap with b'....0011'  with an input of any bucketId between `0-255` means that the user has claimed from buckets 0 and 1
     * @dev If `bucketId` is 256, the bitmap returned will start at bucketId 256 in the 0 binary slot.
     * @dev a few examples:
     *             `bucketId` = 12 returns the bitmap at position 0 which contains the flags for buckets 0-255
     *             `bucketId` = 256 returns the bitmap at position 1 which contains the flags for buckets 256- 511
     *             `bucketId` = 515 returns the bitmap at position 2 which contains the flags for buckets  512-767
     * @return bitmap - the bitmap in which the bucket claim flag is located for the `user`
     */
    function bucketClaimBitmap(uint256 bucketId, address user) public view returns (uint256) {
        return _bucketClaimBitmap[user].map[bucketId / 256];
    }

    /**
     * @inheritdoc IMinerPoolV2
     */
    function hasBucketBeenDelayed(uint256 bucketId) external view returns (bool) {
        return _bucketDelayedBitmap.get(bucketId);
    }

    /**
     * @notice the early liquidity contract address
     * @return the early liquidity contract address
     */
    function earlyLiquidity() public view returns (address) {
        return _EARLY_LIQUIDITY;
    }

    /**
     * @notice The amount of time a delay action will delay a bucket by
     * @return the amount of time a delay action will delay a bucket by
     */
    function bucketDelayDuration() public pure virtual returns (uint256) {
        return _BUCKET_DELAY_DURATION;
    }

    /* -------------------------------------------------------------------------- */
    /*                          internal state changing funcs                     */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice used internally to mint `amount` of GCC to the carbon credit auction contract
     * @dev each bucketId can only be used once to mint to the carbon credit auction
     * @dev the `_mintedToCarbonCreditAuctionBitmap` is used to track which buckets have already been used to mint to the carbon credit auction
     *             -   the key for the mapping is `bucketId / 256`
     *             -   where each slot stores a bitmap of the buckets that have been used to mint to the carbon credit auction
     * @dev if the bucket has already been used to mint to the carbon credit auction, the function continues
     *             -   this behaviour is necessary since the function is called on each claim
     *             -   this function's `trigger` is the `claimRewardMultipleRootsOneBucket` function
     *             -   it should also be able to be called publically
     */
    function _handleMintToCarbonCreditAuction(uint256 bucketId, uint256 amountToMint) internal {
        bool alreadyMinted = _mintedToCarbonCreditAuctionBitmap.get(bucketId);
        if (alreadyMinted) {
            return;
        }
        _mintedToCarbonCreditAuctionBitmap.set(bucketId);
        GCC.mintToCarbonCreditAuction(bucketId, amountToMint);
    }

    /**
     * @dev used internally in the claim reward function to loop through the tokens
     * @param bucketId - the id of the bucket
     * @param user - the address of the user
     * @param tokens - the addresses of the tokens
     * @param usdcWeight - the weight of the user's USDC rewards
     * @param totalUSDCWeight - the total amount of USDC weight for the bucket
     */
    function _handleClaimRewardsTokenLoop(
        uint256 bucketId,
        address user,
        address[] memory tokens,
        uint256 usdcWeight,
        uint256 totalUSDCWeight
    ) internal {
        for (uint256 i; i < tokens.length; ++i) {
            address token = tokens[i];
            uint256 amountInBucket = _getAmountForTokenAndInitIfNot(token, bucketId);
            amountInBucket = (amountInBucket * usdcWeight) / totalUSDCWeight;
            if (amountInBucket > 0) {
                // Cant overflow since the amountInBucket is less than  or equal to the total amount in the bucket
                HOLDING_CONTRACT.addHolding(user, token, SafeCast.toUint192(amountInBucket));
            }
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                                 internal view                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Checks the multi proof for the user's claim
     * @param user - the address of the user
     * @param glwWeight - the weight of the user's glw rewards
     * @param usdcWeight - the weight of the user's USDC rewards
     * @param tokens - the addresses of the payout tokens
     * @param proof - the merkle proof that the user's rewards are stored in the bucket
     * @param flags - the flags used in the multi-merkle proof
     * @param root - the root of the merkle tree
     */
    function _checkClaimMultiProof(
        address user,
        uint256 glwWeight,
        uint256 usdcWeight,
        address[] memory tokens,
        bytes32[] memory proof,
        bool[] memory flags,
        bytes32 root
    ) internal pure {
        bytes32 weightsLeaf = keccak256(bytes.concat(keccak256(abi.encodePacked(user, glwWeight, usdcWeight))));
        bytes32 tokensLeaf = keccak256(bytes.concat(keccak256(abi.encodePacked(TOKENS_LEAF_PREFIX, tokens))));
        //Sort the leaves
        bytes32[] memory leaves = new bytes32[](2);
        if (weightsLeaf > tokensLeaf) {
            leaves[0] = tokensLeaf;
            leaves[1] = weightsLeaf;
        } else {
            leaves[0] = weightsLeaf;
            leaves[1] = tokensLeaf;
        }

        if (!MerkleProofLib.verifyMultiProof(proof, root, leaves, flags)) {
            _revert(IMinerPoolV2.InvalidUserProof.selector);
        }
    }

    /**
     * @dev checks to make sure the weights in the report
     *         - don't overflow the total weights that have been set for the bucket
     *         - Without this check, a malicious weight could be used to overflow the total weights
     *         - and grab rewards from other buckets
     * @param bucketId - the id of the bucket
     * @param totalGlwWeight - the total amount of glw weight for the bucket
     * @param totalUSDCWeight - the total amount of USDC weight for the bucket
     * @param glwWeight - the glw weight of the leaf in the report being claimed
     * @param usdcWeight - the USDC weight of the leaf in the report being claimed
     */
    function _checkWeightsForOverflowAndWriteStorage(
        uint256 bucketId,
        uint256 totalGlwWeight,
        uint256 totalUSDCWeight,
        uint256 glwWeight,
        uint256 usdcWeight
    ) internal {
        PushedWeights memory pushedWeights = _weightsPushed[bucketId];
        pushedWeights.pushedGlwWeight += SafeCast.toUint64(glwWeight);
        pushedWeights.pushedUSDCWeight += SafeCast.toUint64(usdcWeight);
        if (pushedWeights.pushedGlwWeight > totalGlwWeight) {
            _revert(IMinerPoolV2.GlowWeightOverflow.selector);
        }
        if (pushedWeights.pushedUSDCWeight > totalUSDCWeight) {
            _revert(IMinerPoolV2.USDCWeightOverflow.selector);
        }
        _weightsPushed[bucketId] = pushedWeights;
    }

    /**
     * @dev used internally to get the genesis timestamp
     *             - it must override the function in BucketSubmission
     * @return the genesis timestamp
     */
    function _genesisTimestamp() internal view virtual override(BucketSubmissionV2, GCAV2) returns (uint256) {
        return GENESIS_TIMESTAMP;
    }

    /**
     * @dev used to pass down the current week to the {GCASalaryHelper} contract
     */
    function _currentWeek() internal view override(GCAV2) returns (uint256) {
        return currentBucket();
    }

    /**
     * @notice returns the bucket duration
     * @return bucketDuration - the bucket duration
     */
    function bucketDuration() internal pure virtual override(GCAV2, BucketSubmissionV2) returns (uint256) {
        return _BUCKET_DURATION;
    }

    /**
     * @notice reverts with {selector} if {a} > {b}
     * @param a - the first number
     * @param b - the second number
     * @param selector - the selector to revert with
     */
    function _revertIfGreater(uint256 a, uint256 b, bytes4 selector) internal pure {
        if (a > b) _revert(selector);
    }

    /**
     * @dev efficient checker for whether an address is the zero address
     * @param addr the address to check
     * @return res - whether or not the address is the zero address
     */
    function _isZeroAddress(address addr) internal pure returns (bool res) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            res := iszero(addr)
        }
    }
}

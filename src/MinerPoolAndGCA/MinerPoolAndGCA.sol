// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {GCA} from "./GCA.sol";
import {IGCA} from "@/interfaces/IGCA.sol";
import {IVetoCouncil} from "@/interfaces/IVetoCouncil.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {IMinerPool} from "@/interfaces/IMinerPool.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BucketSubmission} from "./BucketSubmission.sol";
import {MerkleProofLib} from "@solady/utils/MerkleProofLib.sol";
import {IHoldingContract} from "@/HoldingContract.sol";
import {IGCC} from "@/interfaces/IGCC.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {_BUCKET_DURATION} from "@/Constants/Constants.sol";

/**
 * @title Miner Pool And GCA
 * @author @DavidVorick
 * @author @0xSimon(twitter) - 0xSimon(github)
 *  @notice this contract allows veto council members to delay buckets as defined in the `GCA` contract
 * @notice It is the entry point for farms participating in GLOW to claim their rewards for their contributions
 */
contract MinerPoolAndGCA is GCA, EIP712, IMinerPool, BucketSubmission {
    /* -------------------------------------------------------------------------- */
    /*                                  constants                                 */
    /* -------------------------------------------------------------------------- */
    /**
     * @dev the amount to increase the finalization timestamp of a bucket by
     *             -   only veto council agents can delay a bucket.
     *             -   the delay is 13 weeks
     */
    uint256 private constant _BUCKET_DELAY_DURATION = uint256(7 days) * 13;

    /// @dev a helper used in a bitmap
    uint256 private constant _BITS_IN_UINT = 256;

    /// @dev the typehash for the claim reward from bucket eip712 message
    bytes32 private constant _CLAIM_REWARD_FROM_BUCKET_TYPEHASH = keccak256(
        "ClaimRewardFromBucket(uint256 bucketId,uint256 glwWeight,uint256 usdcWeight,uint256 index,bool claimFromInflation)"
    );

    /**
     * @notice the total amount of glow rewards available for farms per bucket
     */
    uint256 public constant GLOW_REWARDS_PER_BUCKET = 175_000 ether;

    /* -------------------------------------------------------------------------- */
    /*                                  immutables                                */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice the address of the early liquidity contract
     * @dev used for authorization in {donateToUSDCMinerRewardsPoolEarlyLiquidity}
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
    IHoldingContract public immutable HOLDING_CONTRACT;

    /// @notice the GCC contract
    IGCC public immutable GCC;

    /* -------------------------------------------------------------------------- */
    /*                                   mappings                                  */
    /* -------------------------------------------------------------------------- */
    /**
     * @dev a mapping of (bucketId / 256) -> user  -> bitmap
     */
    mapping(uint256 => mapping(address => uint256)) private _bucketClaimBitmap;

    /**
     * @dev a mapping of (bucketId / 256) -> bitmap
     */
    mapping(uint256 => uint256) private _mintedToCarbonCreditAuctionBitmap;

    /**
     * @dev a mapping of (bucketId / 256) -> bitmap
     * @dev a bucket can only be delayed once
     */
    mapping(uint256 => uint256) private _bucketDelayedBitmap;

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
    ) payable GCA(_gcaAgents, _glowToken, _governance, _requirementsHash) EIP712("GCA and MinerPool", "1") {
        _EARLY_LIQUIDITY = _earlyLiquidity;
        _VETO_COUNCIL = _vetoCouncil;
        HOLDING_CONTRACT = IHoldingContract(_holdingContract);
        USDC = _usdcToken;
        GCC = IGCC(_gcc);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   donations                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @inheritdoc IMinerPool
     */
    function donateToUSDCMinerRewardsPool(uint256 amount) external virtual {
        uint256 balBefore = IERC20(USDC).balanceOf(address(HOLDING_CONTRACT));
        SafeERC20.safeTransferFrom(IERC20(USDC), msg.sender, address(HOLDING_CONTRACT), amount);
        uint256 transferredBalance = IERC20(USDC).balanceOf(address(HOLDING_CONTRACT)) - balBefore;
        _addToCurrentBucket(transferredBalance);
    }

    /**
     * @inheritdoc IMinerPool
     */
    function donateToUSDCMinerRewardsPoolEarlyLiquidity(uint256 amount) external virtual {
        if (msg.sender != _EARLY_LIQUIDITY) _revert(IMinerPool.CallerNotEarlyLiquidity.selector);
        _addToCurrentBucket(amount);
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
            _revert(IMinerPool.BucketNotFinalized.selector);
        }
        uint256 globalPackedState = getPackedBucketGlobalState(bucketId);
        uint256 amountToMint = globalPackedState & _UINT128_MASK;
        _handleMintToCarbonCreditAuction(bucketId, amountToMint);
    }

    /* -------------------------------------------------------------------------- */
    /*                                 claiming rewards                           */
    /* -------------------------------------------------------------------------- */
    /**
     * @inheritdoc IMinerPool
     */
    function claimRewardFromBucket(
        uint256 bucketId,
        uint256 glwWeight,
        uint256 usdcWeight,
        bytes32[] calldata proof,
        uint256 index,
        address user,
        bool claimFromInflation,
        bytes memory signature
    ) external {
        if (msg.sender != user) {
            bytes32 hash = createClaimRewardFromBucketDigest(bucketId, glwWeight, usdcWeight, index, claimFromInflation);
            if (!SignatureChecker.isValidSignatureNow(user, hash, signature)) {
                _revert(IMinerPool.SignatureDoesNotMatchUser.selector);
            }
        }
        if (!isBucketFinalized(bucketId)) {
            _revert(IMinerPool.BucketNotFinalized.selector);
        }
        if (claimFromInflation) {
            claimGlowFromInflation();
        }
        {
            bytes32 root = getBucketRootAtIndexEfficient(bucketId, index);
            _checkProof(user, glwWeight, usdcWeight, proof, root);
        }

        uint256 globalStatePackedData = getPackedBucketGlobalState(bucketId);

        /**
         * Bit Layout of packed global state
         *     [0-127] - totalNewGCC
         *     [128-191] - totalGLWRewardsWeight
         *     [192-255] - totalUSDCRewardsWeight
         */
        uint256 totalUSDCWeight = globalStatePackedData >> 192;
        uint256 totalGlwWeight = globalStatePackedData >> 128 & _UINT64_MASK;
        _checkWeightsForOverflow({
            bucketId: bucketId,
            totalGlwWeight: totalGlwWeight,
            totalUSDCWeight: totalUSDCWeight,
            glwWeight: glwWeight,
            usdcWeight: usdcWeight
        });

        _handleMintToCarbonCreditAuction(bucketId, globalStatePackedData & _UINT128_MASK);

        //no need to use a mask since totalUSDCWeight uses the last 64 bits, so we can just shift
        {
            uint256 userBitmap = _getUserBitmapForBucket(bucketId, user);
            userBitmap = _checkClaimAvailableAndReturnNewBitmap(bucketId, userBitmap);
            _setUserBitmapForBucket(bucketId, user, userBitmap);
        }

        //Just in case a faulty report is submitted, we need to choose the min of _glwWeight and totalGlwWeight
        // so that we don't overflow the available USDC rewards
        // and grab rewards from other buckets
        uint256 amountInBucket = _getAmountForTokenAndInitIfNot(bucketId);
        _revertIfGreater(usdcWeight, totalUSDCWeight, IMinerPool.USDCWeightGreaterThanTotalWeight.selector);
        amountInBucket = amountInBucket * usdcWeight / totalUSDCWeight;
        if (amountInBucket > 0) {
            //Cant overflow since the amountInBucket is less than  or equal to the total amount in the bucket
            HOLDING_CONTRACT.addHolding(user, USDC, SafeCast.toUint192(amountInBucket));
        }

        {
            _revertIfGreater(glwWeight, totalGlwWeight, IMinerPool.GlowWeightGreaterThanTotalWeight.selector);
            uint256 amountGlowToSend = GLOW_REWARDS_PER_BUCKET * glwWeight / totalGlwWeight;
            if (amountGlowToSend > 0) {
                SafeERC20.safeTransfer(IERC20(address(GLOW_TOKEN)), user, amountGlowToSend);
            }
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                                 bucket delays                              */
    /* -------------------------------------------------------------------------- */
    /**
     * @inheritdoc IMinerPool
     */
    function delayBucketFinalization(uint256 bucketId) external {
        if (isBucketFinalized(bucketId)) {
            _revert(IGCA.BucketAlreadyFinalized.selector);
        }
        if (!IVetoCouncil(_VETO_COUNCIL).isCouncilMember(msg.sender)) {
            _revert(IMinerPool.CallerNotVetoCouncilMember.selector);
        }

        if (_buckets[bucketId].lastUpdatedNonce != slashNonce) {
            _revert(IMinerPool.CannotDelayBucketThatNeedsToUpdateSlashNonce.selector);
        }

        uint256 key = bucketId / 256;
        uint256 shift = bucketId % 256;
        uint256 existingBitmap = _bucketDelayedBitmap[key];
        uint256 bitmask = 1 << shift;
        if (existingBitmap & bitmask != 0) {
            _revert(IMinerPool.BucketAlreadyDelayed.selector);
        }
        _bucketDelayedBitmap[key] = existingBitmap | bitmask;
        //If the length is zero that means
        // the bucket has never been initialized
        // therefore, the veto council should not be able
        // to delay a bucket that has never been initialized
        if (_buckets[bucketId].reports.length == 0) {
            _revert(IMinerPool.CannotDelayEmptyBucket.selector);
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
        return _getUserBitmapForBucket(bucketId, user);
    }

    /**
     * @inheritdoc IMinerPool
     */
    function hasBucketBeenDelayed(uint256 bucketId) external view returns (bool) {
        return _bucketDelayedBitmap[bucketId / 256] & (1 << (bucketId % 256)) != 0;
    }

    /**
     * @notice the early liquidity contract address
     * @return the early liquidity contract address
     */
    function earlyLiquidity() public view returns (address) {
        return _EARLY_LIQUIDITY;
    }

    /**
     * @inheritdoc IMinerPool
     */
    function createClaimRewardFromBucketDigest(
        uint256 bucketId,
        uint256 glwWeight,
        uint256 usdcWeight,
        uint256 index,
        bool claimFromInflation
    ) public view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                _domainSeparatorV4(),
                keccak256(
                    abi.encode(
                        _CLAIM_REWARD_FROM_BUCKET_TYPEHASH, bucketId, glwWeight, usdcWeight, index, claimFromInflation
                    )
                )
            )
        );
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
        uint256 key = bucketId / _BITS_IN_UINT;
        uint256 existingBitmap = _mintedToCarbonCreditAuctionBitmap[key];
        uint256 shift = bucketId % _BITS_IN_UINT;
        uint256 mask = 1 << shift;
        if (mask & existingBitmap == 0) {
            existingBitmap |= mask;
            _mintedToCarbonCreditAuctionBitmap[key] = existingBitmap;
            GCC.mintToCarbonCreditAuction(bucketId, amountToMint);
        }
    }

    /**
     * @dev used internally to set the user bitmap for a bucket
     * @param bucketId - the id of the bucket
     *                         - this is divided by 256 to find the key in the mapping
     * @param user - the address of the user
     * @param userBitmap - the new bitmap to set for the user
     */
    function _setUserBitmapForBucket(uint256 bucketId, address user, uint256 userBitmap) internal {
        _bucketClaimBitmap[bucketId / _BITS_IN_UINT][user] = userBitmap;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 internal view                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @dev user internally to check if a user has already claimed for a bucket
     *             -   if the have already claimed, the function reverts
     *             -   if they have not claimed from the bucket, the function returns the new bitmap that should be stored
     * @param bucketId - the id of the bucket
     * @param userBitmap - the existing bitmap of the user
     * @return userBitmap - the new bitmap of the user
     */
    function _checkClaimAvailableAndReturnNewBitmap(uint256 bucketId, uint256 userBitmap)
        internal
        pure
        returns (uint256)
    {
        uint256 shift = (bucketId % _BITS_IN_UINT);
        uint256 mask = 1 << shift;
        if (mask & userBitmap != 0) _revert(IMinerPool.UserAlreadyClaimed.selector);
        userBitmap |= mask;
        return userBitmap;
    }

    /**
     * @dev used internally check if a proof is valid
     * @param payoutWallet - the address of the user
     * @param glwWeight - the weight of the user's glw rewards
     * @param usdcWeight - the weight of the user's USDC rewards
     * @param proof - the merkle proof of the user's rewards
     *                     - the leaves are {payoutWallet, glwWeight, usdcWeight}
     */
    function _checkProof(
        address payoutWallet,
        uint256 glwWeight,
        uint256 usdcWeight,
        bytes32[] calldata proof,
        bytes32 root
    ) internal pure {
        bytes32 leaf = keccak256(abi.encodePacked(payoutWallet, glwWeight, usdcWeight));

        if (!MerkleProofLib.verifyCalldata(proof, root, leaf)) {
            _revert(IMinerPool.InvalidProof.selector);
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
    function _checkWeightsForOverflow(
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
            _revert(IMinerPool.GlowWeightOverflow.selector);
        }
        if (pushedWeights.pushedUSDCWeight > totalUSDCWeight) {
            _revert(IMinerPool.USDCWeightOverflow.selector);
        }
        _weightsPushed[bucketId] = pushedWeights;
    }

    /**
     * @dev used internally to get the user bitmap for a bucket
     * @param bucketId - the id of the bucket
     *                 - this is divided by 256 to find the key in the mapping
     * @param user - the address of the user
     * @return userBitmap - the bitmap of the user
     */
    function _getUserBitmapForBucket(uint256 bucketId, address user) internal view returns (uint256) {
        return _bucketClaimBitmap[bucketId / _BITS_IN_UINT][user];
    }

    /**
     * @dev used internally to get the genesis timestamp
     *             - it must override the function in BucketSubmission
     * @return the genesis timestamp
     */
    function _genesisTimestamp() internal view override(BucketSubmission, GCA) returns (uint256) {
        return GENESIS_TIMESTAMP;
    }

    /**
     * @dev used to pass down the current week to the {GCASalaryHelper} contract
     */
    function _currentWeek() internal view override(GCA) returns (uint256) {
        return currentBucket();
    }

    /**
     * @dev used to pass down the domain separator to the {GCASalaryHelper} contract
     */
    function _domainSeperatorV4Main() internal view virtual override(GCA) returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @notice returns the bucket duration
     * @return bucketDuration - the bucket duration
     */
    function bucketDuration() internal pure virtual override(GCA, BucketSubmission) returns (uint256) {
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

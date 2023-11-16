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
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IHoldingContract} from "@/HoldingContract.sol";
import {IGCC} from "@/interfaces/IGCC.sol";

contract MinerPoolAndGCA is GCA, EIP712, IMinerPool, BucketSubmission {
    //----------------- CONSTANTS -----------------//

    /**
     * @dev the amount to increase the finalization timestamp of a bucket by
     *             -   only veto council agents can delay a bucket.
     *             -   the delay is 13 weeks
     */
    uint256 private constant _BUCKET_DELAY_LENGTH = uint256(7 days) * 13;

    /// @dev a helper used in a bitmap
    uint256 private constant _BITS_IN_UINT = 256;

    /// @dev the typehash for the claim reward from bucket eip712 message
    bytes32 private constant CLAIM_REWARD_FROM_BUCKET_TYPEHASH = keccak256(
        "ClaimRewardFromBucket(uint256 bucketId,uint256 glwWeight,uint256 grcWeight,uint256 index,bool claimFromInflation)"
    );

    /**
     * @notice the address of the early liquidity contract
     * @dev used for authorization in {donateToGRCMinerRewardsPoolEarlyLiquidity}
     */
    address private immutable _EARLY_LIQUIDITY;

    /**
     * @dev the address of the veto council contract.
     */
    address private immutable _VETO_COUNCIL;

    /**
     * @notice the total amount of glow rewards available for farms per bucket
     */
    uint256 public constant GLOW_REWARDS_PER_BUCKET = 175_000 ether;

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
    IGCC public gccContract;

    //----------------- MAPPINGS -----------------//

    /**
     * @dev a mapping of (bucketId / 256) -> user  -> address -> bitmap
     */
    mapping(uint256 => mapping(address => uint256)) private _bucketClaimBitmap;

    /**
     * @dev a mapping of (bucketId / 256) -> user -> bitmap
     */
    mapping(uint256 => uint256) private _mintedToCarbonCreditAuctionBitmap;

    /**
     * @dev a mapping of (bucketId / 256) -> -user -> bitmap
     * @dev a bucket can only be delayed once
     */
    mapping(uint256 => uint256) private _bucketDelayedBitmap;

    /**
     * @dev a mapping of bucketId -> pushed weights
     * - we could split this up into a packed map of pushedGlwWeight and pushedGrcWeight
     *         and use one slot to fit 4 (uint32 pushedGlwWeight, uint32 pushedGrcWeight) tuples,
     *         but since this slot will only be cold for the first write of each bucket claim,
     *         it's not worth the additional complexity and gas costs on each subsequent write
     *         to handle the packing and unpacking.
     */
    mapping(uint256 => PushedWeights) internal _weightsPushed;

    /**
     * @param pushedGlwWeight - the aggregate amount of glw weight pushed
     * @param pushedGrcWeight - the aggregate amount of grc weight pushed
     * @dev meant to be used in conjunction with the _weightsPushed mapping
     *       - when a user claims from a bucket, the pushed weights are added to the total weights
     *       - these are tracked to ensure that the pushed weights dont overflow the total weights
     *       - that were put in place for that specific bucket
     */
    struct PushedWeights {
        uint64 pushedGlwWeight;
        uint64 pushedGrcWeight;
    }

    //************************************************************* */
    //*****************  CONSTRUCTOR   ************** */
    //************************************************************* */

    /**
     * @notice constructs a new GCA contract
     * @param _gcaAgents the addresses of the gca agents the contract starts with
     * @param _glowToken the address of the glow token
     * @param _governance the address of the governance contract
     * @param _requirementsHash the requirements hash of GCA Agents
     * @param _grcToken - the first grc token (USDC)
     * @param _vetoCouncil - the address of the veto council contract.
     * @param _holdingContract - the address of the holding contract
     */
    constructor(
        address[] memory _gcaAgents,
        address _glowToken,
        address _governance,
        bytes32 _requirementsHash,
        address _earlyLiquidity,
        address _grcToken,
        address _vetoCouncil,
        address _holdingContract
    ) payable GCA(_gcaAgents, _glowToken, _governance, _requirementsHash) EIP712("GCA and MinerPool", "1") {
        _EARLY_LIQUIDITY = _earlyLiquidity;
        _VETO_COUNCIL = _vetoCouncil;
        HOLDING_CONTRACT = IHoldingContract(_holdingContract);
        HOLDING_CONTRACT.setMinerPool(address(this));
        USDC = _grcToken;
    }

    //************************************************************* */
    //***********  EXTERNAL/PUBLIC STATE CHANGING FUNCS    ******** */
    //************************************************************* */

    //----------------- DONATIONS -----------------//

    /**
     * @inheritdoc IMinerPool
     */
    function donateToGRCMinerRewardsPool(uint256 amount) external virtual {
        uint256 balBefore = IERC20(USDC).balanceOf(address(HOLDING_CONTRACT));
        SafeERC20.safeTransferFrom(IERC20(USDC), msg.sender, address(HOLDING_CONTRACT), amount);
        uint256 transferredBalance = IERC20(USDC).balanceOf(address(HOLDING_CONTRACT)) - balBefore;
        _addToCurrentBucket(transferredBalance);
    }

    /**
     * @inheritdoc IMinerPool
     */
    function donateToGRCMinerRewardsPoolEarlyLiquidity(uint256 amount) external virtual {
        if (msg.sender != _EARLY_LIQUIDITY) _revert(IMinerPool.CallerNotEarlyLiquidity.selector);
        _addToCurrentBucket(amount);
    }

    //----------------- CLAIMING -----------------//

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

    /**
     * @inheritdoc IMinerPool
     */
    function claimRewardFromBucket(
        uint256 bucketId,
        uint256 glwWeight,
        uint256 grcWeight,
        bytes32[] calldata proof,
        uint256 index,
        address user,
        bool claimFromInflation,
        bytes memory signature
    ) external {
        if (msg.sender != user) {
            bytes32 hash = createClaimRewardFromBucketDigest(bucketId, glwWeight, grcWeight, index, claimFromInflation);
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
        //Call from GCA.sol
        {
            bytes32 root = getBucketRootAtIndexEfficient(bucketId, index);
            _checkProof(user, glwWeight, grcWeight, proof, root);
        }

        uint256 globalStatePackedData = getPackedBucketGlobalState(bucketId);

        uint256 totalGRCWeight = globalStatePackedData >> 192;
        uint256 totalGlwWeight = globalStatePackedData >> 128 & _UINT64_MASK;
        _checkWeightsForOverflow({
            bucketId: bucketId,
            totalGlwWeight: totalGlwWeight,
            totalGrcWeight: totalGRCWeight,
            glwWeight: glwWeight,
            grcWeight: grcWeight
        });
        _handleMintToCarbonCreditAuction(bucketId, globalStatePackedData & _UINT128_MASK);

        //no need to use a mask since totalGRCWeight uses the last 64 bits, so we can just shift
        {
            uint256 userBitmap = _getUserBitmapForBucket(bucketId, user);
            userBitmap = _checkClaimAvailableAndReturnNewBitmap(bucketId, userBitmap);
            _setUserBitmapForBucket(bucketId, user, userBitmap);
        }

        //Just in case a faulty report is submitted, we need to choose the min of _glwWeight and totalGlwWeight
        // so that we don't overflow the available GRC rewards
        // and grab rewards from other buckets
        uint256 amountInBucket = _getAmountForTokenAndInitIfNot(bucketId);
        amountInBucket = amountInBucket * _min(grcWeight, totalGRCWeight) / totalGRCWeight;
        if (amountInBucket > 0) {
            HOLDING_CONTRACT.addHolding(user, USDC, uint192(amountInBucket));
        }

        {
            uint256 amountGlowToSend = GLOW_REWARDS_PER_BUCKET * glwWeight / totalGlwWeight;
            if (amountGlowToSend > 0) {
                SafeERC20.safeTransfer(IERC20(address(GLOW_TOKEN)), user, amountGlowToSend);
            }
        }
    }

    //----------------- BUCKET DELAY -----------------//

    /**
     * @inheritdoc IMinerPool
     */
    function delayBucketFinalization(uint256 bucketId) external {
        if (isBucketFinalized(bucketId)) {
            _revert(IGCA.BucketAlreadyFinalized.selector);
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

        _buckets[bucketId].finalizationTimestamp += uint128(_BUCKET_DELAY_LENGTH);

        if (!IVetoCouncil(_VETO_COUNCIL).isCouncilMember(msg.sender)) {
            _revert(IMinerPool.CallerNotVetoCouncilMember.selector);
        }
    }

    /// @notice initializes the gcc token
    /// @param gcc - the gcc token
    function setGCC(address gcc) external {
        if (!_isZeroAddress(address(gccContract))) {
            _revert(IGCA.GCCAlreadySet.selector);
        }
        gccContract = IGCC(gcc);
    }

    //************************************************************* */
    //*************  PUBLIC/EXTERNAL VIEW FUNCTIONS   ************ */
    //************************************************************* */

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
        uint256 grcWeight,
        uint256 index,
        bool claimFromInflation
    ) public view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                _domainSeparatorV4(),
                keccak256(
                    abi.encode(
                        CLAIM_REWARD_FROM_BUCKET_TYPEHASH, bucketId, glwWeight, grcWeight, index, claimFromInflation
                    )
                )
            )
        );
    }

    //************************************************************* */
    //*************  INTERNAL STATE CHANGING FUNCS   ************ */
    //************************************************************* */

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
            gccContract.mintToCarbonCreditAuction(bucketId, amountToMint);
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

    function bucketClaimBitmap(uint256 bucketId, address user) public view returns (uint256) {
        return _getUserBitmapForBucket(bucketId, user);
    }

    //************************************************************* */
    //***************  INTERNAL VIEW/PURE FUNCTIONS   ************ */
    //************************************************************* */

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
     * @param grcWeight - the weight of the user's grc rewards
     * @param proof - the merkle proof of the user's rewards
     *                     - the leaves are {payoutWallet, glwWeight, grcWeight}
     */
    function _checkProof(
        address payoutWallet,
        uint256 glwWeight,
        uint256 grcWeight,
        bytes32[] calldata proof,
        bytes32 root
    ) internal pure {
        bytes32 leaf = keccak256(abi.encodePacked(payoutWallet, glwWeight, grcWeight));

        if (!MerkleProofLib.verifyCalldata(proof, root, leaf)) {
            _revert(IMinerPool.InvalidProof.selector);
        }
    }

    /**
     * @dev checks to make sure the weights in the report
     *         - dont overflow the total weights that have been set for the bucket
     *         - Without this check, a malicious weight could be used to overflow the total weights
     *         - and grab rewards from other buckets
     * @param bucketId - the id of the bucket
     * @param totalGlwWeight - the total amount of glw weight for the bucket
     * @param totalGrcWeight - the total amount of grc weight for the bucket
     * @param glwWeight - the glw weight of the leaf in the report being claimed
     * @param grcWeight - the grc weight of the leaf in the report being claimed
     */
    function _checkWeightsForOverflow(
        uint256 bucketId,
        uint256 totalGlwWeight,
        uint256 totalGrcWeight,
        uint256 glwWeight,
        uint256 grcWeight
    ) internal {
        PushedWeights memory pushedWeights = _weightsPushed[bucketId];
        pushedWeights.pushedGlwWeight += uint64(glwWeight);
        pushedWeights.pushedGrcWeight += uint64(grcWeight);
        if (pushedWeights.pushedGlwWeight > totalGlwWeight) {
            _revert(IMinerPool.GlowWeightOverflow.selector);
        }
        if (pushedWeights.pushedGrcWeight > totalGrcWeight) {
            _revert(IMinerPool.GRCWeightOverflow.selector);
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

    function _currentWeek() internal view override(GCA) returns (uint256) {
        return currentBucket();
    }

    function _domainSeperatorV4Main() internal view virtual override(GCA) returns (bytes32) {
        return _domainSeparatorV4();
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

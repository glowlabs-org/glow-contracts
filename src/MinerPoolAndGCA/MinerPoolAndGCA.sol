// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {GCA} from "./GCA.sol";
import {IGCA} from "@/interfaces/IGCA.sol";
import {IGlow} from "@/interfaces/IGlow.sol";
import {IVetoCouncil} from "@/interfaces/IVetoCouncil.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IMinerPool} from "@/interfaces/IMinerPool.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BucketSubmission} from "./BucketSubmission.sol";
import {MerkleProofLib} from "@solady/utils/MerkleProofLib.sol";

/**
 * TODO:
 * Add tests for all the claim stuff
 * Add tests for new bitmask stuff
 * add test for merkle root efficient in gca
 * make sure that veto council agents can delay a bucket
 * make sure to check for finalization around bucket submission
 * add tests for withdrawing from reinstated buckets
 */
contract MinerPoolAndGCA is GCA, EIP712, IMinerPool, BucketSubmission {
    //----------------- CONSTANTS -----------------//

    /// @notice the typehash for the electricity future auction authorization
    /// @dev this is used for the EIP712 signature when gca's authorize bidders
    bytes32 public constant ELECTRICITY_FUTURES_TYPEHASH =
        keccak256("ElectricityFutureAuctionAuthorization(address bidder,uint256 expirationTimestamp)");

    // /// @notice the maximum length of an authorization
    // /// @dev a signature can only last 16 weeks
    // uint256 public constant MAX_AUTHORIZATION_LENGTH = uint256(7 days) * 16;

    /**
     * @notice the address of the early liquidity contract
     * @dev used for authorization in {donateToGRCMinerRewardsPoolEarlyLiquidity}
     */
    address private immutable _EARLY_LIQUIDITY;

    address private immutable _CARBON_CREDIT_AUCTION;

    address private immutable _VETO_COUNCIL;

    /**
     * @notice the total amount of glow rewards available for farms per bucket
     */
    uint256 public constant GLOW_REWARDS_PER_BUCKET = 175_000 ether;

    /**
     * @dev the amount to increase the finalization timestamp of a bucket by
     *             -   only veto council agents can delay a bucket.
     *             -   the delay is 13 weeks
     */
    uint256 private constant _BUCKET_DELAY_LENGTH = uint256(7 days) * 13;

    //----------------- STATE VARIABLES -----------------//

    /**
     * @notice a counter for the electricity future auctions
     */
    uint256 public electricityFutureAuctionCount;

    uint256 private constant _BITS_IN_UINT = 256;

    //----------------- MAPPINGS -----------------//

    //TODO: see if we use this in the getReward function from GCA.
    struct GRCTracker {
        uint248 firstAddedBucketId;
        bool isGRC;
    }

    /**
     *  @notice a mapping o4f auction id -> auction data
     */
    mapping(uint256 => IMinerPool.ElectricityFutureAuction) private _electricityFutureAuctions;

    /**
     * @dev a mapping of (bucketId / 256) -> user -> bitmap
     */
    mapping(uint256 => mapping(address => uint256)) private _bucketClaimBitmap;

    /**
     * @dev a mapping of (bucketId / 256) -> user -> bitmap
     */
    mapping(uint256 => uint256) private _mintedToCarbonCreditAuctionBitmap;

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
     */
    constructor(
        address[] memory _gcaAgents,
        address _glowToken,
        address _governance,
        bytes32 _requirementsHash,
        address _earlyLiquidity,
        address _grcToken,
        address _carbonCreditAuction,
        address _vetoCouncil
    ) GCA(_gcaAgents, _glowToken, _governance, _requirementsHash) EIP712("GCA and MinerPool", "1") {
        _EARLY_LIQUIDITY = _earlyLiquidity;
        _CARBON_CREDIT_AUCTION = _carbonCreditAuction;
        _VETO_COUNCIL = _vetoCouncil;
        _setGRCToken(_grcToken, true, 0);
    }

    //************************************************************* */
    //***********  EXTERNAL/PUBLIC STATE CHANGING FUNCS    ******** */
    //************************************************************* */

    //----------------- ELECTRICITY FUTURE AUCTIONS -----------------//

    /**
     * @notice allows GCA's to create a new electricity future auction
     * @param grcToken - the address of the grc token to conduct the auction in
     * @param hash - the hash of the auction data
     *                         -   should be available off-chain
     * @param minimumBid - the minimum bid for the auction
     */
    function createElectricityFutureAuction(address grcToken, bytes32 hash, uint256 minimumBid) external {
        //TODO: need to add check if it's a valid grc token...
        if (!isGCA(msg.sender)) _revert(IGCA.CallerNotGCA.selector);
        //current time + 1 week
        uint64 endTime = uint64(block.timestamp + 604800);
        _electricityFutureAuctions[electricityFutureAuctionCount] = ElectricityFutureAuction({
            grcToken: grcToken,
            hash: hash,
            minimumBid: uint192(minimumBid),
            endTime: endTime,
            highestBid: 0,
            highestBidder: address(0)
        });
        emit IMinerPool.ElectricityFutureAuctionCreated(
            electricityFutureAuctionCount, grcToken, hash, minimumBid, endTime
        );
        ++electricityFutureAuctionCount;
    }

    /**
     * @notice entrypoint for an authorized bidder to bid on an electricity future auction
     * @param auctionId - the id of the auction
     * @param amount - the amount of the bid in the grc token of the auction
     * @param expiration - the expiration timestamp of the authorization signature in seconds
     * @param gca - the address of the gca that authorized the bidder
     *                 -   must be an active gca
     * @param signature - the signature of the authorization
     *                     -   the signature cannot be expired
     */
    function bidOnFuturesAuction(
        uint256 auctionId,
        uint256 amount,
        uint256 expiration,
        address gca,
        bytes calldata signature
    ) external {
        ElectricityFutureAuction memory auction = _electricityFutureAuctions[auctionId];
        if (block.timestamp > auction.endTime) {
            _revert(IMinerPool.ElectricityFuturesAuctionEnded.selector);
        }
        if (amount < auction.minimumBid) {
            _revert(IMinerPool.ElectricityFutureAuctionBidMustBeGreaterThanMinimumBid.selector);
        }
        if (amount < auction.highestBid) {
            _revert(IMinerPool.ElectricityFuturesAuctionBidTooLow.selector);
        }

        if (block.timestamp > expiration) {
            _revert(IMinerPool.ElectricityFuturesSignatureExpired.selector);
        }

        if (!isGCA(gca)) _revert(IMinerPool.SignerNotGCA.selector);

        bytes32 digest = _constructElectricityFutureAuctionDigest(msg.sender, expiration);
        if (!SignatureChecker.isValidSignatureNow(gca, digest, signature)) {
            _revert(IMinerPool.ElectricityFuturesAuctionInvalidSignature.selector);
        }

        IERC20 grcToken = IERC20(auction.grcToken);

        SafeERC20.safeTransferFrom(grcToken, msg.sender, address(this), amount);

        _electricityFutureAuctions[auctionId].highestBid = amount;
        _electricityFutureAuctions[auctionId].highestBidder = msg.sender;
        _addToCurrentBucket(auction.grcToken, amount);
        emit IMinerPool.FuturesBid(msg.sender, auctionId, amount);
    }

    //----------------- DONATIONS -----------------//

    //     TODO: token whitelist

    /**
     * @inheritdoc IMinerPool
     */
    function donateToGRCMinerRewardsPool(address grcToken, uint256 amount) external virtual {
        // if (!grcTracker[grcToken].isGRC) _revert(IMinerPool.NotGRCToken.selector);
        uint256 balBefore = IERC20(grcToken).balanceOf(address(this));
        SafeERC20.safeTransferFrom(IERC20(grcToken), msg.sender, address(this), amount);
        uint256 transferredBalance = IERC20(grcToken).balanceOf(address(this)) - balBefore;
        _addToCurrentBucket(grcToken, transferredBalance);
    }

    /**
     * @inheritdoc IMinerPool
     */
    function donateToGRCMinerRewardsPoolEarlyLiquidity(address grcToken, uint256 amount) external virtual {
        if (msg.sender != _EARLY_LIQUIDITY) _revert(IMinerPool.CallerNotEarlyLiquidity.selector);
        // if (!grcTracker[grcToken].isGRC) _revert(IMinerPool.NotGRCToken.selector);
        _addToCurrentBucket(grcToken, amount);
    }

    //----------------- CLAIMING -----------------//

    /**
     * @notice allows a user to claim their rewards for a bucket
     * @dev It's highly recommended to use a CLI or UI to call this function.
     *             - the proof can only be generated off-chain with access to the entire tree
     *             - furthermore, GRC tokens must be correctly input in order to receive rewards
     *             - the grc tokens should be kept on record off-chain.
     *             - failure to input all correct GRC Tokens will result in lost rewards
     * @param bucketId - the id of the bucket
     * @param glwWeight - the weight of the user's glw rewards
     * @param grcWeight - the weight of the user's grc rewards
     * @param proof - the merkle proof of the user's rewards
     *                     - the leaves are {payoutWallet, glwWeight, grcWeight}
     * @param index - the index of the report in the bucket
     *                     - that contains the merkle root where the user's rewards are stored
     * @param user - the address of the user
     *                   - TODO: make a wrapper contract that can loop through buckets
     *                   - OR: have an approved withdrawal address that can initiate the tx
     * @param grcTokens - the grc tokens to send to the user
     * @param claimFromInflation - whether or not to claim glow from inflation
     */
    function claimRewardMultipleRootsOneBucket(
        uint256 bucketId,
        uint256 glwWeight,
        uint256 grcWeight,
        bytes32[] calldata proof,
        uint256 index,
        address user,
        address[] memory grcTokens,
        bool claimFromInflation
    ) external {
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
        {
            uint256 userBitmap = _getUserBitmapForBucket(bucketId, user);
            userBitmap = _checkClaimAvailableAndReturnNewBitmap(bucketId, userBitmap);
            _setUserBitmapForBucket(bucketId, user, userBitmap);
        }
        uint256 globalStatePackedData = getPackedBucketGlobalState(bucketId);

        _handleMintToCarbonCreditAuction(bucketId, globalStatePackedData & _UINT128_MASK);
        // Vulnerability if user does not put in all the correct grc tokens
        {
            //no need to use a mask since totalGRCWeight uses the last 64 bits, so we can just shift
            uint256 totalGRCWeight = globalStatePackedData >> 192;

            for (uint256 i; i < grcTokens.length;) {
                uint256 amountInBucket = _getAmountForTokenAndInitIfNot(grcTokens[i], bucketId);
                //Just in case a faulty report is submitted, we need to choose the min of _glwWeight and totalGlwWeight
                // so that we don't overflow the available GRC rewards
                amountInBucket = amountInBucket * _min(grcWeight, totalGRCWeight) / totalGRCWeight;
                if (amountInBucket > 0) {
                    SafeERC20.safeTransfer(IERC20(grcTokens[i]), msg.sender, amountInBucket);
                }

                unchecked {
                    ++i;
                }
            }
        }
        {
            uint256 totalGlwWeight = globalStatePackedData >> 128 & _UINT64_MASK;
            //Just in case a faulty report is submitted, we need to choose the min of _glwWeight and totalGlwWeight
            // so that we don't overflow the available glow rewards
            uint256 amountGlowToSend = GLOW_REWARDS_PER_BUCKET * _min(glwWeight, totalGlwWeight) / totalGlwWeight;
            if (amountGlowToSend > 0) {
                SafeERC20.safeTransfer(IERC20(address(GLOW_TOKEN)), msg.sender, amountGlowToSend);
            }
        }
    }

    //----------------- BUCKET DELAY -----------------//

    /**
     * @notice allows a veto council member to delay the finalization of a bucket
     * @dev the bucket must already be initialized in order to be delayed
     * @dev the bucket cannot be finalized in order to be delayed
     * @dev the bucket can be delayed multiple times
     * @param bucketId - the id of the bucket to delay
     */
    function delayBucketFinalization(uint256 bucketId) external {
        if (isBucketFinalized(bucketId)) {
            _revert(IGCA.BucketAlreadyFinalized.selector);
        }

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

    //************************************************************* */
    //*************  PUBLIC/EXTERNAL VIEW FUNCTIONS   ************ */
    //************************************************************* */

    /**
     * @notice the early liquidity contract address
     * @return the early liquidity contract address
     */
    function earlyLiquidity() public view returns (address) {
        return _EARLY_LIQUIDITY;
    }

    function electricityFutureAuction(uint256 id) external view returns (ElectricityFutureAuction memory) {
        return _electricityFutureAuctions[id];
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
            //TODO: mint to the auction
            existingBitmap |= mask;
            _mintedToCarbonCreditAuctionBitmap[key] = existingBitmap;
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
    function _genesisTimestamp() internal view override(BucketSubmission) returns (uint256) {
        return GENESIS_TIMESTAMP;
    }

    /**
     * @dev used internally to construct the digest for the electricity future auction authorization
     * @param bidder - the address of the bidder
     * @param expiration - the expiration timestamp of the authorization
     * @return digest - the digest of the authorization
     */
    function _constructElectricityFutureAuctionDigest(address bidder, uint256 expiration)
        internal
        view
        returns (bytes32)
    {
        return _hashTypedDataV4(keccak256(abi.encode(ELECTRICITY_FUTURES_TYPEHASH, bidder, expiration)));
    }
}

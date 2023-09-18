// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {GCA} from "./GCA.sol";
import {IGCA} from "@/interfaces/IGCA.sol";
import {IGlow} from "@/interfaces/IGlow.sol";
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

    /// @notice the maximum length of an authorization
    /// @dev a signature can only last 16 weeks
    uint256 public constant MAX_AUTHORIZATION_LENGTH = uint256(7 days) * 16;

    /**
     * @notice the address of the early liquidity contract
     * @dev used for authorization in {donateToGRCMinerRewardsPoolEarlyLiquidity}
     */
    address private immutable _EARLY_LIQUIDITY;

    address private immutable _CARBON_CREDIT_AUCTION;

    /**
     * @notice the total amount of glow rewards available for farms per bucket
     */
    uint256 public constant GLOW_REWARDS_PER_BUCKET = 175_000 ether;

    //----------------- STATE VARIABLES -----------------//

    /**
     * @notice a counter for the electricity future auctions
     */
    uint256 public electricityFutureAuctionCount;

    uint256 private constant _BITS_IN_UINT = 256;

    //----------------- MAPPINGS -----------------//

    struct GRCTracker {
        uint248 firstAddedBucketId;
        bool isGRC;
    }

    mapping(uint256 => ElectricityFutureAuction) public electricityFutureAuctions;

    //Sharded ID -> user -> bitmap
    mapping(uint256 => mapping(address => uint256)) private _bucketClaimBitmap;

    mapping(uint256 => uint256) private _mintedToCarbonCreditAuctionBitmap;

    /**
     * @param grcToken - the address of the grc token
     * @param hash - the hash of the auction data
     * @param minimumBid - the minimum bid for the auction
     * @param endTime - the end time of the auction
     * @param highestBid - the highest bid for the auction
     * @param highestBidder - the highest bidder for the auction
     */
    struct ElectricityFutureAuction {
        address grcToken;
        bytes32 hash;
        uint64 minimumBid;
        uint64 endTime;
        uint256 highestBid;
        address highestBidder;
    }
    /**
     * @notice emitted when a GCA creates a new electricity future auction
     * @param id - the id of the auction
     * @param grcToken - the address of the grc token
     * @param hash - the hash of the auction data
     * @param minimumBid - the minimum bid for the auction
     * @param endTime - the end time of the auction
     */

    event ElectricityFutureAuctionCreated(
        uint256 indexed id, address grcToken, bytes32 hash, uint256 minimumBid, uint256 endTime
    );

    /**
     * @notice emitted when a new highest bid is placed on an electricity future auction
     * @param bidder - the address of the bidder
     * @param auctionId - the id of the auction
     * @param amount - the amount of the bid
     */
    event FuturesBid(address indexed bidder, uint256 indexed auctionId, uint256 amount);

    //----------------- CONSTRUCTOR -----------------//

    /**
     * @notice constructs a new GCA contract
     * @param _gcaAgents the addresses of the gca agents the contract starts with
     * @param _glowToken the address of the glow token
     * @param _governance the address of the governance contract
     * @param _requirementsHash the requirements hash of GCA Agents
     * @param _grcToken - the first grc token (USDC)
     */
    constructor(
        address[] memory _gcaAgents,
        address _glowToken,
        address _governance,
        bytes32 _requirementsHash,
        address _earlyLiquidity,
        address _grcToken,
        address _carbonCreditAuction
    ) GCA(_gcaAgents, _glowToken, _governance, _requirementsHash) EIP712("GCA and MinerPool", "1") {
        _EARLY_LIQUIDITY = _earlyLiquidity;
        _CARBON_CREDIT_AUCTION = _carbonCreditAuction;
        _setGRCToken(_grcToken, true, 0);
    }

    function createElectricityFutureAuction(ElectricityFutureAuction memory auctionData) external {
        if (!isGCA(msg.sender)) _revert(IGCA.CallerNotGCA.selector);
        electricityFutureAuctions[electricityFutureAuctionCount] = auctionData;
        emit ElectricityFutureAuctionCreated(
            electricityFutureAuctionCount,
            auctionData.grcToken,
            auctionData.hash,
            auctionData.minimumBid,
            auctionData.endTime
        );
        ++electricityFutureAuctionCount;
    }

    function bidOnFuturesAuction(
        uint256 auctionId,
        uint256 amount,
        uint256 expiration,
        address gca,
        bytes calldata signature
    ) external {
        ElectricityFutureAuction memory auction = electricityFutureAuctions[auctionId];
        if (block.timestamp > auction.endTime) {
            _revert(IMinerPool.ElectricityFuturesAuctionEnded.selector);
        }
        if (amount < auction.minimumBid) {
            _revert(IMinerPool.ElectricityFuturesAuctionBidTooLow.selector);
        }
        if (amount < auction.highestBid) {
            _revert(IMinerPool.ElectricityFuturesAuctionBidTooLow.selector);
        }
        //if block.timestamp > expiration then this will revert from underflow
        if (expiration - block.timestamp > MAX_AUTHORIZATION_LENGTH) {
            _revert(IMinerPool.ElectricityFuturesAuctionAuthorizationTooLong.selector);
        }
        if (!isGCA(gca)) _revert(IGCA.CallerNotGCA.selector);
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(ELECTRICITY_FUTURES_TYPEHASH, msg.sender, expiration)));
        if (!SignatureChecker.isValidSignatureNow(gca, digest, signature)) {
            _revert(IMinerPool.ElectricityFuturesAuctionInvalidSignature.selector);
        }

        IERC20 grcToken = IERC20(auction.grcToken);

        SafeERC20.safeTransferFrom(grcToken, msg.sender, address(this), amount);
        _addToCurrentBucket(auction.grcToken, amount);
    }

    function checkProof(
        address payoutWallet,
        uint256 glwWeight,
        uint256 grcWeight,
        bytes32[] calldata proof,
        bytes32 root
    ) internal {
        bytes32 leaf = keccak256(abi.encodePacked(payoutWallet, glwWeight, grcWeight));

        if (!MerkleProofLib.verifyCalldata(proof, root, leaf)) {
            _revert(IMinerPool.InvalidProof.selector);
        }
    }

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
            checkProof(user, glwWeight, grcWeight, proof, root);
        }
        {
            uint256 userBitmap = getUserBitmapForBucket(bucketId, user);
            userBitmap = checkClaimAvailableAndReturnNewBitmap(bucketId, userBitmap);
            setUserBitmapForBucket(bucketId, user, userBitmap);
        }
        uint256 globalStatePackedData = getPackedBucketGlobalState(bucketId);

        // Vulnerability if user does not put in all the correct grc tokens
        {
            //no need to use a mask since totalGRCWeight uses the last 64 bits, so we can just shift
            uint256 totalGRCWeight = globalStatePackedData >> 192;

            for (uint256 i; i < grcTokens.length;) {
                uint256 amountInBucket = getAmountForTokenAndInitIfNot(grcTokens[i], bucketId);
                amountInBucket = amountInBucket * grcWeight / totalGRCWeight;
                if (amountInBucket > 0) {
                    SafeERC20.safeTransfer(IERC20(grcTokens[i]), msg.sender, amountInBucket);
                }
                //TODO: Check Overflow on following ops.
                unchecked {
                    ++i;
                }
            }
        }
        {
            uint256 totalGlwWeight = globalStatePackedData >> 128 & _UINT64_MASK;
            uint256 amountGlowToSend = GLOW_REWARDS_PER_BUCKET * glwWeight / totalGlwWeight;
            if (amountGlowToSend > 0) {
                SafeERC20.safeTransfer(IERC20(address(GLOW_TOKEN)), msg.sender, amountGlowToSend);
            }
        }
    }

    function getUserBitmapForBucket(uint256 bucketId, address user) internal view returns (uint256) {
        return _bucketClaimBitmap[bucketId / _BITS_IN_UINT][user];
    }

    function _handleMintToCarbonCreditAuction(uint256 bucketId, uint256 amountToMint) internal {
        uint256 key = bucketId / _BITS_IN_UINT;
        uint256 existingBitmap = _mintedToCarbonCreditAuctionBitmap[key];
        uint256 shift = bucketId % bucketId;
        uint256 mask = 1 << shift;
        if (mask & existingBitmap == 0) {
            //TODO: mint to the auction
            existingBitmap |= mask;
            _mintedToCarbonCreditAuctionBitmap[key] = existingBitmap;
        }
    }

    function setUserBitmapForBucket(uint256 bucketId, address user, uint256 userBitmap) internal {
        _bucketClaimBitmap[bucketId / _BITS_IN_UINT][user] = userBitmap;
    }

    function checkClaimAvailableAndReturnNewBitmap(uint256 bucketId, uint256 userBitmap)
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

    //----------------- VIEW FUNCTIONS -----------------//

    //---------- HELPERS -----------//

    /**
     * @inheritdoc IMinerPool
     */
    function donateToGRCMinerRewardsPool(address grcToken, uint256 amount) external virtual {
        // if (!grcTracker[grcToken].isGRC) _revert(IMinerPool.NotGRCToken.selector);
        SafeERC20.safeTransferFrom(IERC20(grcToken), msg.sender, address(this), amount);
        _addToCurrentBucket(grcToken, amount);
    }

    /**
     * @inheritdoc IMinerPool
     */
    function donateToGRCMinerRewardsPoolEarlyLiquidity(address grcToken, uint256 amount) external virtual {
        if (msg.sender != _EARLY_LIQUIDITY) _revert(IMinerPool.CallerNotEarlyLiquidity.selector);
        // if (!grcTracker[grcToken].isGRC) _revert(IMinerPool.NotGRCToken.selector);
        _addToCurrentBucket(grcToken, amount);
    }

    function earlyLiquidity() public view returns (address) {
        return _EARLY_LIQUIDITY;
    }

    function _genesisTimestamp() internal view override(BucketSubmission) returns (uint256) {
        return GENESIS_TIMESTAMP;
    }
}

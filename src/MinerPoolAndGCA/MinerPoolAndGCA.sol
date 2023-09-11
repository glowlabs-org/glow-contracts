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

    //----------------- STATE VARIABLES -----------------//
    uint256 public electricityFutureAuctionCount;

    //----------------- MAPPINGS -----------------//

    struct GRCTracker {
        uint248 firstAddedBucketId;
        bool isGRC;
    }

    mapping(uint256 => ElectricityFutureAuction) public electricityFutureAuctions;

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
        address _grcToken
    ) GCA(_gcaAgents, _glowToken, _governance, _requirementsHash) EIP712("GCA and MinerPool", "1") {
        _EARLY_LIQUIDITY = _earlyLiquidity;
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

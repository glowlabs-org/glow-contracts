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
import "forge-std/console.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IHoldingContract} from "@/HoldingContract.sol";



contract MinerPoolAndGCA is GCA, EIP712, IMinerPool, BucketSubmission {
    //----------------- CONSTANTS -----------------//

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
     * @dev the amount to increase the finalization timestamp of a bucket by
     *             -   only veto council agents can delay a bucket.
     *             -   the delay is 13 weeks
     */
    uint256 private constant _BUCKET_DELAY_LENGTH = uint256(7 days) * 13;

    uint256 private constant _BITS_IN_UINT = 256;

    /**
     * @notice the total amount of glow rewards available for farms per bucket
     */
    uint256 public constant GLOW_REWARDS_PER_BUCKET = 175_000 ether;

    uint256 private constant _MAX_RESERVE_CURRENCIES = 3;

    uint256 public numReserveCurrencies;

    IHoldingContract public immutable HOLDING_CONTRACT;

    bytes32 public constant CLAIM_REWARD_FROM_BUCKET_TYPEHASH = keccak256(
        "ClaimRewardFromBucket(uint256 bucketId,uint256 glwWeight,uint256 grcWeight,uint256 index,address[] grcTokens,bool claimFromInflation)"
    );

    //----------------- MAPPINGS -----------------//

    //TODO: see if we use this in the getReward function from GCA.
    struct GRCTracker {
        uint248 firstAddedBucketId;
        bool isGRC;
    }

    /**
     * @dev a mapping of (bucketId / 256) -> user  -> address -> bitmap
     */
    mapping(uint256 => mapping(address => mapping(address => uint256))) private _bucketClaimBitmap;

    /**
     * @dev a mapping of (bucketId / 256) -> user -> bitmap
     */
    mapping(uint256 => uint256) private _mintedToCarbonCreditAuctionBitmap;

    /**
     * @dev a mapping of (bucketId / 256) -> -user -> bitmap
     * @dev a bucket can only be delayed once
     */
    mapping(uint256 => uint256) private _bucketDelayedBitmap;

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
        address _carbonCreditAuction,
        address _vetoCouncil,
        address _holdingContract
    ) GCA(_gcaAgents, _glowToken, _governance, _requirementsHash) EIP712("GCA and MinerPool", "1") {
        _EARLY_LIQUIDITY = _earlyLiquidity;
        _CARBON_CREDIT_AUCTION = _carbonCreditAuction;
        _VETO_COUNCIL = _vetoCouncil;
        _setGRCToken(_grcToken, true, 0);
        HOLDING_CONTRACT = IHoldingContract(_holdingContract);
        HOLDING_CONTRACT.setMinerPool(address(this));
        ++numReserveCurrencies;
    }

    //************************************************************* */
    //***********  EXTERNAL/PUBLIC STATE CHANGING FUNCS    ******** */
    //************************************************************* */

    //----------------- DONATIONS -----------------//

    /**
     * @inheritdoc IMinerPool
     */
    function editReserveCurrencies(address oldReserveCurrency, address newReserveCurrency) external returns (bool) {
        if (msg.sender != GOVERNANCE) _revert(IGCA.CallerNotGovernance.selector);

        uint256 numCurrenciesToAdd = _isZeroAddress(newReserveCurrency) ? 0 : 1;
        uint256 numCurrenciesToRemove = _isZeroAddress(oldReserveCurrency) ? 0 : 1;

        uint256 _numReserveCurrencies = numReserveCurrencies;

        //Need to handle the case where we could get an underflow revert
        if (_numReserveCurrencies == 0) {
            //We can't remove a currency if there are no currencies
            if (numCurrenciesToRemove > 0) {
                return false;
            }
        }

        _numReserveCurrencies = (_numReserveCurrencies + numCurrenciesToAdd) - numCurrenciesToRemove;
        if (_numReserveCurrencies > _MAX_RESERVE_CURRENCIES) {
            return false;
        }

        uint256 _currentBucket = currentBucket();
        //If we're not dealing with the zero address,
        // then we add the new currency to the current bucket
        if (numCurrenciesToAdd > 0) {
            if (!_setGRCToken(newReserveCurrency, true, _currentBucket)) {
                return false;
            }
        }

        //if we're not dealing with the zero address,
        // then we remove the old currency from the current bucket
        if (numCurrenciesToRemove > 0) {
            if (!_setGRCToken(oldReserveCurrency, false, _currentBucket)) {
                return false;
            }
        }
        numReserveCurrencies = _numReserveCurrencies;
        //emit an event
        return true;
    }

    /**
     * @inheritdoc IMinerPool
     */
    function donateToGRCMinerRewardsPool(address grcToken, uint256 amount) external virtual {
        // if (!grcTracker[grcToken].isGRC) _revert(IMinerPool.NotGRCToken.selector);
        uint256 balBefore = IERC20(grcToken).balanceOf(address(HOLDING_CONTRACT));
        SafeERC20.safeTransferFrom(IERC20(grcToken), msg.sender, address(HOLDING_CONTRACT), amount);
        uint256 transferredBalance = IERC20(grcToken).balanceOf(address(HOLDING_CONTRACT)) - balBefore;
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
    function claimRewardFromBucket(
        uint256 bucketId,
        uint256 glwWeight,
        uint256 grcWeight,
        bytes32[] calldata proof,
        uint256 index,
        address user,
        address[] memory grcTokens,
        bool claimFromInflation,
        bytes memory signature
    )
        //todo: add nonce to claim sig?
        external
    {
        if (msg.sender != user) {
            bytes32 hash =
                createClaimRewardFromBucketDigest(bucketId, glwWeight, grcWeight, index, grcTokens, claimFromInflation);
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

        _handleMintToCarbonCreditAuction(bucketId, globalStatePackedData & _UINT128_MASK);
        // Vulnerability if user does not put in all the correct grc tokens
        {
            //no need to use a mask since totalGRCWeight uses the last 64 bits, so we can just shift
            uint256 totalGRCWeight = globalStatePackedData >> 192;
            for (uint256 i; i < grcTokens.length;) {
                {
                    address token = grcTokens[i];
                    uint256 userBitmap = _getUserBitmapForBucket(bucketId, user, token);
                    userBitmap = _checkClaimAvailableAndReturnNewBitmap(bucketId, userBitmap);
                    _setUserBitmapForBucket(bucketId, user, token, userBitmap);
                }

                //Just in case a faulty report is submitted, we need to choose the min of _glwWeight and totalGlwWeight
                // so that we don't overflow the available GRC rewards
                // and grab rewards from other buckets
                uint256 amountInBucket = _getAmountForTokenAndInitIfNot(grcTokens[i], bucketId);
                amountInBucket = amountInBucket * _min(grcWeight, totalGRCWeight) / totalGRCWeight;
                if (amountInBucket > 0) {
                    HOLDING_CONTRACT.addHolding(user, grcTokens[i], uint192(amountInBucket));
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
                SafeERC20.safeTransfer(IERC20(address(GLOW_TOKEN)), user, amountGlowToSend);
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

    //************************************************************* */
    //*************  PUBLIC/EXTERNAL VIEW FUNCTIONS   ************ */
    //************************************************************* */

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

    function createClaimRewardFromBucketDigest(
        uint256 bucketId,
        uint256 glwWeight,
        uint256 grcWeight,
        uint256 index,
        address[] memory grcTokens,
        bool claimFromInflation
    ) public view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                _domainSeparatorV4(),
                keccak256(
                    abi.encode(
                        CLAIM_REWARD_FROM_BUCKET_TYPEHASH,
                        bucketId,
                        glwWeight,
                        grcWeight,
                        index,
                        keccak256(abi.encodePacked(grcTokens)),
                        claimFromInflation
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
    function _setUserBitmapForBucket(uint256 bucketId, address user, address token, uint256 userBitmap) internal {
        _bucketClaimBitmap[bucketId / _BITS_IN_UINT][user][token] = userBitmap;
    }

    function bucketClaimBitmap(uint256 bucketId, address user, address token) public view returns (uint256) {
        return _getUserBitmapForBucket(bucketId, user, token);
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
    function _getUserBitmapForBucket(uint256 bucketId, address user, address token) internal view returns (uint256) {
        return _bucketClaimBitmap[bucketId / _BITS_IN_UINT][user][token];
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
     * @dev efficient checker for whether an address is the zero address
     * @param addr the address to check
     * @return res - whether or not the address is the zero address
     */
    function _isZeroAddress(address addr) internal pure returns (bool res) {
        assembly {
            res := iszero(addr)
        }
    }
}

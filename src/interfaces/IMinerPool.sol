// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IMinerPool {
    /* -------------------------------------------------------------------------- */
    /*                                   errors                                    */
    /* -------------------------------------------------------------------------- */
    error ElectricityFuturesSignatureExpired();
    error ElectricityFuturesAuctionEnded();
    error ElectricityFuturesAuctionBidTooLow();
    error ElectricityFuturesAuctionAuthorizationTooLong();
    error ElectricityFuturesAuctionInvalidSignature();
    error ElectricityFutureAuctionBidMustBeGreaterThanMinimumBid();
    error CallerNotEarlyLiquidity();
    error NotUSDCToken();
    error InvalidProof();
    error UserAlreadyClaimed();
    error AlreadyMintedToCarbonCreditAuction();
    error BucketNotFinalized();
    error CallerNotVetoCouncilMember();
    error CannotDelayEmptyBucket();
    error CannotDelayBucketThatNeedsToUpdateSlashNonce();
    error BucketAlreadyDelayed();
    error SignerNotGCA();
    error SignatureDoesNotMatchUser();
    error GlowWeightOverflow();
    error USDCWeightOverflow();
    error GlowWeightGreaterThanTotalWeight();
    error USDCWeightGreaterThanTotalWeight();

    /* -------------------------------------------------------------------------- */
    /*                                     state-changing                        */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice Allows anyone to donate USDC into the miner USDC rewards pool
     * @notice the amount is split across 192 weeks starting at the current week + 16
     * @param amount -  amount to deposit
     */
    function donateToUSDCMinerRewardsPool(uint256 amount) external;

    /**
     * @notice Allows the early liquidity to donate USDC into the miner USDC rewards pool
     * @notice the amount is split across 192 weeks starting at the current week + 16
     * @dev the USDC token must be a valid USDC token
     * @dev early liquidity will safeTransfer from the user to the miner pool
     *     -   and then call this function directly.
     *     -   we do this to prevent extra transfers.
     * @param amount -  amount to deposit
     */
    function donateToUSDCMinerRewardsPoolEarlyLiquidity(uint256 amount) external;

    /**
     * @notice allows a user to claim their rewards for a bucket
     * @dev It's highly recommended to use a CLI or UI to call this function.
     *             - the proof can only be generated off-chain with access to the entire tree
     *             - furthermore, USDC tokens must be correctly input in order to receive rewards
     *             - the USDC tokens should be kept on record off-chain.
     *             - failure to input all correct USDC Tokens will result in lost rewards
     * @param bucketId - the id of the bucket
     * @param glwWeight - the weight of the user's glw rewards
     * @param USDCWeight - the weight of the user's USDC rewards
     * @param proof - the merkle proof of the user's rewards
     *                     - the leaves are {payoutWallet, glwWeight, USDCWeight}
     * @param index - the index of the report in the bucket
     *                     - that contains the merkle root where the user's rewards are stored
     * @param user - the address of the user
     * @param claimFromInflation - whether or not to claim glow from inflation
     * @param signature - the eip712 signature that allows a relayer to execute the action
     *               - to claim for a user.
     *               - the relayer is not able to access rewards under any means
     *               - rewards are always sent to the {user}
     */
    function claimRewardFromBucket(
        uint256 bucketId,
        uint256 glwWeight,
        uint256 USDCWeight,
        bytes32[] calldata proof,
        uint256 index,
        address user,
        bool claimFromInflation,
        bytes memory signature
    ) external;

    /**
     * @notice allows a veto council member to delay the finalization of a bucket
     * @dev the bucket must already be initialized in order to be delayed
     * @dev the bucket cannot be finalized in order to be delayed
     * @dev the bucket can be delayed multiple times
     * @param bucketId - the id of the bucket to delay
     */
    function delayBucketFinalization(uint256 bucketId) external;

    /* -------------------------------------------------------------------------- */
    /*                                   view                                    */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice returns true if a bucket has been delayed
     * @param bucketId - the id of the bucket
     * @return true if the bucket has been delayed
     */
    function hasBucketBeenDelayed(uint256 bucketId) external view returns (bool);

    /**
     * @notice returns the bytes32 digest of the claim reward from bucket message
     * @param bucketId - the id of the bucket
     * @param glwWeight - the weight of the user's glw rewards in the leaf of the report root
     * @param USDCWeight - the weight of the user's USDC rewards in the leaf of the report root
     * @param index - the index of the report in the bucket
     *                     - that contains the merkle root where the user's rewards are stored
     * @param claimFromInflation - whether or not to claim glow from inflation
     * @return the bytes32 digest of the claim reward from bucket message
     */
    function createClaimRewardFromBucketDigest(
        uint256 bucketId,
        uint256 glwWeight,
        uint256 USDCWeight,
        uint256 index,
        bool claimFromInflation
    ) external view returns (bytes32);
}

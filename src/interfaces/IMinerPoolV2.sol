// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IMinerPoolV2 {
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
    error InvalidUserProof();
    error InvalidTokensProof();
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
     * @notice Allows anyone to donate any erc20 into the miner token rewards pool
     * @notice the amount is split across 192 weeks starting at the current week + 16
     * @param token - the erc20 token to donate
     * @param amount -  amount to deposit
     */
    function donateTokenToMinerRewardsPool(address token, uint256 amount) external;

    /**
     * @notice Allows the early liquidity to donate an erc20 into the miner token rewards pool
     * @notice the amount is split across 192 weeks starting at the current week + 16
     * @dev early liquidity will safeTransfer from the user to the miner pool
     *     -   and then call this function directly.
     *     -   we do this to prevent extra transfers.
     * @param token - the erc20 token to donate
     * @param amount -  amount to deposit
     */
    function donateTokenToRewardsPoolEarlyLiquidity(address token, uint256 amount) external;

    /**
     * @notice allows a user to claim their rewards for a bucket
     * @dev It's highly recommended to use a CLI or UI to call this function.
     *             - the proof can only be generated off-chain with access to the entire tree
     *             - furthermore, USDC tokens must be correctly input in order to receive rewards
     *             - the USDC tokens should be kept on record off-chain.
     *             - failure to input all correct USDC Tokens will result in lost rewards
     * @param bucketId - the id of the bucket
     * @param glwWeight - the weight of the user's glw rewards
     * @param usdcWeight - the weight of the user's USDC rewards
     * @param proof - the merkle proof that the user's rewards are stored in the bucket
     * @param flags - the flags used in the multi-merkle proof
     * @param tokens - the addresses of the payout tokens
     * @param index - the index of the report in the bucket
     *                     - that contains the merkle root where the user's rewards are stored
     */
    function claimRewardFromBucket(
        uint256 bucketId,
        uint256 glwWeight,
        uint256 usdcWeight,
        bytes32[] memory proof,
        bool[] memory flags,
        address[] memory tokens,
        uint256 index,
        bool claimFromInflation
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
}

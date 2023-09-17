interface IMinerPool {
    //----------------- ERRORS -----------------//
    error ElectricityFuturesSignatureExpired();
    error ElectricityFuturesAuctionEnded();
    error ElectricityFuturesAuctionBidTooLow();
    error ElectricityFuturesAuctionAuthorizationTooLong();
    error ElectricityFuturesAuctionInvalidSignature();
    error CallerNotEarlyLiquidity();
    error NotGRCToken();
    error InvalidProof();
    error UserAlreadyClaimed();
    error AlreadyMintedToCarbonCreditAuction();
    error BucketNotFinalized();

    /**
     * @notice Allows anyone to donate GRC into the miner grc rewards pool
     * @notice the amount is split across 192 weeks starting at the current week + 16
     * @dev the grc token must be a valid grc token
     * @param grcToken - the token to deposit
     * @param amount -  amount to deposit
     */
    function donateToGRCMinerRewardsPool(address grcToken, uint256 amount) external;

    /**
     * @notice Allows the early liquidity to donate GRC into the miner grc rewards pool
     * @notice the amount is split across 192 weeks starting at the current week + 16
     * @dev the grc token must be a valid grc token
     * @dev early liquidity will safeTransfer from the user to the miner pool
     *     -   and then call this function directly.
     *     -   we do this to prevent extra transfers.
     * @param grcToken - the token to deposit
     * @param amount -  amount to deposit
     */
    function donateToGRCMinerRewardsPoolEarlyLiquidity(address grcToken, uint256 amount) external;
}

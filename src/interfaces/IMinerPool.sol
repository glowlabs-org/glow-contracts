interface IMinerPool {
    //----------------- ERRORS -----------------//
    error ElectricityFuturesSignatureExpired();
    error ElectricityFuturesAuctionEnded();
    error ElectricityFuturesAuctionBidTooLow();
    error ElectricityFuturesAuctionAuthorizationTooLong();
    error ElectricityFuturesAuctionInvalidSignature();
    error ElectricityFutureAuctionBidMustBeGreaterThanMinimumBid();
    error CallerNotEarlyLiquidity();
    error NotGRCToken();
    error InvalidProof();
    error UserAlreadyClaimed();
    error AlreadyMintedToCarbonCreditAuction();
    error BucketNotFinalized();
    error CallerNotVetoCouncilMember();
    error CannotDelayEmptyBucket();
    error CannotDelayBucketThatNeedsToUpdateSlashNonce();
    error BucketAlreadyDelayed();
    error SignerNotGCA();

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
        uint192 minimumBid;
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
}

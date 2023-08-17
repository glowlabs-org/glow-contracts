interface IMinerPool {
    //----------------- ERRORS -----------------//
    error ElectricityFuturesSignatureExpired();
    error ElectricityFuturesAuctionEnded();
    error ElectricityFuturesAuctionBidTooLow();
    error ElectricityFuturesAuctionAuthorizationTooLong();
    error ElectricityFuturesAuctionInvalidSignature();
}

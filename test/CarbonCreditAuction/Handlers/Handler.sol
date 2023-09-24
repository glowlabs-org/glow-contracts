// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdCheats.sol";
import "forge-std/console.sol";
import {ICarbonCreditAuction} from "@/interfaces/ICarbonCreditAuction.sol";
import {CCC} from "@/CCC.sol";

contract Handler is Test {
    CCC public auction;
    uint256 public iterations;

    constructor(address _auction) payable {
        auction = CCC(_auction);
    }

    function bid(uint96 bid, uint96 bidAmount) external {
        uint256 nextMinimumBid = auction.getNextBidPrice();
        bidAmount = uint96(bound(bidAmount, nextMinimumBid, bidAmount));
        auction.bid(bid, 0, 0, bidAmount);
        ++iterations;
    }
}

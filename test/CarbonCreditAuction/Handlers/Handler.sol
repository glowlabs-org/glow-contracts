// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdCheats.sol";
import "forge-std/console.sol";
import {ICarbonCreditAuction} from "@/interfaces/ICarbonCreditAuction.sol";
import {CCC} from "@/CCC.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract Handler is Test {
    CCC public auction;
    uint256 public iterations;
    mapping(uint256 => bool) public bidAmountTaken;
    uint32 private constant NULL = type(uint32).max;

    constructor(address _auction) payable {
        auction = CCC(_auction);
    }

    function bid(uint96 bid, uint96 bidAmount) external {
        uint256 nextMinimumBid = auction.getNextBidPrice();
        bidAmount = uint96(bound(bidAmount, nextMinimumBid, nextMinimumBid));
        while (bidAmountTaken[bidAmount]) {
            ++bidAmount;
        }
        bidAmountTaken[bidAmount] = true;
        bid = uint96(bound(bid, 1, 1000 * 1e18));
        auction.bid(bid, 0, 0, bidAmount);
        ++iterations;
    }
}

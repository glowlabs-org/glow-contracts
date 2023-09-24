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
        bidAmount = uint96(bound(bidAmount, nextMinimumBid, type(uint96).max / 2));

        while (bidAmountTaken[bidAmount]) {
            ++bidAmount;
        }
        bidAmountTaken[bidAmount] = true;
        // vm.writeLine(
        //     "./test/CarbonCreditAuction/data.txt",
        //     string(abi.encodePacked("maxPrice =  ", Strings.toString(uint256(bidAmount))))
        // );
        // vm.writeLine(
        //     "./test/CarbonCreditAuction/data.txt",
        //     string(abi.encodePacked("iteration =  ", Strings.toString(uint256(iterations))))
        // );
        auction.bid(bid, 0, 0, bidAmount);
        ++iterations;
    }

    function calculateStuffSimon() public {
        uint256 head = auction.pointers().head;
        if (head == NULL) return;
        auction.close();
        uint256 closingPrice = auction.closingPrice();
        uint256 totalOwed;
        // vm.writeLine("./test/CarbonCreditAuction/data.txt",
        // string(abi.encodePacked("closing price: ",Strings.toString(closingPrice))));

        while (head != NULL) {
            CCC.Bid memory bid = auction.bids(head);
            if (bid.maxPrice < closingPrice) break;
            totalOwed += auction.amountOwed(head);
            head = bid.prev;
        }

        string memory strToWrite = string(abi.encodePacked("total to close at =", Strings.toString(uint256(totalOwed))));
        vm.writeLine("./test/CarbonCreditAuction/data.txt", strToWrite);

        vm.writeLine(
            "./test/CarbonCreditAuction/data.txt",
            string(abi.encodePacked("iteration =  ", Strings.toString(uint256(iterations))))
        );
    }
}

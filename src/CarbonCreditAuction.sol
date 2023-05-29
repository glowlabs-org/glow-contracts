// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract GlowCarbonCreditAuction {
    IERC20 immutable GLW;
    IERC20 immutable GCC;

    uint256 public totalAuctionedGLW;
    uint256 public totalGCC;
    uint256 public currentClearingPrice;
    // Define the bid struct

    struct Bid {
        uint256 amount;
        address bidder;
        uint256 next; // points to the next bid in the list
        uint256 prev; // points to the previous bid in the list
    }

    // Define the linked list struct
    struct LinkedList {
        uint256 head; // head of the list
        uint256 tail; // tail of the list
        mapping(uint256 => Bid) bids; // stores all the bids
        uint256 minBid; // the minimum acceptable bid
    }

    LinkedList public linkedList;

    constructor(address _glw, address _gcc) {
        GLW = IERC20(_glw);
        GCC = IERC20(_gcc);
    }

    function placeBid(uint256 bidAmount, uint256 position, uint256 maxPrice) public {
        require(bidAmount > linkedList.minBid, "Bid is too low");
        require(GLW.balanceOf(msg.sender) >= bidAmount, "Insufficient GLW balance");
        require(GLW.allowance(msg.sender, address(this)) >= bidAmount, "Not enough GLW allowance");

        // Transfer GLW from bidder to the contract
        GLW.transferFrom(msg.sender, address(this), bidAmount);
        totalAuctionedGLW += bidAmount;

        // Create the new bid
        Bid memory newBid;
        newBid.amount = bidAmount;
        newBid.bidder = msg.sender;

        // Initialize current and previous bids
        Bid storage currentBid = linkedList.bids[position];

        // Check if the new bid should actually go before the current bid
        // If not, find the correct position
        while (position < totalAuctionedGLW && (newBid.amount / totalGCC) < currentBid.amount) {
            position = currentBid.next;
            currentBid = linkedList.bids[position];
        }

        // Insert the new bid at the correct position
        newBid.next = currentBid.next;
        newBid.prev = position;
        linkedList.bids[newBid.next].prev = position;
        currentBid.next = position;

        // Add the new bid to the mapping
        linkedList.bids[position] = newBid;

        // If the bid is at the end of the list, update the tail
        if (newBid.next == 0) {
            linkedList.tail = position;
        }

        // Calculate new clearing price
        uint256 newClearingPrice = totalAuctionedGLW / totalGCC;

        // Check if new clearing price is greater than current
        if (newClearingPrice > currentClearingPrice) {
            // Update clearing price
            currentClearingPrice = newClearingPrice;

            // Delete all bids below new clearing price
            while (linkedList.minBid < currentClearingPrice && linkedList.tail != 0) {
                removeLowestBid();
            }
        }

        // Update the minimum acceptable bid to the new lowest bid in the list
        linkedList.minBid = linkedList.bids[linkedList.tail].amount;
    }

    function removeLowestBid() private {
        // Get the lowest bid
        Bid storage lowestBid = linkedList.bids[linkedList.tail];

        // Update the tail to the previous bid in the list
        linkedList.tail = lowestBid.prev;

        // Check if the list is now empty
        if (linkedList.tail != 0) {
            // Update the next of the new tail
            linkedList.bids[linkedList.tail].next = 0;
        }

        // Return GLW to the bidder
        GLW.transfer(lowestBid.bidder, lowestBid.amount);
        totalAuctionedGLW -= lowestBid.amount;

        // Delete the lowest bid
        delete linkedList.bids[linkedList.tail];

        // Update the minimum acceptable bid to the new lowest bid in the list
        if (linkedList.tail != 0) {
            linkedList.minBid = linkedList.bids[linkedList.tail].amount;
        } else {
            linkedList.minBid = 0;
        }
    }
}

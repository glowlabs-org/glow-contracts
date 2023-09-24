// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {ICarbonCreditAuction} from "@/interfaces/ICarbonCreditAuction.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
//TEMP!
import "forge-std/console.sol";

contract CCC is ICarbonCreditAuction {
    uint256 public constant MIN_BID = 1 ether;
    uint256 public constant INCREASE_BID_PERCENTAGE = 10;
    uint256 private constant _DENOMINATOR = 100;
    uint32 private constant _NULL = type(uint32).max;
    uint256 public constant GCC_IN_AUCTION = 1000 ether;

    uint256 public bidCount;
    uint256 public currentHighestBid;
    Pointers private _pointers;

    uint256 public closingPrice;

    struct Pointers {
        uint32 head;
        uint32 tail;
    }

    struct Bid {
        address bidder;
        uint96 maxPrice;
        uint32 prev;
        uint32 next;
        uint96 bidAmount;
    }

    mapping(uint256 => Bid) private _bids;

    constructor() {
        _pointers.head = _NULL;
        _pointers.tail = _NULL;
    }

    /// @inheritdoc ICarbonCreditAuction
    function receiveGCC(uint256 amount) external override {
        return;
    }

    //TODO: finish calculating the closing price
    // take into account partial fills  and how to handle those
    // take into account the other edge cases where there are not enough bids
    // also remember to make sure that the bid is a minimum bid sothat users can bid as much glow as they want
    // include rfunds
    function close() external {
        uint256 gccSoldCounter;
        uint256 head = _pointers.head;
        Bid memory highestBid = _bids[head];
        uint256 price = highestBid.maxPrice;

        //10 GLOW / 10 GLOW / GCC = 1 GCC
        //10 GLOW / (.5 GLOW / GCC) = 20
        uint256 amount = (uint256(highestBid.bidAmount) * 1e18) / uint256(highestBid.maxPrice);
        gccSoldCounter = amount;
        head = highestBid.prev;

        while (head != _NULL) {
            Bid memory bid = _bids[head];

            gccSoldCounter = (uint256(gccSoldCounter) * uint256(price)) / bid.maxPrice;

            if (gccSoldCounter > GCC_IN_AUCTION) {
                console.log("gcc sold counter inside loop", gccSoldCounter);
                console.log("gcc in auction inside loop", GCC_IN_AUCTION);
                console.log("should be here");

                //If the next lowest price causes an overflow in the total gcc we will sell
                //that means that the current bid we're iterating on doesen't fit in the winning bids
                //so we need to manually calculate the closing price.
                //For example, if there are 1000 GCC to sell and we have sold 600 at a price of 2 GLW / GCC
                //If the next lowest bid is 1 GLW / GCC  the total sold will be 1200 since we have to multiply everbody's bid by 2
                //That means that there can be no partial fill for the current bid that's getting iterated
                //Therefore, we need to find the price that would close the auction at 1000
                //We can derive the price by reconstructing the formula
                //totalGCCSoldReservedInIterations = gccSoldCounter * price / newPrice
                //Restructure this and the new price that sells all the gcc in the auction is
                //newPrice = gccSoldCounter * price / Total GCC In Auction
                //In the example above, we want totalGCCSoldReservedInIterations = Total GCC In Auction = 1000
                //So if we hae sold 600, and we want
                //1000 = 600 * 2 / newPrice
                //newPrice = (600*2)/1000
                //newPrice = 1.2
                //Let's double verify
                //600 * 2 / 1.2 = 1000
                price = gccSoldCounter * price / GCC_IN_AUCTION;
                gccSoldCounter = GCC_IN_AUCTION;
                break;
            }
            uint256 amount = (uint256(bid.bidAmount) * 1e18) / uint256(bid.maxPrice);
            gccSoldCounter += amount;
            price = bid.maxPrice;

            //If we make it here, that means that there needs to be a partial fill on the bid.
            /**
             * For example, let's say we have sold 400 out of 1000 tokens
             *             while in this loop at a price of 2 GLW / GCC.
             *             The newest price in this iteration is 1 GLW / GCC
             *             which makes the total sold 800 / 1000
             *             Now, let's say the current bid was for 300 GLOW Tokens
             *             That would mean that we sold 1100 / 1000 tokens.
             *             We can't do that, we need to partial fill so that we sell exactly 1000 tokens.
             *             That means we need to make the following changes
             *             currentBidAmount = originalBidAmount / price
             */

            if (gccSoldCounter > GCC_IN_AUCTION) {
                //gcc sold counter is 1100
                //our bid gets us 300 glow at let's say price = 1
                //so we need to find what amount at current price gets us down
                //to 1000
                //so we solve for teh equation
                //gccSoldCounter (GCC) - price(GLW/GCC) * x = total gcc in auction
                //let's say finishing price is .5
                //100 = x / .5
                //x = 200
                //because 200 glw gets us 100 gcc

                // amountOverflow is in terms of GCC
                uint256 amountOverflow = gccSoldCounter - GCC_IN_AUCTION;

                // Now, you need to adjust the last bid's amount to reduce this overflow.
                // Suppose the last bid was at a price of `price` GLOW/GCC.
                // The bid amount in terms of GCC can be calculated as: bidAmountGcc = bidAmountGlow / price
                // We need to reduce this bidAmountGcc by amountOverflow, so:
                // newBidAmountGcc = bidAmountGcc - amountOverflow
                // Converting this back to GLOW: newBidAmountGlow = newBidAmountGcc * price

                // Calculate the new bid amount in terms of GCC.
                uint256 bidAmountGcc = (uint256(bid.bidAmount) * 1e18) / price; // assuming bid.bidAmount is in GLOW and price is in GLOW/GCC
                uint256 newBidAmountGcc = bidAmountGcc > amountOverflow ? bidAmountGcc - amountOverflow : 0;

                // Convert the new bid amount back to GLOW.
                uint256 newBidAmount = (newBidAmountGcc * price) / 1e18; // converting back to GLOW

                //Send glow back to user
                _bids[head].bidAmount = uint96(newBidAmount);
                gccSoldCounter = GCC_IN_AUCTION;
                break;
            }

            if (gccSoldCounter == GCC_IN_AUCTION) {
                break;
            }
            head = bid.prev;
        }
        //Handle not enough bids case.
        if (gccSoldCounter < GCC_IN_AUCTION) {
            price = (price * gccSoldCounter) / GCC_IN_AUCTION;
        }

        closingPrice = price;
    }

    function getNextBidPrice() public view returns (uint256) {
        uint256 _currentHighestBid = currentHighestBid;
        if (_currentHighestBid == 0) return MIN_BID;
        return _currentHighestBid * (100 + INCREASE_BID_PERCENTAGE) / _DENOMINATOR;
    }

    function amountOwed(uint256 bidId) public view returns (uint256) {
        uint256 amountInBid = _bids[bidId].bidAmount;
        return amountInBid * 1e18 / closingPrice;
    }

    function bid(uint256 maxPrice, uint32 prev, uint32 next, uint256 amountToBid) external payable {
        uint256 _bidCount = bidCount++;

        // Ensure the provided bid amount meets the required minimum
        uint256 amountRequired = getNextBidPrice();
        if (amountToBid < amountRequired) revert("Amount Required");
        currentHighestBid = amountRequired;
        // require(msg.value == amountRequired, "Bid amount is too low.");

        if (_bidCount == 0) {
            // If no bids have been placed yet
            _bids[0] = Bid({
                bidder: msg.sender,
                maxPrice: uint96(maxPrice),
                prev: _NULL,
                next: _NULL,
                bidAmount: uint96(amountToBid)
            });
            _pointers.head = 0;
            _pointers.tail = 0;
        } else {
            Pointers memory __pointers = _pointers;
            Bid memory nextBid = _bids[next];

            if (next == _NULL) {
                next = __pointers.head;
            }
            if (prev == _NULL) {
                prev = __pointers.tail;
            }
            if (next > _bidCount) {
                _revert(ICarbonCreditAuction.NextNotInList.selector);
            }
            if (prev > _bidCount) {
                _revert(ICarbonCreditAuction.PrevNotInList.selector);
            }

            while (true) {
                if (maxPrice < nextBid.maxPrice) {
                    prev = nextBid.prev;
                    if (prev == _NULL) {
                        prev = __pointers.tail;
                    }
                    Bid memory lastBid = _bids[prev];
                    while (true) {
                        if (lastBid.maxPrice <= maxPrice) {
                            break;
                        }
                        if (lastBid.prev == _NULL) {
                            _pointers.tail = uint32(_bidCount);
                            _bids[prev].prev = uint32(_bidCount);
                            _bids[_bidCount] = Bid({
                                bidder: msg.sender,
                                maxPrice: uint96(maxPrice),
                                prev: _NULL,
                                next: prev,
                                bidAmount: uint96(amountToBid)
                            });
                            return;
                        }
                        next = prev;
                        prev = lastBid.prev;
                        lastBid = _bids[prev];

                        // printBid(prev);
                    }

                    break;
                }

                if (nextBid.next == _NULL) {
                    _bids[next].next = uint32(_bidCount);
                    _pointers.head = uint32(_bidCount);
                    _bids[_bidCount] = Bid({
                        bidder: msg.sender,
                        maxPrice: uint96(maxPrice),
                        prev: next,
                        next: _NULL,
                        bidAmount: uint96(amountToBid)
                    });
                    return;
                }

                // if(maxPrice)

                next = nextBid.next;
                nextBid = _bids[next];
            }

            Bid memory lastBid = _bids[nextBid.prev];

            _bids[next].prev = uint32(_bidCount);
            _bids[prev].next = uint32(_bidCount);
            _bids[_bidCount] = Bid({
                bidder: msg.sender,
                maxPrice: uint96(maxPrice),
                prev: prev,
                next: next,
                bidAmount: uint96(amountToBid)
            });
            //
        }
    }

    function bids(uint256 id) external view returns (Bid memory) {
        return _bids[id];
    }

    function printBid(uint32 id) public {
        console.logString("--------------------");
        Bid memory bid = _bids[id];
        console.log("id %s:", id);
        console.log("max price", bid.maxPrice);
        console.log("bidder", bid.bidder);
        console.log("prev", bid.prev);
        console.log("next", bid.next);
        console.logString("--------------------");
    }

    function pointers() external view returns (Pointers memory) {
        return _pointers;
    }

    struct ListResponse {
        uint256 id;
        uint256 value;
    }

    function constructSortedList() external view returns (ListResponse[] memory) {
        ListResponse[] memory list = new ListResponse[](bidCount);

        uint32 next = _pointers.tail;
        uint32 i = 0;
        while (next != _NULL) {
            Bid memory bid = _bids[next];
            list[i] = ListResponse({id: next, value: bid.maxPrice});
            next = bid.next;
            ++i;
        }
        return list;
    }

    /**
     * @notice More efficiently reverts with a bytes4 selector
     * @param selector The selector to revert with
     */
    function _revert(bytes4 selector) private pure {
        assembly {
            mstore(0x0, selector)
            revert(0x0, 0x04)
        }
    }
}

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

    uint256 public lastPointerLegibleForClaim;
    uint256 public totalGlowSold;

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
        lastPointerLegibleForClaim = type(uint256).max;
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
        uint256 totalGlowSpent;
        uint256 head = _pointers.head;
        if (head == _NULL) revert("Head Null");
        Bid memory highestBid = _bids[head];
        uint256 price = highestBid.maxPrice;

        //10 GLOW / 10 GLOW / GCC = 1 GCC
        //10 GLOW / (.5 GLOW / GCC) = 20
        uint256 amount = (uint256(highestBid.bidAmount) * 1e18) / uint256(highestBid.maxPrice);
        gccSoldCounter = amount;
        totalGlowSpent = highestBid.bidAmount;

        // console.log("gcc sold counter =  top level", gccSoldCounter);

        head = highestBid.prev;
        while (head != _NULL) {
            Bid memory bid = _bids[head];
            uint256 prevCounter = gccSoldCounter;
            gccSoldCounter = (uint256(gccSoldCounter) * uint256(price)) / bid.maxPrice;
            // console.log("-------------------");
            // console.log("gcc.c.top level =", gccSoldCounter);
            // console.log("price coming up =", uint256(bid.maxPrice));
            // console.log("price           =", price);
            // console.log("------------------");
            if (gccSoldCounter > GCC_IN_AUCTION) {
                // console.log("gcc sold counter inside loop", gccSoldCounter);
                // console.log("gcc in auction inside loop", GCC_IN_AUCTION);
                // console.log("should be here");

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
                //to find the value where all the glow we've spent so far clears the auction
                //newPrice = totalGlowSpent * 1e18 / total gcc in auction
                // console.log("price before = ", price);
                // console.log("gcc sold counter = ", gccSoldCounter);
                price = totalGlowSpent * 1e18 / GCC_IN_AUCTION;
                // uint iter;
                while (totalGlowSpent * 1e18 / price > GCC_IN_AUCTION) {
                    price = price * 1_000_000_000 / 999_999_999;
                    // console.log("iter",iter++);
                }

                // console.log("total glow spent = ",totalGlowSpent);
                // console.log("price after = ", price);
                // console.log("prev counter = ", prevCounter);
                gccSoldCounter = GCC_IN_AUCTION;
                totalGlowSpent += bid.bidAmount;
                // console.log("First");
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
                // amountOverflow is in terms of GCC
                uint256 amountOverflow = gccSoldCounter - GCC_IN_AUCTION;
                //our current bid get's us `amount`
                //so we need `amount - `amountOverflow`
                uint256 amountGccNeededInBid = amount - amountOverflow;
                //Now we need to find how much glow is needed to get there.
                //amount needed = glow amount * 1e18 / price
                //glow amount = amount needed * price / 1e18
                uint256 newBidAmount = amountGccNeededInBid * price / 1e18;

                console.log("prev bid amount = ", uint256(bid.bidAmount));
                console.log("new bid amount  =", newBidAmount);

                //Send glow back to user
                _bids[head].bidAmount = uint96(newBidAmount);
                gccSoldCounter = GCC_IN_AUCTION;

                totalGlowSpent += newBidAmount;
                break;
            }

            if (gccSoldCounter == GCC_IN_AUCTION) {
                // console.log("3rd");
                totalGlowSpent += bid.bidAmount;
                break;
            }

            totalGlowSpent += bid.bidAmount;
            head = bid.prev;
        }
        //Handle not enough bids case.
        if (gccSoldCounter < GCC_IN_AUCTION) {
            price = (price * gccSoldCounter) / GCC_IN_AUCTION;
            //we need totalGlowSpent * 1e18 / price = GCC_IN_AUCTION
            //so price = totalGlowSpent * 1e18 / GCC_IN_AUCTIOn
            price = totalGlowSpent * 1e18 / GCC_IN_AUCTION;

            //There's a chance we overshoot because of precision
            uint256 iter;
            while (totalGlowSpent * 1e18 / price > GCC_IN_AUCTION) {
                console.log("iter ", iter++);

                price = price * 1_000_000_000 / 999_999_999;
            }
            // console.log("third");
            // console.log("price from here = ", price);
        }
        if (head == _NULL) {
            lastPointerLegibleForClaim = _pointers.tail;
        } else {
            lastPointerLegibleForClaim = head;
        }

        // console.log("last pointer legibile for claim)

        closingPrice = price;
        totalGlowSold = totalGlowSpent;
    }

    function getNextBidPrice() public view returns (uint256) {
        uint256 _currentHighestBid = currentHighestBid;
        if (_currentHighestBid == 0) return MIN_BID;
        return _currentHighestBid * (100 + INCREASE_BID_PERCENTAGE) / _DENOMINATOR;
    }

    function amountOwed(uint256 bidId) public view returns (uint256) {
        // uint startingBidId = bidId;
        uint256 _closingPrice = closingPrice;
        uint256 amountInBid = _bids[bidId].bidAmount;
        uint256 maxPriceInBid = _bids[bidId].maxPrice;

        if (_closingPrice > maxPriceInBid) {
            return 0;
        }

        if (_closingPrice == maxPriceInBid) {
            //We need to make sure that
            uint256 _lastAcceptableBidId = lastPointerLegibleForClaim;
            //so let's  load in id 247
            uint256 tempId = bidId;
            if (tempId != _lastAcceptableBidId) {
                tempId = _bids[tempId].next;
                if (bidId == _lastAcceptableBidId) {
                    return 0;
                }

                while (maxPriceInBid == _bids[tempId].maxPrice) {
                    uint256 next = _bids[tempId].next;
                    if (next == _lastAcceptableBidId) {
                        return 0;
                    }
                    tempId = next;
                }
            }
            if (bidId == _lastAcceptableBidId) {
                uint256 totalGccSold = totalGlowSold * 1e18 / _closingPrice;
                uint256 owed = amountInBid * 1e18 / _closingPrice;
                if (totalGccSold > GCC_IN_AUCTION) {
                    uint256 overflow = totalGccSold - GCC_IN_AUCTION;
                    console.log("------------------");
                    console.log("partial bid id = ", bidId);
                    console.log("amountGCCToReceive partial bid =", owed - overflow);
                    console.log("amountGlowBid = ", amountInBid);
                    console.log("max price chosen", maxPriceInBid);

                    console.log("------------------");

                    return owed - overflow;
                }
            }
        }
        uint256 amount = amountInBid * 1e18 / closingPrice;
        console.log("------------------");

        console.log("bid id = ", bidId);
        console.log("amountGCCToReceive =", amount);
        console.log("amountGlowBid = ", amountInBid);
        console.log("max price chosen", maxPriceInBid);
        console.log("------------------");

        return amount;
    }

    function maxAmountToBidForPrice(uint256 price, uint256 timesSmallerMustBe) external view returns (uint256) {
        /**
         * amountToBid * 1e18 / maxPrice = total sold
         *     total sold = 1000, find amountToBid
         *     totalSold * maxPrice / 1e18 = amountToBid
         */
        uint256 amountToBid = GCC_IN_AUCTION * price / 1e18;
        return amountToBid / timesSmallerMustBe;
    }

    function bid(uint256 maxPrice, uint32 prev, uint32 next, uint256 amountToBid) external payable {
        uint256 _bidCount = bidCount++;
        if (maxPrice == 0) revert("price must be > 0");
        if (amountToBid * 1e18 / maxPrice > GCC_IN_AUCTION) revert("Oversell Auction Individually");

        // Ensure the provided bid amount meets the required minimum
        uint256 amountRequired = getNextBidPrice();
        // console.log("amount required = ", amountRequired);
        // console.log("amount to bid   = " , amountToBid);
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
        uint256 maxPrice;
        uint256 amount;
    }

    function constructSortedList() external view returns (ListResponse[] memory) {
        ListResponse[] memory list = new ListResponse[](bidCount);

        uint32 next = _pointers.tail;
        uint32 i = 0;
        while (next != _NULL) {
            Bid memory bid = _bids[next];
            list[i] = ListResponse({id: next, amount: bid.bidAmount, maxPrice: bid.maxPrice});
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

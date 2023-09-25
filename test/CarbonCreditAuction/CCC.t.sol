// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "../../src/testing/TestGLOW.sol";
import "forge-std/console.sol";
import {ICarbonCreditAuction} from "@/interfaces/ICarbonCreditAuction.sol";
import {CCC} from "@/CCC.sol";
import {Handler} from "./Handlers/Handler.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract CCCTest is Test {
    CCC auction;
    uint32 private constant NULL = type(uint32).max;
    Handler handler;

    function setUp() public {
        auction = new CCC();
        handler = new Handler(address(auction));

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = Handler.bid.selector;
        FuzzSelector memory fs = FuzzSelector({selectors: selectors, addr: address(handler)});
        targetContract(address(handler));
    }

    // /**
    //  * forge-config: default.invariant.runs = 10
    //  * forge-config: default.invariant.depth = 1000
    //  */
    // function invariant_linkedLinkShouldBeSortedAscending() public {
    //     CCC.Pointers memory pointers = auction.pointers();
    //     uint32 current = pointers.tail;
    //     uint256 iterations;
    //     while (current != NULL) {
    //         CCC.Bid memory bid = auction.bids(current);
    //         if (bid.next != NULL) {
    //             CCC.Bid memory nextBid = auction.bids(bid.next);
    //             assertTrue(bid.maxPrice <= nextBid.maxPrice, "Bid should be sorted ascending");
    //         }
    //         current = bid.next;
    //         ++iterations;
    //     }

    //     assertEq(iterations, handler.iterations());
    // }

    // function invariant_linkedListShouldSortDescending_whenTraversingFromHead() public {
    //     CCC.Pointers memory pointers = auction.pointers();
    //     uint32 current = pointers.head;
    //     uint256 iterations;
    //     while (current != NULL) {
    //         CCC.Bid memory bid = auction.bids(current);
    //         if (bid.prev != NULL) {
    //             CCC.Bid memory prevBid = auction.bids(bid.prev);
    //             assertTrue(bid.maxPrice >= prevBid.maxPrice, "Bid should be sorted descending");
    //         }
    //         current = bid.prev;
    //         ++iterations;
    //     }

    //     assertEq(iterations, handler.iterations());
    // }

    function inRange(uint256 value, uint256 lowestAcceptableValue, uint256 highestAcceptableValue)
        internal
        view
        returns (bool)
    {
        bool valid = lowestAcceptableValue <= value && value <= highestAcceptableValue;

        if (value < lowestAcceptableValue) {
            console.log("lowest");
        }
        if (value > highestAcceptableValue) {
            console.log("higher");
        }
        return valid;
    }

    /**
     * forge-config: default.invariant.runs = 100
     * forge-config: default.invariant.depth = 200
     */
    function invariant_closingPriceMultipliedByAllValidBids_shouldEqualTotalGCC_largeDepth() public {
        checkerInvariantForTotalGCCSold();
    }

    /**
     * forge-config: default.invariant.runs = 10000
     * forge-config: default.invariant.depth = 5
     */
    function invariant_closingPriceMultipliedByAllValidBids_shouldEqualTotalGCC_smallDepth() public {
        checkerInvariantForTotalGCCSold();
    }

    /**
     * forge-config: default.invariant.runs = 1000
     * forge-config: default.invariant.depth = 50
     */
    function invariant_closingPriceMultipliedByAllValidBids_shouldEqualTotalGCC_mediumDepth() public {
        checkerInvariantForTotalGCCSold();
    }

    function checkerInvariantForTotalGCCSold() public {
        uint256 head = auction.pointers().head;
        if (head == NULL) return;
        auction.close();
        uint256 amountExpected = auction.GCC_IN_AUCTION();
        uint256 minimumExpected = amountExpected * 9_999_999 / 10_000_000;
        //we need .0001% precision
        console.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
        uint256 totalOwed = findTotalOwed(false);
        console.log("sum           =", totalOwed);
        console.log("closing price = ", auction.closingPrice());
        bool _inRange = inRange(totalOwed, minimumExpected, amountExpected);
        console.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~");

        assertTrue(_inRange);
    }

    function test_bidClosingPrice_notEnoughBidsToFinishSale() public {
        //maxPrice,prev,next,amount to bid
        auction.bid(10 * 1e18, 0, 0, 1e18);
        auction.bid(20 * 1e18, 0, 0, 11 * 1e17);

        uint256 totalGlowInBids = 1e18 + 11 * 1e17;

        //price will finish at 10 glw / gcc which means
        //we will have sold .21 gcc
        //so

        auction.close();
        uint256 closingPrice = auction.closingPrice();

        uint256 totalOwed = findTotalOwed(false);

        console.log("sum  = ", totalOwed);
    }

    function test_randomBids() public {
        //maxPrice,prev,next,amount to bid
        auction.bid(10 * 1e18, 0, 0, 1e18);
        auction.bid(20 * 1e18, 0, 0, 11 * 1e17);
        //maxPrice,prev,next,amount to bid
        auction.bid(1e17, 0, 0, 20 * 1e18);
        auction.bid(1e16, 0, 0, 10 * 1e18);
        //20 + 1 + 1.1 = 22.2
        uint256 valToLog = 210 ether / 1000;
        // 210 GLOW / x(GLOW /GCC) = 1000 GCC
        // 210 GLOW / 1000 GCC

        console.log("val to log = ", valToLog);
        /**
         * In Order:
         *     20 GLW / GCC : 1.1 GLOW
         *     10 GLOW / GCC: 1 GLOW
         *     .1 GLW / GCC, 20 GLOW
         *     .01 GLW / GCC: 10 GLOW
         *
         *     If at .1:
         *     200 GCC +
         *
         *     Closing Price = 221000000000000000
         */

        auction.close();
        uint256 closingPrice = auction.closingPrice();
        console.log("closing pric = ", closingPrice);

        uint256 totalOwed = findTotalOwed(false);

        console.log("sum  = ", totalOwed);
    }

    function findTotalOwed(bool logIndividual) internal view returns (uint256) {
        uint256 totalOwed;
        uint256 head = auction.pointers().head;
        while (head != NULL) {
            uint256 amount = auction.amountOwed(head);
            if (logIndividual) {
                console.log("-----------------");
                console.log("@head", head);
                console.log("@amount=", amount);
                console.log("-----------------");
            }
            if (amount == 0) break;
            totalOwed += amount;
            head = auction.bids(head).prev;
        }

        return totalOwed;
    }

    function test_bidClosingPrice_partialBidMustFill() public {
        auction.bid(1 * 1e18, 0, 0, 400 * 1e18);
        auction.bid(5 * 1e17, 0, 0, 150 * 1e18);
        auction.close();
        //Price finishes at 1 glow / gcc
        //First bid was 2 glow / gcc and 800 glw
        //Second bid was 300 glow
        //That means we oversell by 100 (1000 - 800 + 300  = 100) glow and we need to partial fill.

        uint256 closingPrice = auction.closingPrice();

        uint256 amountOwedFromZero = auction.amountOwed(0);
        uint256 amountOwedFromOne = auction.amountOwed(1);
        console.log("closing price = ", closingPrice);
        console.log("owed zero = ", amountOwedFromZero);
        console.log("owed one = ", amountOwedFromOne);

        console.log("sum  = ", amountOwedFromZero + amountOwedFromOne);
    }

    function test_closeOversell() public {
        auction.bid(2 * 1e18, 0, 0, 800 * 1e18);
        auction.bid(1e18, 0, 0, 300 * 1e18);
        auction.close();
    }

    //PRINT FUNCTIONS
    function printPointers() public {
        CCC.Pointers memory pointers = auction.pointers();
        console.log("head %s", pointers.head);
        console.log("tail %s", pointers.tail);
    }

    function printBid(uint32 id) public {
        console.logString("--------------------");
        CCC.Bid memory bid = auction.bids(id);
        console.log("id %s:", id);
        console.log("max price", bid.maxPrice);
        console.log("bidder", bid.bidder);
        console.log("prev", bid.prev);
        console.log("next", bid.next);
        console.logString("--------------------");
    }

    function printList() public {
        CCC.Pointers memory pointers = auction.pointers();
        uint32 current = pointers.tail;
        // CCC.memory bid = auction.bids(current);
        while (current != NULL) {
            printBid(current);
            current = auction.bids(current).next;
        }
    }

    function printListLinear() public {
        uint32 current = 0;
        uint256 bidCount = auction.bidCount();
        for (uint32 i = 0; i < bidCount; i++) {
            printBid(i);
        }
    }
}

// pragma solidity 0.8.21;

// import {ICarbonCreditAuction} from "@/interfaces/ICarbonCreditAuction.sol";
// import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// //TEMP!
// import "forge-std/console.sol";

// contract CCC is ICarbonCreditAuction {
//     uint256 public constant MIN_BID = 1 ether;
//     uint256 public constant INCREASE_BID_PERCENTAGE = 10;
//     uint256 private constant _DENOMINATOR = 100;
//     uint32 private constant _NULL = type(uint32).max;

//     uint256 public bidCount;
//     uint256 public currentHighestBid = MIN_BID;
//     Pointers private _pointers;

//     struct Pointers {
//         uint32 head;
//         uint32 tail;
//     }

//     struct Bid {
//         address bidder;
//         uint96 maxPrice;
//         uint32 prev;
//         uint32 next;
//     }

//     mapping(uint256 => Bid) private _bids;

//     constructor() {
//         _pointers.head = _NULL;
//         _pointers.tail = _NULL;
//     }

//     /// @inheritdoc ICarbonCreditAuction
//     function receiveGCC(uint256 amount) external override {
//         return;
//     }

//     function getNextBidPrice() public view returns (uint256) {
//         return currentHighestBid * (100 + INCREASE_BID_PERCENTAGE) / _DENOMINATOR;
//     }

//     function bid(uint256 maxPrice, uint32 prev, uint32 next) external payable {
//         uint256 _bidCount = bidCount;

//         // Ensure the provided bid amount meets the required minimum
//         uint256 amountRequired = getNextBidPrice();
//         // require(msg.value == amountRequired, "Bid amount is too low.");

//         if (_bidCount == 0) {
//             // If no bids have been placed yet
//             _bids[0] = Bid({bidder: msg.sender, maxPrice: uint96(maxPrice), prev: _NULL, next: _NULL});
//             _pointers.head = 0;
//             _pointers.tail = 0;
//         } else if (_bidCount == 1) {
//             // If only one bid has been placed
//             if (maxPrice > _bids[0].maxPrice) {
//                 // If the new bid is higher than the existing bid
//                 _bids[1] = Bid({bidder: msg.sender, maxPrice: uint96(maxPrice), prev: 0, next: _NULL});
//                 _bids[0].next = 1;
//                 _pointers.head = 1;
//             } else {
//                 // If the new bid is lower than the existing bid
//                 _bids[1] = Bid({bidder: msg.sender, maxPrice: uint96(maxPrice), prev: _NULL, next: 0});
//                 _bids[0].prev = 1;
//                 _pointers.tail = 1;
//             }
//         } else {
//             if (next == _NULL) {
//                 next = _pointers.head;
//             }
//             // if (prev == _NULL) {
//             //     prev = _pointers.tail;
//             // }

//             // if (next > _bidCount) revert("Invalid next _pointer.");
//             // if (prev > _bidCount) revert("Invalid prev _pointer.");

//             Bid storage topAdjacentBid = _bids[next];
//             // if(topAdjacentBid.maxPrice > maxPrice) revert("max price");
//             //Find Next
//             uint iter;
//             while (true) {
//                 if (maxPrice < topAdjacentBid.maxPrice) {
//                     if (topAdjacentBid.next == _NULL) {
//                         break;
//                     }
//                     break;
//                 }

//                 if (topAdjacentBid.next == _NULL) {
//                     _pointers.head = uint32(_bidCount);
//                     topAdjacentBid.next = uint32(bidCount);
//                     _bids[_bidCount] = Bid({bidder: msg.sender, maxPrice: uint96(maxPrice), prev: next, next: _NULL});
//                     ++bidCount;
//                     return;
//                 }
//                 next = topAdjacentBid.next;
//                 topAdjacentBid = _bids[topAdjacentBid.next];

//                 ++iter;

//             }

//             Bid storage bottomAdjacentBid = _bids[topAdjacentBid.prev == _NULL ? _pointers.tail : topAdjacentBid.prev];

//             // printBid(5);

//             while (true) {
//                 //          if(_bidCount == 6) {
//                 //     console.log("here");
//                 // }
//                 if (maxPrice >= bottomAdjacentBid.maxPrice) {
//                     break;
//                 }

//                 if (bottomAdjacentBid.prev == _NULL) {
//                     console.log("Sugama wugama jugama");
//                     _pointers.tail = uint32(_bidCount);
//                     bottomAdjacentBid.prev = uint32(_bidCount);
//                     _bids[_bidCount] = Bid({bidder: msg.sender, maxPrice: uint96(maxPrice), prev: _NULL, next: next});
//                     ++bidCount;
//                     return;
//                 }
//                 //
//                 break;

//                 prev = bottomAdjacentBid.prev;
//                 bottomAdjacentBid = _bids[bottomAdjacentBid.prev];
//             }

//             bottomAdjacentBid.next = uint32(_bidCount);
//             topAdjacentBid.prev = uint32(_bidCount);
//             _bids[_bidCount] = Bid({bidder: msg.sender, maxPrice: uint96(maxPrice), prev: prev, next: next});
//         }

//         ++bidCount;

//         // emit BidPlaced(msg.sender, msg.value, maxPrice);  // Assuming you have an event called BidPlaced
//     }

//     function bids(uint256 id) external view returns (Bid memory) {
//         return _bids[id];
//     }

//     function printBid(uint32 id) public {
//         console.logString("--------------------");
//         Bid memory bid = _bids[id];
//         console.log("id %s:", id);
//         console.log("max price", bid.maxPrice);
//         console.log("bidder", bid.bidder);
//         console.log("prev", bid.prev);
//         console.log("next", bid.next);
//         console.logString("--------------------");
//     }

//     function pointers() external view returns (Pointers memory) {
//         return _pointers;
//     }

//     /**
//      * @notice More efficiently reverts with a bytes4 selector
//      * @param selector The selector to revert with
//      */
//     function _revert(bytes4 selector) private pure {
//         assembly {
//             mstore(0x0, selector)
//             revert(0x0, 0x04)
//         }
//     }
// }

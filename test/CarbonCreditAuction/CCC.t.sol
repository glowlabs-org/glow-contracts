// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "../../src/testing/TestGLOW.sol";
import "forge-std/console.sol";
import {ICarbonCreditAuction} from "@/interfaces/ICarbonCreditAuction.sol";
import {CCC} from "@/CCC.sol";
import {Handler} from "./Handlers/Handler.sol";

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

    /**
     * forge-config: default.invariant.runs = 10
     * forge-config: default.invariant.depth = 1000
     */
    function invariant_linkedLinkShouldBeSortedAscending() public {
        CCC.Pointers memory pointers = auction.pointers();
        uint32 current = pointers.tail;
        uint256 iterations;
        while (current != NULL) {
            CCC.Bid memory bid = auction.bids(current);
            if (bid.next != NULL) {
                CCC.Bid memory nextBid = auction.bids(bid.next);
                assertTrue(bid.maxPrice <= nextBid.maxPrice, "Bid should be sorted ascending");
            }
            current = bid.next;
            ++iterations;
        }

        assertEq(iterations, handler.iterations());
    }

    function invariant_linkedListShouldSortDescending_whenTraversingFromHead() public {
        CCC.Pointers memory pointers = auction.pointers();
        uint32 current = pointers.head;
        uint256 iterations;
        while (current != NULL) {
            CCC.Bid memory bid = auction.bids(current);
            if (bid.prev != NULL) {
                CCC.Bid memory prevBid = auction.bids(bid.prev);
                assertTrue(bid.maxPrice >= prevBid.maxPrice, "Bid should be sorted descending");
            }
            current = bid.prev;
            ++iterations;
        }

        assertEq(iterations, handler.iterations());
    }

    function test_bid2() public {
        auction.bid(3281, 0, 0);
        auction.bid(79228162514264337593543950335, 0, 0);
        printList();
    }

    function test_Bid() public {
        auction.bid(2, 1, 1); //0
        auction.bid(10, 0, 0); //1
        auction.bid(20, 1, NULL); //2

        auction.bid(11, 1, 2); //3
        auction.bid(13, 0, 0); //4
        auction.bid(15, 0, 0); //5
        auction.bid(1, NULL, 0); //6
        auction.bid(1, 0, 0); //7
        auction.bid(12, 0, 2); //8

        // auction.bid(12, 0, 2); //6

        //Order should be
        //0,3,4,1,2

        printPointers();
        // printBid(0);
        // printBid(1);
        // printBid(2);
        printList();
        // printListLinear();
    }

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

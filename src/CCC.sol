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
    uint256 public currentHighestBid = MIN_BID;
    Pointers private _pointers;

    uint256 closingPrice;

    struct Pointers {
        uint32 head;
        uint32 tail;
    }

    struct Bid {
        address bidder;
        uint96 maxPrice;
        uint32 prev;
        uint32 next;
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

    function closeAuction() external {
        uint amountAllocated;
        uint head = _pointers.head;
        while(head != _NULL) {
            Bid memory bid = _bids[head];
            uint amountToAllocate = GCC_IN_AUCTION * bid.maxPrice / _DENOMINATOR;
            amountAllocated += amountToAllocate;
            // SafeERC20.safeTra
    }
    }

    function getNextBidPrice() public view returns (uint256) {
        return currentHighestBid * (100 + INCREASE_BID_PERCENTAGE) / _DENOMINATOR;
    }

    function bid(uint256 maxPrice, uint32 prev, uint32 next) external payable {
        uint256 _bidCount = bidCount++;

        // Ensure the provided bid amount meets the required minimum
        uint256 amountRequired = getNextBidPrice();
        currentHighestBid = amountRequired;
        // require(msg.value == amountRequired, "Bid amount is too low.");

        if (_bidCount == 0) {
            // If no bids have been placed yet
            _bids[0] = Bid({bidder: msg.sender, maxPrice: uint96(maxPrice), prev: _NULL, next: _NULL});
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
                            _bids[_bidCount] =
                                Bid({bidder: msg.sender, maxPrice: uint96(maxPrice), prev: _NULL, next: prev});
                            return;
                        }
                        // console.log("prev = ", )
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
                    _bids[_bidCount] = Bid({bidder: msg.sender, maxPrice: uint96(maxPrice), prev: next, next: _NULL});
                    return;
                }

                // if(maxPrice)

                next = nextBid.next;
                nextBid = _bids[next];
            }

            Bid memory lastBid = _bids[nextBid.prev];

            _bids[next].prev = uint32(_bidCount);
            _bids[prev].next = uint32(_bidCount);
            _bids[_bidCount] = Bid({bidder: msg.sender, maxPrice: uint96(maxPrice), prev: prev, next: next});
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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * TransientBytes (incremental slots)
 * - Length at `baseSlot`
 * - Data starts at keccak256(abi.encodePacked(baseSlot, DOMAIN))
 * - Chunk i lives at dataStart + i
 *
 * Uses OpenZeppelin TransientSlot for typed tload/tstore.
 */
import "./TransientSlot.sol";

library TransientBytes {
    using TransientSlot for *;

    // Domain-separate the data region to avoid accidental overlap
    bytes32 private constant _DOMAIN = keccak256("TransientBytes.v2");

    /*//////////////////////////////////////////////////////////////
                              WRITE
    //////////////////////////////////////////////////////////////*/

    function tstoreBytes(bytes32 baseSlot, bytes memory data) internal {
        uint256 len = data.length;
        baseSlot.asUint256().tstore(len);

        if (len == 0) return;

        uint256 nChunks = (len + 31) / 32; // ceil_div
        bytes32 dataStart = _dataStart(baseSlot);

        uint256 src;
        assembly {
            src := add(data, 32)
        }

        for (uint256 i = 0; i < nChunks; ++i) {
            bytes32 word;
            assembly {
                word := mload(add(src, mul(i, 32)))
            }
            _slotAdd(dataStart, i).asBytes32().tstore(word);
        }
    }

    /*//////////////////////////////////////////////////////////////
                               READ
    //////////////////////////////////////////////////////////////*/

    function tloadBytes(bytes32 baseSlot) internal view returns (bytes memory out) {
        uint256 len = baseSlot.asUint256().tload();
        if (len == 0) return bytes("");

        out = new bytes(len);
        uint256 nChunks = (len + 31) / 32;
        bytes32 dataStart = _dataStart(baseSlot);

        uint256 dst;
        assembly {
            dst := add(out, 32)
        }

        for (uint256 i = 0; i < nChunks; ++i) {
            bytes32 word = _slotAdd(dataStart, i).asBytes32().tload();
            assembly {
                mstore(add(dst, mul(i, 32)), word)
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                               CLEAR
    //////////////////////////////////////////////////////////////*/

    /// @dev Logically clear by zeroing length (no need to zero chunks).
    function tclear(bytes32 baseSlot) internal {
        baseSlot.asUint256().tstore(0);
    }

    /*//////////////////////////////////////////////////////////////
                             INTERNALS
    //////////////////////////////////////////////////////////////*/

    /// @dev Start of data region = keccak256(baseSlot || DOMAIN)
    function _dataStart(bytes32 baseSlot) private pure returns (bytes32 start) {
        bytes32 d = _DOMAIN;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, baseSlot)
            mstore(add(ptr, 0x20), d)
            start := keccak256(ptr, 64)
        }
    }

    /// @dev Return base + index as a bytes32 slot.
    function _slotAdd(bytes32 base, uint256 index) private pure returns (bytes32 slot) {
        assembly {
            slot := add(base, index)
        }
    }
}

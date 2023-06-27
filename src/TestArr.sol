// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract TestArr {

    uint256[] public storageArray;

    function push(uint[] calldata arr) public {
        unchecked{

            for (uint i = 0; i < arr.length; ++i) {
                storageArray.push(arr[i]);
            }
        }
    }

    function addElement(uint256 element) public {
        storageArray.push(element);
    }

    function getArr() public view returns (uint256[] memory) {
        return storageArray;
    }
}
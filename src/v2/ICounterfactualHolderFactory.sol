// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Call} from "./Structs.sol";

interface ICounterfactualHolderFactory {
    function getTransientCalls() external view returns (Call[] memory);
    function getTransientNextHolder() external view returns (address);
}

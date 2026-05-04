// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ITokenDelegateFactory {
    function getTransientBeam() external view returns (address);
    function getTransientBeamData() external view returns (bytes memory);
}

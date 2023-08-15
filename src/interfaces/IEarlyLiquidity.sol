// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

interface IEarlyLiquidity {
    error PriceTooHigh();
    error ModNotZero();

    event Purchase(address indexed buyer, uint256 glwReceived, uint256 totalUSDCSpent);
}

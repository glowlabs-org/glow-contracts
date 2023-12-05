// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {USDG} from "@/USDG.sol";
import {UnifapV2Library} from "@unifapv2/libraries/UnifapV2Library.sol";

contract MainnetForkTestUSDG is USDG {
    /* -------------------------------------------------------------------------- */
    /*                                 constructor                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @param _usdc the USDC token
     * @param _usdcReceiver the address to receive USDC from the `swap` function
     * @param _owner the owner of the contract
     * @param _univ2Factory the uniswap v2 factory
     */
    constructor(address _usdc, address _usdcReceiver, address _owner, address _univ2Factory)
        USDG(_usdc, _usdcReceiver, _owner, _univ2Factory)
    {}

    function addAllowlistedContract(address _address) external {
        allowlistedContracts[_address] = true;
    }
}

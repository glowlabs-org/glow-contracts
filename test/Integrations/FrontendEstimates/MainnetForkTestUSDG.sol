// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {USDG} from "@glow/USDG.sol";
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
     * @param _glow the glow token
     * @param _gcc the gcc token
     * @param _holdingContract the holding contract
     * @param _vetoCouncilContract the veto council contract
     * @param _impactCatalyst the impact catalyst contract
     */
    constructor(
        address _usdc,
        address _usdcReceiver,
        address _owner,
        address _univ2Factory,
        address _glow,
        address _gcc,
        address _holdingContract,
        address _vetoCouncilContract,
        address _impactCatalyst
    )
        USDG(
            _usdc,
            _usdcReceiver,
            _owner,
            _univ2Factory,
            _glow,
            _gcc,
            _holdingContract,
            _vetoCouncilContract,
            _impactCatalyst
        )
    {}

    function addAllowlistedContract(address _address) external {
        allowlistedContracts[_address] = true;
    }
}

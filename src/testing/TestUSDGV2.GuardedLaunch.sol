// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {USDGGuardedLaunchV2} from "@/GuardedLaunchV2/USDG.GuardedLaunchV2.sol";
import {UnifapV2Library} from "@unifapv2/libraries/UnifapV2Library.sol";

contract TestUSDGGuardedLaunchV2 is USDGGuardedLaunchV2 {
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
        address _impactCatalyst,
        address[] memory _allowlistedMultisigContracts,
        bytes memory _migrationContractAndAmount //To prevent stack too deep error
    )
        USDGGuardedLaunchV2(
            _usdc,
            _usdcReceiver,
            _owner,
            _univ2Factory,
            _glow,
            _gcc,
            _holdingContract,
            _vetoCouncilContract,
            _impactCatalyst,
            _allowlistedMultisigContracts,
            _migrationContractAndAmount
        )
    {}

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "UniswapV2Library: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "UniswapV2Library: ZERO_ADDRESS");
    }

    function getPair(address factory, address _tokenA, address _tokenB) internal view override returns (address pair) {
        (address token0, address token1) = sortTokens(_tokenA, _tokenB);
        pair = UnifapV2Library.pairFor(factory, token0, token1);
        return pair;
    }

    function addAllowlistedContract(address _address) external {
        allowlistedContracts[_address] = true;
    }
}

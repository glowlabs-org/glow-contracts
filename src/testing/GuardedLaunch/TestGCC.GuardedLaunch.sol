// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {GCCGuardedLaunch} from "@/GuardedLaunch/GCC.GuardedLaunch.sol";
import {UnifapV2Library} from "@unifapv2/libraries/UnifapV2Library.sol";

contract TestGCCGuardedLaunch is GCCGuardedLaunch {
    /* -------------------------------------------------------------------------- */
    /*                                 constructor                                */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice GCC constructor
     * @param _gcaAndMinerPoolContract The address of the GCAAndMinerPool contract
     * @param _governance The address of the governance contract
     * @param _glowToken The address of the GLOW token
     * @param _usdg The address of the USDG token
     * @param _vetoCouncilAddress The address of the veto council contract
     * @param _uniswapRouter The address of the Uniswap V2 router
     * @param _uniswapFactory The address of the Uniswap V2 factory
     */
    constructor(
        address _gcaAndMinerPoolContract,
        address _governance,
        address _glowToken,
        address _usdg,
        address _vetoCouncilAddress,
        address _uniswapRouter,
        address _uniswapFactory
    )
        payable
        GCCGuardedLaunch(
            _gcaAndMinerPoolContract,
            _governance,
            _glowToken,
            _usdg,
            _vetoCouncilAddress,
            _uniswapRouter,
            _uniswapFactory
        )
    {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function allowlistAddress(address _address) external {
        allowlistedContracts[_address] = true;
    }

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "UniswapV2Library: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "UniswapV2Library: ZERO_ADDRESS");
    }

    function getPair(address factory, address _tokenB) internal view virtual override returns (address pair) {
        (address token0, address token1) = sortTokens(address(this), _tokenB);
        pair = UnifapV2Library.pairFor(factory, token0, token1);
        return pair;
    }
}

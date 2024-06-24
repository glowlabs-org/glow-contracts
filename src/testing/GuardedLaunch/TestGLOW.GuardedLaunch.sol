// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {GlowGuardedLaunch} from "@/GuardedLaunch/Glow.GuardedLaunch.sol";
import {UnifapV2Library} from "@unifapv2/libraries/UnifapV2Library.sol";

contract TestGLOWGuardedLaunch is GlowGuardedLaunch {
    uint256 private _launchTimestamp;

    /**
     * @notice constructs a new GLOW token
     * @param _earlyLiquidityAddress the address to send the early liquidity to
     * @param _vestingContract the address of the vesting contract
     * @param _gcaAndMinerPoolAddress The address of the GCA and Miner Pool
     * @param _vetoCouncilAddress The address of the Veto Council
     * @param _grantsTreasuryAddress The address of the Grants Treasury
     * @param _owner the owner of the contract
     * @param _usdg the address of the USDG contract
     * @param _uniswapV2Factory the address of the uniswap v2 factory
     * @param _gccContract the address of the GCC contract
     */
    constructor(
        address _earlyLiquidityAddress,
        address _vestingContract,
        address _gcaAndMinerPoolAddress,
        address _vetoCouncilAddress,
        address _grantsTreasuryAddress,
        address _owner,
        address _usdg,
        address _uniswapV2Factory,
        address _gccContract
    )
        GlowGuardedLaunch(
            _earlyLiquidityAddress,
            _vestingContract,
            _gcaAndMinerPoolAddress,
            _vetoCouncilAddress,
            _grantsTreasuryAddress,
            _owner,
            _usdg,
            _uniswapV2Factory,
            _gccContract
        )
    {
        _launchTimestamp = block.timestamp;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function allowlistAddress(address _address) external {
        allowlistedContracts[_address] = true;
    }

    function GENESIS_TIMESTAMP() public view override returns (uint256) {
        return _launchTimestamp;
    }

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "UniswapV2Library: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "UniswapV2Library: ZERO_ADDRESS");
    }

    function getPair(address factory, address _tokenA, address _tokenB)
        internal
        view
        virtual
        override
        returns (address pair)
    {
        (address token0, address token1) = sortTokens(_tokenA, _tokenB);
        pair = UnifapV2Library.pairFor(factory, token0, token1);
        return pair;
    }
}

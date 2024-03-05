// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../GLOW.sol";

contract TestGLOW is Glow {
    uint256 private _launchTimestamp;

    /*
     * @notice Sets the immutable variables (GENESIS_TIMESTAMP, EARLY_LIQUIDITY_ADDRESS)
    * @notice sends 12 million GLW to the Early Liquidity Contract and 96 million GLW to the unlocker contract
    * @param _earlyLiquidityAddress The address of the Early Liquidity Contract
    * @param _vestingContract The address of the vesting contract
    * @param _gcaAndMinerPoolAddress The address of the GCA and Miner Pool
    * @param _vetoCouncilAddress The address of the Veto Council
    * @param _grantsTreasuryAddress The address of the Grants Treasury
    */
    constructor(
        address _earlyLiquidityAddress,
        address _vestingContract,
        address _gcaAndMinerPoolAddress,
        address _vetoCouncilAddress,
        address _grantsTreasuryAddress
    )
        payable
        Glow(_earlyLiquidityAddress, _vestingContract, _gcaAndMinerPoolAddress, _vetoCouncilAddress, _grantsTreasuryAddress)
    {
        _launchTimestamp = block.timestamp;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function GENESIS_TIMESTAMP() public view override returns (uint256) {
        return _launchTimestamp;
    }
}

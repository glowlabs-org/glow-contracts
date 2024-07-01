// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {GlowGuardedLaunch} from "../GuardedLaunch/Glow.GuardedLaunch.sol";
import {_GENESIS_TIMESTAMP_GUARDED_LAUNCH_V2} from "@/Constants/Constants.sol";

contract GlowGuardedLaunchV2 is GlowGuardedLaunch {
    /* -------------------------------------------------------------------------- */
    /*                                 constructor                                */
    /* -------------------------------------------------------------------------- */
    /*
    * @notice Sets the immutable variables (GENESIS_TIMESTAMP, EARLY_LIQUIDITY_ADDRESS)
    * @notice sends 12 million GLW to the Early Liquidity Contract and 90 million GLW to the unlocker contract
    * @param _earlyLiquidityAddress The address of the Early Liquidity Contract
    * @param _vestingContract The address of the vesting contract
                              -unused in guarded launch
      * @param _gcaAndMinerPoolAddress The address of the GCA and Miner Pool
    * @param _ve toCouncilAddress The address of the Veto Council
    * @param _grantsTreasuryAddress The address of the Grants Treasury
    * @param _owner The address of the owner
    * @param _usdg The address of the USDG contract
    * @param _uniswapV2Factory The address of the Uniswap V2 Factory
    * @param _gccContract The address of the GCC contract
    * @param _allowlistedMultisigContracts The addresses of the multisig contracts to allowlist
    * @param _extraBytes The address and amount in bytes to send to the migration contract
        - Also includes the last claimed timestamps for the inflationary contracts
        - To prevent stack too deep error
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
        address _gccContract,
        address[] memory _allowlistedMultisigContracts,
        bytes memory _extraBytes //To prevent stack too deep error
    )
        // address _migrationContract,
        // uint256 amount
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
        for (uint256 i; i < _allowlistedMultisigContracts.length;) {
            allowlistedContracts[_allowlistedMultisigContracts[i]] = true;
            unchecked {
                ++i;
            }
        }

        _executeExtraBytes(_extraBytes);
    }

    /* -------------------------------------------------------------------------- */
    /*                                  glow overrides                            */
    /* -------------------------------------------------------------------------- */
    // function GENESIS_TIMESTAMP() public pure override returns (uint256) {
    //     return _GENESIS_TIMESTAMP_GUARDED_LAUNCH_V2;
    // }

    /**
     * @inheritdoc GlowGuardedLaunch
     * @dev - The early liquidity will claim from migration.
     * @dev - The grants will also claim from the migration contract
     * @dev Guarded launch v2 does send to the vesting contract
     */
    function _handleConstructorMint(
        address _earlyLiquidityAddress,
        address _vestingContract,
        address _grantsTreasryAddress
    ) internal virtual override {
        allowlistedContracts[_vestingContract] = true;
        _mint(_vestingContract, 90_000_000 ether);
        _mint(_earlyLiquidityAddress, 12_000_000 ether); //TODO: check if this is correct when relaunching
        _mint(_grantsTreasryAddress, 10_000_000 ether); //TODO: check if this is correct when relaunching
    }

    /* -------------------------------------------------------------------------- */
    /*                                  utils                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @dev decode the migration contract and send the amount and
     * @dev also sets the last claimed timestamps for the inflationary contracts
     */
    function _executeExtraBytes(bytes memory _extraBytes) internal {
        (
            address _migrationContract,
            uint256 _amountToSendToMigrationContract,
            uint256 _gcaLastClaimTimestamp,
            uint256 _vetoCouncilLastClaimedTimestamp,
            uint256 _grantsLastClaimedTimestamp
        ) = abi.decode(_extraBytes, (address, uint256, uint256, uint256, uint256));
        allowlistedContracts[_migrationContract] = true;
        gcaAndMinerPoolLastClaimedTimestamp = _gcaLastClaimTimestamp;
        vetoCouncilLastClaimedTimestamp = _vetoCouncilLastClaimedTimestamp;
        grantsTreasuryLastClaimedTimestamp = _grantsLastClaimedTimestamp;
        _mint(_migrationContract, _amountToSendToMigrationContract);
    }
}

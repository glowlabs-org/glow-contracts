// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {USDG} from "@/USDG.sol";

contract USDGGuardedLaunchV2 is USDG {
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
     * @param _allowlistedMultisigContracts The addresses of the multisig contracts to allowlist
     * @param _migrationContractAndAmount The address and amount in bytes to send to the migration contract
     *     - To prevent stack too deep error
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
        payable
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
    {
        for (uint256 i; i < _allowlistedMultisigContracts.length;) {
            allowlistedContracts[_allowlistedMultisigContracts[i]] = true;
            unchecked {
                ++i;
            }
        }

        _decodeMigrationContractAndSendAmount(_migrationContractAndAmount);
    }

    function _decodeMigrationContractAndSendAmount(bytes memory _migrationContractAndAmount) internal {
        (address _migrationContract, uint256 _amountToSendToMigrationContract) =
            abi.decode(_migrationContractAndAmount, (address, uint256));
        allowlistedContracts[_migrationContract] = true;
        _mint(_migrationContract, _amountToSendToMigrationContract);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {GCCGuardedLaunch} from "@/GuardedLaunch/GCC.GuardedLaunch.sol";

contract GCCGuardedLaunchV2 is GCCGuardedLaunch {
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
     * @param _allowlistedMultisigContracts The addresses of the multisig contracts to allowlist
     * @param migrationContract The address of the migration contract
     * @param migrationAmount The amount to send to the migration contract
     */
    constructor(
        address _gcaAndMinerPoolContract,
        address _governance,
        address _glowToken,
        address _usdg,
        address _vetoCouncilAddress,
        address _uniswapRouter,
        address _uniswapFactory,
        address[] memory _allowlistedMultisigContracts,
        address migrationContract,
        uint256 migrationAmount
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
    {
        for (uint256 i; i < _allowlistedMultisigContracts.length;) {
            allowlistedContracts[_allowlistedMultisigContracts[i]] = true;
            unchecked {
                ++i;
            }
            allowlistedContracts[migrationContract] = true;
            _mint(migrationContract, migrationAmount);
        }
    }
}

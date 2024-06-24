// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {MinerPoolAndGCA} from "@/MinerPoolAndGCA/MinerPoolAndGCA.sol";
import {_GENESIS_TIMESTAMP_GUARDED_LAUNCH_V2} from "@/Constants/Constants.sol";

contract MinerPoolAndGCAGuardedLaunchV2 is MinerPoolAndGCA {
    /**
     * @notice constructs a new MinerPoolAndGCA contract
     * @param _gcaAgents the addresses of the gca agents the contract starts with
     * @param _glowToken the address of the glow token
     * @param _governance the address of the governance contract
     * @param _requirementsHash the requirements hash of GCA Agents
     * @param _usdcToken - the USDC token address
     * @param _vetoCouncil - the address of the veto council contract.
     * @param _holdingContract - the address of the holding contract
     * @param _gcc - the address of the gcc contract
     */
    constructor(
        address[] memory _gcaAgents,
        address _glowToken,
        address _governance,
        bytes32 _requirementsHash,
        address _earlyLiquidity,
        address _usdcToken,
        address _vetoCouncil,
        address _holdingContract,
        address _gcc
    )
        payable
        MinerPoolAndGCA(
            _gcaAgents,
            _glowToken,
            _governance,
            _requirementsHash,
            _earlyLiquidity,
            _usdcToken,
            _vetoCouncil,
            _holdingContract,
            _gcc
        )
    {}

    function _genesisTimestamp() internal pure virtual override(MinerPoolAndGCA) returns (uint256) {
        return _GENESIS_TIMESTAMP_GUARDED_LAUNCH_V2;
    }
}

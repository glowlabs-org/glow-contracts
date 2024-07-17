// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {MinerPoolAndGCA as MinerPoolAndGCAV1} from "@/MinerPoolAndGCA/MinerPoolAndGCA.sol";
import {MinerPoolAndGCAV2} from "@/MinerPoolAndGCA/MinerPoolAndGCAV2.sol";
import {GCASalaryHelper} from "@/MinerPoolAndGCA/GCASalaryHelper.sol";
import {GCA} from "@/MinerPoolAndGCA/GCA.sol";
import {_GENESIS_TIMESTAMP_GUARDED_LAUNCH_V2} from "@/Constants/Constants.sol";
import {IGCA} from "@/interfaces/IGCA.sol";

//TODO: check miner pool claim function and do the approvals for the claims

contract MinerPoolAndGCAGuardedLaunchV2 is MinerPoolAndGCAV2 {
    // struct MigrationInformation {
    //     uint256 migrationWeek;
    //     address previousMinerPool;
    // }

    // error CannotClaimFromPreviousContract();

    // uint256 public immutable MIGRATION_WEEK;
    // address public immutable PREVIOUS_MINERPOOL_CONTRACT;
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
        // MigrationInformation memory _migrationInfo
        // address _previousMinerPoolContract
        payable
        MinerPoolAndGCAV2(
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
    {
        // MIGRATION_WEEK = _migrationInfo.migrationWeek;
        // PREVIOUS_MINERPOOL_CONTRACT = _migrationInfo.previousMinerPool;
    }

    /**
     * @inheritdoc MinerPoolAndGCAV2
     */
    function claimRewardFromBucket(
        uint256 bucketId,
        uint256 glwWeight,
        uint256 usdcWeight,
        bytes32[][] calldata proofs,
        address[] calldata tokens,
        uint256 index,
        address user
    ) public virtual override {
        //     if (bucketId < MIGRATION_WEEK) revert CannotClaimFromPreviousContract();
        super.claimRewardFromBucket(bucketId, glwWeight, usdcWeight, proofs, tokens, index, user);
        // }
    }
    //TODO: probably best to throw an error....... ?

    function bucket(uint256 bucketId) public view virtual override returns (IGCA.Bucket memory _bucket) {
        // if (bucketId < MIGRATION_WEEK) {
        //     return MinerPoolAndGCAV1(PREVIOUS_MINERPOOL_CONTRACT).bucket(bucketId);
        // }
        return super.bucket(bucketId);
    }

    /* -------------------------------------------------------------------------- */
    /*                 overrides to set state in constructors                     */
    /* -------------------------------------------------------------------------- */

    function _constructorSetAgentsLastClaimedTimestamp(address[] memory _gcaAddresses, uint256)
        internal
        virtual
        override(GCA)
    {
        unchecked {
            for (uint256 i; i < _gcaAddresses.length; ++i) {
                _gcaPayouts[_gcaAddresses[i]].lastClaimedTimestamp = uint64(block.timestamp);
            }
        }
    }

    /**
     * @dev Due to the migration, we override the function to correctly set the payout start timestamp
     *       - in the constructor of the Salary Helper
     */
    function setZeroPaymentStartTimestamp() internal virtual override(GCASalaryHelper) {
        _paymentNonceToShiftStartTimestamp[0] = block.timestamp;
    }
}

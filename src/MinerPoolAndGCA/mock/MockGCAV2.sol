import "../GCA.sol";

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {GCASalaryHelper} from "../GCASalaryHelper.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {GCAV2} from "../GCAV2.sol";

contract MockGCAV2 is GCAV2 {
    /**
     * @notice constructs a new GCA contract
     * @param _gcaAgents the addresses of the gca agents
     * @param _glowToken the address of the glow token
     * @param _governance the address of the governance contract
     */
    constructor(address[] memory _gcaAgents, address _glowToken, address _governance)
        GCAV2(_gcaAgents, _glowToken, _governance, keccak256("FAKE DATA"))
    {}

    function setGCAs(address[] calldata newGcas) external {
        _setGCAs(newGcas);
    }

    function incrementSlashNonce() public {
        slashNonceToSlashTimestamp[slashNonce] = block.timestamp;
        ++slashNonce;
    }

    /**
     * @notice returns the WCEIL for the given slash nonce
     * @param _slashNonce the slash nonce
     * @return the WCEIL
     */
    function WCEIL(uint256 _slashNonce) public view returns (uint256) {
        return _WCEIL(_slashNonce);
    }

    function pushRequirementsHashMock(bytes32 hash) external {
        proposalHashes.push(hash);
    }

    function calculateBucketSubmissionEndTimestamp(uint256 id) public view returns (uint256) {
        return _calculateBucketSubmissionEndTimestamp(
            id,
            _buckets[id].originalNonce,
            _buckets[id].lastUpdatedNonce,
            slashNonce,
            _buckets[id].finalizationTimestamp
        );
    }

    function currentWeekInternal() public view returns (uint256) {
        _currentWeek();
    }
}

import "../GCA.sol";

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {GCASalaryHelper} from "../GCASalaryHelper.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {GCAV2} from "../GCAV2.sol";

contract MockGCAV2 is GCAV2 {
    error BARFSN();

    mapping(uint256 => mapping(uint256 => bool)) public slashNonceToBucketIdToResubmit;
    mapping(uint256 => bool) internal _isBucketClaimedFrom;
    /**
     * @notice constructs a new GCA contract
     * @param _gcaAgents the addresses of the gca agents
     * @param _glowToken the address of the glow token
     * @param _governance the address of the governance contract
     */

    constructor(address[] memory _gcaAgents, address _glowToken, address _governance)
        GCAV2(_gcaAgents, _glowToken, _governance, keccak256("FAKE DATA"))
    {}

    function setIsBucketClaimedFrom(uint256 bucketId, bool status) public {
        _isBucketClaimedFrom[bucketId] = status;
    }

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

    function calculateBucketSubmissionEndTimestamp(uint256 bucketId) public view returns (uint256) {
        (, uint256 submissionEndTimestamp,,) = getBucketSubmissionRange(bucketId);
        return submissionEndTimestamp;
    }

    function getBucketSubmissionRange(uint256 bucketId)
        public
        view
        returns (
            uint256, /*startSubmissionTimestamp*/
            uint256, /*endSubmissionTimestamp*/
            uint256, /*newSlashNonce*/
            uint256 /*newFinalizationTimestamp*/
        )
    {
        return _getBucketSubmissionRange(bucketId, slashNonce, bucket(bucketId));
    }

    function hasBucketBeenRequestedForResubmissionAtSlashNonce(uint256 _slashNonce, uint256 bucketId)
        public
        view
        virtual
        override
        returns (bool)
    {
        return slashNonceToBucketIdToResubmit[_slashNonce][bucketId];
    }

    function requestBucketForResubmission(uint256 bucketId) public {
        //If already true, revert
        if (slashNonceToBucketIdToResubmit[slashNonce][bucketId]) {
            revert BARFSN(); //Bucket already requested for slash nonce
        }
        slashNonceToBucketIdToResubmit[slashNonce][bucketId] = true;
        GCAV2._handleBucketRequestedResubmission(bucketId);
    }

    /**
     * @notice returns the end submission timestamp of a bucket
     *         - GCA's wont be able to submit if block.timestamp >= endSubmissionTimestamp
     * @param bucketId - the id of the bucket
     * @return the end submission timestamp of a bucket
     * @dev should not be used for reinstated buckets or buckets that need to be reinstated
     */
    function bucketEndSubmissionTimestampNotReinstated(uint256 bucketId) public view returns (uint128) {
        return SafeCast.toUint128(bucketStartSubmissionTimestampNotReinstated(bucketId) + bucketDuration());
    }

    /**
     * @notice returns the finalization timestamp of a bucket
     * @param bucketId - the id of the bucket
     * @return the finalization timestamp of a bucket
     * @dev should not be used for reinstated buckets or buckets that need to be reinstated
     */
    function bucketFinalizationTimestampNotReinstated(uint256 bucketId) public view returns (uint128) {
        return SafeCast.toUint128(bucketEndSubmissionTimestampNotReinstated(bucketId) + bucketDuration());
    }

    function isBucketClaimedFrom(uint256 bucketId) internal view override returns (bool) {
        return _isBucketClaimedFrom[bucketId];
    }

    function currentWeekInternal() public view returns (uint256) {
        _currentWeek();
    }

    function bucketDelayDuration() public pure virtual override returns (uint256) {
        return 13 weeks;
    }
}

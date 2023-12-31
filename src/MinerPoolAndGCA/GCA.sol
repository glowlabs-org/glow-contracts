// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IGCA} from "@/interfaces/IGCA.sol";
import {IGlow} from "@/interfaces/IGlow.sol";
import {GCASalaryHelper} from "./GCASalaryHelper.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {_BUCKET_DURATION} from "@/Constants/Constants.sol";

/**
 * @title GCA (Glow Certification Agent)
 * @author @DavidVorick
 * @author @0xSimon(twitter) - 0xSimon(github)
 *  @notice this contract is the entry point for GCAs to submit reports and claim payouts
 *  @notice GCA's submit weekly reports that contain how many carbon credits have been created
 *             - and which farms should get rewarded for the creation of those credits
 * @notice The weekly reports that GCA's submit into are called `buckets`
 * @notice Each `bucket` has a 1 week period for report submission
 *             - followed by a 1 week period before its finalized
 *             - during this finalization period, the veto council can decide to delay the bucket by 90 days
 *             - should they find anything suspicious in the bucket.
 *                - A delayed bucket should always finalize 90 days after the delay event
 *                - This should give governance enough time to slash the GCA that submitted the faulty report
 *                - This slash event causes all buckets that were not finalized at the time of the slash, to be permanently slashed
 *                - The exception is that the current GCA's have 1-2 weeks after the slash to reinstate the bucket
 *                - Reinstating the buckets deletes all the past reports and allows the GCAs to submit fresh reports
 *             - after the bucket has passed this finalization period, the bucket's rewards become available for distribution to solar farms,
 *                and the GCC created is minted and sent to the Carbon Credit Auction
 *             - These actions above take place in the `MinerPoolAndGCA` contract
 * @notice Governance has the ability to change and slash the GCA's.
 *
 */
contract GCA is IGCA, GCASalaryHelper {
    /* -------------------------------------------------------------------------- */
    /*                                  constants                                 */
    /* -------------------------------------------------------------------------- */
    /// @dev the return value if an index position is not found in an array
    uint256 private constant _INDEX_NOT_FOUND = type(uint256).max;

    /// @notice the shift to apply to the bitpacked compensation plans
    uint256 private constant _UINT24_SHIFT = 24;

    /// @notice the mask to apply to the bitpacked compensation plans
    uint256 private constant _UINT24_MASK = 0xFFFFFF;

    /// @dev 200 Billion in 18 decimals
    uint256 private constant _200_BILLION = 200_000_000_000 ether;

    /// @dev the max uint64 divided by 5
    /// @dev this is used to check if the total weight of a report is less than the max uint64 / 5
    /// @dev the max sum of all weights is type(uint64).max, so we can not allow an overflow by a bad
    uint256 private constant _UINT64_MAX_DIV5 = type(uint64).max / 5;

    /// @dev mask to apply a uint128 mask to a uint256
    /// @dev this is used to get the `finalizationTimestamp` from the `Bucket` struct
    ///     - which is a uint128 stored in the last 128 bits of the uint256
    uint256 internal constant _UINT128_MASK = (1 << 128) - 1;

    /// @dev mask to apply a uint64 mask to a uint256
    /// @dev this is used to get the `originalNonce` and `lastUpdatedNonce` from the `Bucket` struct
    /// -  `originalNonce` is a uint64 stored in the first 64 bits of the uint256
    /// -  `lastUpdatedNonce` is a uint64 stored in the second 64 bits of the uint256
    uint256 internal constant _UINT64_MASK = (1 << 64) - 1;

    /* -------------------------------------------------------------------------- */
    /*                                 immutables                                 */
    /* -------------------------------------------------------------------------- */
    /// @notice the address of the glow token
    IGlow public immutable GLOW_TOKEN;

    /// @notice the address of the governance contract
    address public immutable GOVERNANCE;

    /// @notice the timestamp of the genesis block
    uint256 public immutable GENESIS_TIMESTAMP;

    /* -------------------------------------------------------------------------- */
    /*                                 state vars                                */
    /* -------------------------------------------------------------------------- */
    /// @notice the index of the last proposal that was updated + 1
    uint256 public nextProposalIndexToUpdate;

    /// @notice the hashes of the proposals that have been submitted from {GOVERNANCE}
    bytes32[] public proposalHashes;

    /// @notice the addresses of the gca agents
    address[] public gcaAgents;

    /**
     * @notice the requirements hash of GCA Agents
     */
    bytes32 public requirementsHash;

    /**
     * @notice the current slash nonce
     */
    uint256 public slashNonce;

    /* -------------------------------------------------------------------------- */
    /*                                   mappings                                  */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice the timestamp of the slash event as [nonce]
     * @dev nonce -> slash timestamp
     */
    mapping(uint256 => uint256) public slashNonceToSlashTimestamp;

    /// @notice the gca payouts
    mapping(address => IGCA.GCAPayout) private _gcaPayouts;

    /// @notice bucket -> Bucket Struct
    mapping(uint256 => IGCA.Bucket) internal _buckets;

    /// @notice bucket -> Global State
    mapping(uint256 => IGCA.BucketGlobalState) internal _bucketGlobalState;

    /* -------------------------------------------------------------------------- */
    /*                                 constructor                                */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice constructs a new GCA contract
     * @param _gcaAgents the addresses of the gca agents the contract starts with
     * @param _glowToken the address of the glow token
     * @param _governance the address of the governance contract
     * @param _requirementsHash the requirements hash of GCA Agents
     */
    constructor(address[] memory _gcaAgents, address _glowToken, address _governance, bytes32 _requirementsHash)
        payable
        GCASalaryHelper(_gcaAgents)
    {
        //Set the glow token
        GLOW_TOKEN = IGlow(_glowToken);
        //Set governance
        GOVERNANCE = _governance;
        //Set the GCA's
        _setGCAs(_gcaAgents);
        //Set the genesis timestamp
        GENESIS_TIMESTAMP = GLOW_TOKEN.GENESIS_TIMESTAMP();
        //Initialize the payouts for the gcas
        for (uint256 i; i < _gcaAgents.length; ++i) {
            _gcaPayouts[_gcaAgents[i]].lastClaimedTimestamp = uint64(GENESIS_TIMESTAMP);
        }
        //Set the GCA requirements hash
        requirementsHash = _requirementsHash;
        GCASalaryHelper.setZeroPaymentStartTimestamp();
    }

    /* -------------------------------------------------------------------------- */
    /*                              submit comp plans                             */
    /* -------------------------------------------------------------------------- */
    /// @inheritdoc IGCA
    function submitCompensationPlan(uint32[5] calldata plan, uint256 indexOfGCA) external {
        _revertIfFrozen();
        uint256 gcaLength = gcaAgents.length;
        if (msg.sender != gcaAgents[indexOfGCA]) _revert(IGCA.CallerNotGCAAtIndex.selector);
        GCASalaryHelper.handleCompensationPlanSubmission(plan, indexOfGCA, gcaLength);
        emit IGCA.CompensationPlanSubmitted(msg.sender, plan);
    }

    /* -------------------------------------------------------------------------- */
    /*                              submitting reports                            */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice allows GCAs to submit a weekly report and emit {data}
     *         - {data} is a bytes array that can be used to emit any data
     *         - it could contain the merkle tree, or any other data
     *         - it is not strictly enforced and GCA's should communicate what they are emitting
     * @param bucketId - the id of the bucket
     * @param totalNewGCC - the total amount of GCC to be created from the report
     * @param totalGlwRewardsWeight - the total amount of glw rewards weight in the report
     * @param totalGRCRewardsWeight - the total amount of grc rewards weight in the report
     * @param root - the merkle root containing all the reports (leaves) for the period
     */
    function submitWeeklyReport(
        uint256 bucketId,
        uint256 totalNewGCC,
        uint256 totalGlwRewardsWeight,
        uint256 totalGRCRewardsWeight,
        bytes32 root
    ) external {
        _submitWeeklyReport(bucketId, totalNewGCC, totalGlwRewardsWeight, totalGRCRewardsWeight, root);
        emit IGCA.BucketSubmissionEvent(
            bucketId, msg.sender, slashNonce, totalNewGCC, totalGlwRewardsWeight, totalGRCRewardsWeight, root, ""
        );
    }

    /**
     * @notice allows GCAs to submit a weekly report and emit {data}
     *         - {data} is a bytes array that can be used to emit any data
     *         - it could contain the merkle tree, or any other data
     *         - it is not strictly enforced and GCA's should communicate what they are emitting
     * @param bucketId - the id of the bucket
     * @param totalNewGCC - the total amount of GCC to be created from the report
     * @param totalGlwRewardsWeight - the total amount of glw rewards weight in the report
     * @param totalGRCRewardsWeight - the total amount of grc rewards weight in the report
     * @param root - the merkle root containing all the reports (leaves) for the period
     * @param data - the data to emit
     */
    function submitWeeklyReportWithBytes(
        uint256 bucketId,
        uint256 totalNewGCC,
        uint256 totalGlwRewardsWeight,
        uint256 totalGRCRewardsWeight,
        bytes32 root,
        bytes calldata data
    ) external {
        _submitWeeklyReport(bucketId, totalNewGCC, totalGlwRewardsWeight, totalGRCRewardsWeight, root);
        emit IGCA.BucketSubmissionEvent(
            bucketId, msg.sender, slashNonce, totalNewGCC, totalGlwRewardsWeight, totalGRCRewardsWeight, root, data
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                              governance interaction                        */
    /* -------------------------------------------------------------------------- */
    /**
     * @inheritdoc IGCA
     */
    function setRequirementsHash(bytes32 _requirementsHash) external {
        if (msg.sender != GOVERNANCE) _revert(IGCA.CallerNotGovernance.selector);
        requirementsHash = _requirementsHash;
        emit IGCA.RequirementsHashUpdated(_requirementsHash);
    }

    /**
     * @inheritdoc IGCA
     */
    function pushHash(bytes32 hash, bool incrementSlashNonce) external {
        if (msg.sender != GOVERNANCE) _revert(IGCA.CallerNotGovernance.selector);
        if (incrementSlashNonce) {
            ++slashNonce;
        }
        proposalHashes.push(hash);
        emit IGCA.ProposalHashPushed(hash);
    }

    /**
     * @notice allows anyone to call this function to ensure that governance proposals are being taken into effect
     * @param gcasToSlash - the gca agents to slash
     * @param newGCAs - the new gca agents
     * @dev - this is a standalone function that anyone can call to ensure that
     *             - users dont pay too much gas when syncing proposals.
     * @dev if there is a hash to execute against, the contract will be frozen
     *             - if there is no hash to execute against, the contract will be available
     *             - to execute actions
     */
    function executeAgainstHash(
        address[] calldata gcasToSlash,
        address[] calldata newGCAs,
        uint256 proposalCreationTimestamp
    ) external {
        uint256 _nextProposalIndexToUpdate = nextProposalIndexToUpdate;
        uint256 len = proposalHashes.length;
        if (len == 0) _revert(IGCA.ProposalHashesEmpty.selector);
        bytes32 derivedHash = keccak256(abi.encode(gcasToSlash, newGCAs, proposalCreationTimestamp));
        //Slash nonce already get's incremented so we need to subtract 1
        if (gcasToSlash.length > 0) {
            slashNonceToSlashTimestamp[slashNonce - 1] = proposalCreationTimestamp;
        }
        if (proposalHashes[_nextProposalIndexToUpdate] != derivedHash) {
            _revert(IGCA.ProposalHashDoesNotMatch.selector);
        }

        GCASalaryHelper.callbackInElectionEvent(newGCAs);
        _setGCAs(newGCAs);
        _slashGCAs(gcasToSlash);
        nextProposalIndexToUpdate = _nextProposalIndexToUpdate + 1;
        emit IGCA.ProposalHashUpdate(_nextProposalIndexToUpdate, derivedHash);
    }

    /* -------------------------------------------------------------------------- */
    /*                                 glow inflation                             */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice - an open function to claim the glow from inflation
     */
    function claimGlowFromInflation() public virtual {
        _claimGlowFromInflation();
    }

    /* -------------------------------------------------------------------------- */
    /*                                 view functions                             */
    /* -------------------------------------------------------------------------- */
    /// @inheritdoc IGCA
    function isGCA(address account, uint256 index) public view returns (bool) {
        if (_isFrozen()) return false;
        return gcaAgents[index] == account;
    }

    /// @inheritdoc IGCA
    function isGCA(address account) public view returns (bool) {
        if (_isFrozen()) return false;
        uint256 len = gcaAgents.length;
        unchecked {
            for (uint256 i; i < len; ++i) {
                if (gcaAgents[i] == account) return true;
            }
        }
        return false;
    }

    /// @inheritdoc IGCA
    function allGcas() public view returns (address[] memory) {
        return gcaAgents;
    }

    /// @inheritdoc IGCA
    function gcaPayoutData(address gca) public view returns (IGCA.GCAPayout memory) {
        return _gcaPayouts[gca];
    }

    /**
     * @inheritdoc IGCA
     */
    function getProposalHashes() external view returns (bytes32[] memory) {
        return proposalHashes;
    }

    /**
     * @inheritdoc IGCA
     */
    function getProposalHashes(uint256 start, uint256 end) external view returns (bytes32[] memory) {
        if (end > proposalHashes.length) end = proposalHashes.length;
        if (start > end) return new bytes32[](0);
        bytes32[] memory result = new bytes32[](end - start);
        unchecked {
            for (uint256 i = start; i < end; ++i) {
                result[i - start] = proposalHashes[i];
            }
        }
        return result;
    }

    /**
     * @inheritdoc IGCA
     */
    function bucketGlobalState(uint256 bucketId) external view returns (IGCA.BucketGlobalState memory) {
        return _bucketGlobalState[bucketId];
    }

    /**
     * @notice returns the start submission timestamp of a bucket
     * @param bucketId - the id of the bucket
     * @return the start submission timestamp of a bucket
     * @dev should not be used for reinstated buckets or buckets that need to be reinstated
     */
    function bucketStartSubmissionTimestampNotReinstated(uint256 bucketId) public view returns (uint128) {
        return SafeCast.toUint128(bucketId * bucketDuration() + GENESIS_TIMESTAMP);
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

    /**
     * @inheritdoc IGCA
     */
    function bucket(uint256 bucketId) public view returns (IGCA.Bucket memory bucket) {
        return _buckets[bucketId];
    }

    /**
     * @inheritdoc IGCA
     */
    function isBucketFinalized(uint256 bucketId) public view returns (bool) {
        uint256 packedData;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(0x0, bucketId)
            mstore(0x20, _buckets.slot)
            let slot := keccak256(0x0, 0x40)
            // nonce, reinstated and finalizationTimestamp are all in the first slot
            packedData := sload(slot)
        }

        uint256 bucketLastUpdatedNonce = (packedData >> 64) & _UINT64_MASK;
        //First bit.
        //first 64 bits are originalNonce, next 64 bits are lastUpdatedNonce, last 128 bits are finalizationTimestamp
        //no need to us to use a mask since finalizationTimestamp takes up the last 128 bits
        uint256 finalizationTimestamp = packedData >> 128;

        uint256 _slashNonce = slashNonce;
        return _isBucketFinalized(bucketLastUpdatedNonce, finalizationTimestamp, _slashNonce);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   internal                                 */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice allows GCAs to submit a weekly report and emit {data}
     *         - {data} is a bytes array that can be used to emit any data
     *         - it could contain the merkle tree, or any other data
     *         - it is not strictly enforced and GCA's should communicate what they are emitting
     * @param bucketId - the id of the bucket
     * @param totalNewGCC - the total amount of GCC to be created from the report
     * @param totalGlwRewardsWeight - the total amount of glw rewards weight in the report
     * @param totalGRCRewardsWeight - the total amount of grc rewards weight in the report
     * @param root - the merkle root containing all the reports (leaves) for the period
     */

    function _submitWeeklyReport(
        uint256 bucketId,
        uint256 totalNewGCC,
        uint256 totalGlwRewardsWeight,
        uint256 totalGRCRewardsWeight,
        bytes32 root
    ) internal {
        //GCAs can't submit if the contract is frozen (pending a proposal hash update)
        _revertIfFrozen();
        if (!isGCA(msg.sender)) _revert(NotGCA.selector);
        checkBucketSubmissionArithmeticInputs(totalGlwRewardsWeight, totalGRCRewardsWeight, totalNewGCC);
        //Need to check if bucket is slashed
        Bucket storage bucket = _buckets[bucketId];
        //Cache values
        uint256 len = bucket.reports.length;
        {
            uint256 bucketFinalizationTimestamp = bucket.finalizationTimestamp;

            uint256 lastUpdatedNonce = bucket.lastUpdatedNonce;
            //Get the submission start itimestamp
            uint256 bucketSubmissionStartTimestamp = bucketStartSubmissionTimestampNotReinstated(bucketId);
            if (block.timestamp < bucketSubmissionStartTimestamp) _revert(IGCA.BucketSubmissionNotOpen.selector);

            //Keep in mind, all bucketNonces start with 0
            //So on the first init, we need to set the bucketNonce to the slashNonce in storage
            {
                uint256 _slashNonce = slashNonce;
                //If not inititialized, intitialize the bucket
                if (bucketFinalizationTimestamp == 0) {
                    bucket.originalNonce = SafeCast.toUint64(_slashNonce);
                    bucket.lastUpdatedNonce = SafeCast.toUint64(_slashNonce);
                    bucket.finalizationTimestamp =
                        SafeCast.toUint128(bucketFinalizationTimestampNotReinstated(bucketId));
                    lastUpdatedNonce = _slashNonce;
                }

                {
                    /**
                     * If the bucket needs to be reinstated
                     *             we need to update the bucket accordingly
                     *             and we need to change the finalization timestamp
                     *             lastly, we need to delete all reports in storage if there are any
                     */
                    uint256 bucketSubmissionEndTimestamp = _calculateBucketSubmissionEndTimestamp(
                        bucketId, bucket.originalNonce, lastUpdatedNonce, _slashNonce, bucketFinalizationTimestamp
                    );
                    if (block.timestamp >= bucketSubmissionEndTimestamp) _revert(IGCA.BucketSubmissionEnded.selector);

                    if (lastUpdatedNonce != _slashNonce) {
                        bucket.lastUpdatedNonce = SafeCast.toUint64(_slashNonce);
                        //Need to check before storing the finalization timestamp in case
                        //the bucket was delayed.
                        if (bucketSubmissionEndTimestamp + bucketDuration() > bucketFinalizationTimestamp) {
                            bucket.finalizationTimestamp =
                                SafeCast.toUint128(bucketSubmissionEndTimestamp + bucketDuration());
                        }
                        //conditionally delete all reports in storage
                        if (len > 0) {
                            len = 0;
                            //delete all reports in storage
                            //by setting the length to 0
                            // solhint-disable-next-line no-inline-assembly
                            assembly {
                                //1 slot offset for buckets length
                                sstore(add(1, bucket.slot), 0)
                            }
                            delete _bucketGlobalState[bucketId];
                        }
                    }
                }
            }
        }
        uint256 reportArrayStartSlot;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            //add 1 for reports offset
            mstore(0x0, add(bucket.slot, 1))
            // hash the reports start slot to get the start of the data
            reportArrayStartSlot := keccak256(0x0, 0x20)
        }

        (uint256 foundIndex, uint256 gcaReportStartSlot) = findReportIndexOrUintMax(reportArrayStartSlot, len);
        handleGlobalBucketStateStore(
            totalNewGCC, totalGlwRewardsWeight, totalGRCRewardsWeight, bucketId, foundIndex, gcaReportStartSlot
        );
        handleBucketStore(bucket, foundIndex, totalNewGCC, totalGlwRewardsWeight, totalGRCRewardsWeight, root);
    }

    /**
     * @dev handles the store for a new report in a bucket
     * @param gcaTotalNewGCC - the total amount of new gcc that the gca is reporting
     * @param gcaTotalGlwRewardsWeight - the total amount of glw rewards weight that the gca is reporting
     * @param gcaTotalGRCRewardsWeight - the total amount of grc rewards weight that the gca is reporting
     * @param bucketId - the id of the bucket
     * @param foundIndex - the index of the report in the bucket
     * @param gcaReportStartSlot - the start slot of the gca report
     */
    function handleGlobalBucketStateStore(
        uint256 gcaTotalNewGCC,
        uint256 gcaTotalGlwRewardsWeight,
        uint256 gcaTotalGRCRewardsWeight,
        uint256 bucketId,
        uint256 foundIndex,
        uint256 gcaReportStartSlot
    ) internal {
        uint256 packedGlobalState;
        uint256 slot;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(0x0, bucketId)
            mstore(0x20, _bucketGlobalState.slot)
            slot := keccak256(0x0, 0x40)
            packedGlobalState := sload(slot)
        }

        uint256 gccInBucketPlusGcaGcc = (packedGlobalState & _UINT128_MASK) + gcaTotalNewGCC;
        uint256 glwWeightInBucketPlusGcaGlwWeight = (packedGlobalState >> 128 & _UINT64_MASK) + gcaTotalGlwRewardsWeight;
        //No need to shift on `grcWeightInBucketPlusGcaGrcWeight` since  the grcWeight is the last 64 bits
        uint256 grcWeightInBucketPlusGcaGrcWeight = (packedGlobalState >> 192) + gcaTotalGRCRewardsWeight;

        if (foundIndex == 0) {
            //gcc is uint128, glwWeight is uint64, grcWeight is uint64
            packedGlobalState = gccInBucketPlusGcaGcc | (glwWeightInBucketPlusGcaGlwWeight << 128)
                | (grcWeightInBucketPlusGcaGrcWeight << 192);
            // solhint-disable-next-line no-inline-assembly
            assembly {
                sstore(slot, packedGlobalState)
            }
            return;
        }

        uint256 packedDataInReport;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            packedDataInReport := sload(gcaReportStartSlot)
        }

        gccInBucketPlusGcaGcc -= packedDataInReport & _UINT128_MASK;
        glwWeightInBucketPlusGcaGlwWeight -= (packedDataInReport >> 128) & _UINT64_MASK;
        //no need to mask since the grcWeight is the last 64 bits
        grcWeightInBucketPlusGcaGrcWeight -= (packedDataInReport >> 192);

        packedGlobalState = gccInBucketPlusGcaGcc | (glwWeightInBucketPlusGcaGlwWeight << 128)
            | (grcWeightInBucketPlusGcaGrcWeight << 192);
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(slot, packedGlobalState)
        }
    }

    function _transferGlow(address to, uint256 amount) internal override(GCASalaryHelper) {
        GLOW_TOKEN.transfer(to, amount);
    }

    /// @dev claims the glow from inflation
    function _claimGlowFromInflation() internal virtual override(GCASalaryHelper) {
        GLOW_TOKEN.claimGLWFromGCAAndMinerPool();
    }

    /**
     * @dev handles the store for a new report in a bucket
     * @param bucket - the bucket to store the report in
     * @param foundIndex - the index of the report in the bucket
     * @param totalNewGCC - the total amount of new gcc that the gca is reporting
     * @param totalGlwRewardsWeight - the total amount of glw rewards weight that the gca is reporting
     * @param totalGRCRewardsWeight - the total amount of grc rewards weight that the gca is reporting
     * @param root - the merkle root containing all the reports (leaves) for the period
     */
    function handleBucketStore(
        IGCA.Bucket storage bucket,
        uint256 foundIndex,
        uint256 totalNewGCC,
        uint256 totalGlwRewardsWeight,
        uint256 totalGRCRewardsWeight,
        bytes32 root
    ) internal {
        //If the array was empty
        // we need to push
        if (foundIndex == 0) {
            bucket.reports.push(
                IGCA.Report({
                    proposingAgent: msg.sender,
                    totalNewGCC: SafeCast.toUint128(totalNewGCC),
                    totalGLWRewardsWeight: SafeCast.toUint64(totalGlwRewardsWeight),
                    totalGRCRewardsWeight: SafeCast.toUint64(totalGRCRewardsWeight),
                    merkleRoot: root
                })
            );
            //else we write the the index we found
        } else {
            bucket.reports[foundIndex == _INDEX_NOT_FOUND ? 0 : foundIndex] = IGCA.Report({
                //Redundant sstore on {proposingAgent}
                proposingAgent: msg.sender,
                totalNewGCC: SafeCast.toUint128(totalNewGCC),
                totalGLWRewardsWeight: SafeCast.toUint64(totalGlwRewardsWeight),
                totalGRCRewardsWeight: SafeCast.toUint64(totalGRCRewardsWeight),
                merkleRoot: root
            });
        }
    }

    /**
     * @dev sets the gca agents
     *         -  removes all previous gca agents
     *         -  sets the new gca agents
     */
    function _setGCAs(address[] memory gcaAddresses) internal {
        gcaAgents = gcaAddresses;
        emit IGCA.NewGCAsAppointed(gcaAddresses);
    }

    /**
     * @dev slashes the gca agents
     * @param gcasToSlash - the gca agents to slash
     */
    function _slashGCAs(address[] memory gcasToSlash) internal {
        unchecked {
            for (uint256 i; i < gcasToSlash.length; ++i) {
                GCASalaryHelper._slash(gcasToSlash[i]);
            }
        }
        emit IGCA.GCAsSlashed(gcasToSlash);
    }

    /* -------------------------------------------------------------------------- */
    /*                        internal / private view functions                   */
    /* -------------------------------------------------------------------------- */
    /**
     * @dev checks if the weights are valid
     *     - this check is necessary to ensure that GCA's cant cause the weights to overflow in their reports
     *     - and also ensures that the total new gcc minted isnt greated than 200 billion * number of gcas
     * @param totalGlwRewardsWeight - the total amount of glw rewards weight
     * @param totalGRCRewardsWeight - the total amount of grc rewards weight
     * @param totalNewGCC - the total amount of new gcc
     */
    function checkBucketSubmissionArithmeticInputs(
        uint256 totalGlwRewardsWeight,
        uint256 totalGRCRewardsWeight,
        uint256 totalNewGCC
    ) internal pure {
        //Arithmetic Checks
        //To make sure that the weight's dont result in an overflow,
        // we need to make sure that the total weight is less than 1/5 of the max uint64
        if (totalGlwRewardsWeight > _UINT64_MAX_DIV5) _revert(IGCA.ReportWeightMustBeLTUint64MaxDiv5.selector);
        if (totalGRCRewardsWeight > _UINT64_MAX_DIV5) _revert(IGCA.ReportWeightMustBeLTUint64MaxDiv5.selector);
        //Max of 1 trillion GCC per week
        //Since there are a max of 5 GCA's at any point in time,
        // this means that the max amount of GCC that can be minted per GCA is 200 Billion
        if (totalNewGCC > _200_BILLION) _revert(IGCA.ReportGCCMustBeLT200Billion.selector);
    }

    /**
     * @dev finds the index of the report in the bucket
     *             - if the report is not found, it returns _INDEX_NOT_FOUND
     * @param reportArrayStartSlot - the storage start slot of the reports
     * @param len - the length of the reports array
     * @return foundIndex - the index of the report in the bucket
     * @return gcaReportStartSlot - the start slot of the report in storage
     */
    function findReportIndexOrUintMax(uint256 reportArrayStartSlot, uint256 len)
        internal
        view
        returns (uint256 foundIndex, uint256)
    {
        unchecked {
            {
                for (uint256 i; i < len; ++i) {
                    address proposingAgent;
                    // solhint-disable-next-line no-inline-assembly
                    assembly {
                        //the address is stored in the [0,1,2] - 3rd slot
                        //                                  ^
                        //that means the slot to read from is i*3 + startSlot + 2
                        proposingAgent := sload(add(reportArrayStartSlot, 2))
                        reportArrayStartSlot := add(reportArrayStartSlot, 3)
                    }
                    if (proposingAgent == msg.sender) {
                        foundIndex = i == 0 ? _INDEX_NOT_FOUND : i;
                        // solhint-disable-next-line no-inline-assembly
                        assembly {
                            //since we incremented the slot by 3, we need to decrement it by 3 to get the start of the packed data
                            reportArrayStartSlot := sub(reportArrayStartSlot, 3)
                        }
                        break;
                    }
                }
            }
        }
        //Increased readability
        uint256 gcaReportStartSlot = reportArrayStartSlot;
        return (foundIndex, gcaReportStartSlot);
    }

    /**
     * @notice returns the length (in seconds) of a bucket duration
     * @return the length (in seconds) of a bucket duration
     */
    function bucketDuration() internal pure virtual override returns (uint256) {
        return _BUCKET_DURATION;
    }

    /**
     * @dev an efficient function to get the merkle root of a bucket at a given index
     * @param bucketId - the bucket id to find the root for
     * @param index - the index of the report in the reports[] array for the bucket
     * @return root - the merkle root for the report for the given bucket at the specific index
     */

    function getBucketRootAtIndexEfficient(uint256 bucketId, uint256 index) internal view returns (bytes32 root) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            //Store the key
            mstore(0x0, bucketId)
            //Store the slot
            mstore(0x20, _buckets.slot)
            //Find storage slot where bucket starts
            let slot := keccak256(0x0, 0x40)
            //Reports start at the second slot so we add 1
            slot := add(slot, 1)

            //Check length
            let len := sload(slot)
            if gt(add(index, 1), len) {
                //cast sig "BucketIndexOutOfBounds()"
                mstore(0x0, 0xfdbe8876)
                revert(0x1c, 0x04)
            }

            mstore(0x0, slot)
            //calculate slot for the reports
            slot := keccak256(0x0, 0x20)
            //slot is now the start of the reports
            //each report is 3 slots long
            //So, our index needs to be multiplied by 3
            index := mul(index, 3)
            //the root is the second slot so we need to add 1
            index := add(index, 1)
            //Calculate the slot to sload from
            slot := add(slot, index)
            //sload the root
            root := sload(slot)
        }

        if (uint256(root) == 0) _revert(IGCA.EmptyRoot.selector);
    }

    /**
     * @dev a function that reverts if proposal hashes are not up to date
     */
    function _revertIfFrozen() internal view {
        if (_isFrozen()) _revert(IGCA.ProposalHashesNotUpdated.selector);
    }

    /// @dev returns true if the contract is frozen, false otherwise
    function _isFrozen() internal view returns (bool) {
        uint256 len = proposalHashes.length;
        //If no proposals have been submitted, we don't need to check
        if (len == 0) return false;
        if (len != nextProposalIndexToUpdate) {
            return true;
        }
        return false;
    }

    /**
     * @dev checks if a bucket is finalized
     * @param bucketLastUpdatedNonce the last updated nonce of the bucket
     * @param bucketFinalizationTimestamp the finalization timestamp of the bucket
     * @param _slashNonce the current slash nonce
     * @return true if the bucket is finalized, false otherwise
     */
    function _isBucketFinalized(
        uint256 bucketLastUpdatedNonce,
        uint256 bucketFinalizationTimestamp,
        uint256 _slashNonce
    ) internal view returns (bool) {
        //If the bft(bucket finalization timestamp) = 0,
        // that means that bucket hasn't been initialized yet
        // so that also means it's not finalized.
        // this also means that we return false if
        // the bucket was indeed finalized. but it was never pushed to
        // in that case, we return a false negative,
        // but it has no side effects since the bucket is empty
        // and no one can claim rewards from it.
        if (bucketFinalizationTimestamp == 0) return false;

        //This checks if the bucket has finalized in regards to the timestamp stored
        bool finalized = block.timestamp >= bucketFinalizationTimestamp;
        //If there hasn't been a slash event and the bucket is finalized
        // then we return true;
        if (bucketLastUpdatedNonce == _slashNonce) {
            if (finalized) return true;
        }

        //If there has been a slash event
        if (bucketLastUpdatedNonce != _slashNonce) {
            //If the slash event happened after the bucket's finalization timestamp
            //That means the bucket had already been finalized and we can return true;
            if (slashNonceToSlashTimestamp[bucketLastUpdatedNonce] >= bucketFinalizationTimestamp) {
                if (finalized) {
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * @dev will underflow and revert if slashNonceToSlashTimestamp[_slashNonce] has not yet been written to
     * @dev returns the WCEIL for the given slash nonce.
     * @dev WCEIL is equal to the end bucket submission time for the bucket that the slash nonce was slashed in + 2 weeks
     * @dev it's two weeks instead of one to make sure there is adequate time for GCA's to submit reports
     * @dev the finalization timestamp is the end of the submission period + 1 week
     */
    function _WCEIL(uint256 _slashNonce) internal view returns (uint256) {
        //This will underflow if slashNonceToSlashTimestamp[_slashNonce] has not yet been written to
        uint256 bucketNonceWasSlashedAt =
            (slashNonceToSlashTimestamp[_slashNonce] - GENESIS_TIMESTAMP) / bucketDuration();
        //the end submission period is the bucket + 2
        return (bucketNonceWasSlashedAt + 2) * bucketDuration() + GENESIS_TIMESTAMP;
    }

    function getPackedBucketGlobalState(uint256 bucketId) internal view returns (uint256 packedGlobalState) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(0x0, bucketId)
            mstore(0x20, _bucketGlobalState.slot)
            let slot := keccak256(0x0, 0x40)
            packedGlobalState := sload(slot)
        }
    }

    /**
     * @notice calculates the bucket submission end timestamp
     * @param bucketId - the id of the bucket
     * @param bucketOriginNonce - the original nonce of the bucket
     * @param bucketLastUpdatedNonce - the last updated nonce of the bucket
     * @param _slashNonce - the current slash nonce
     * @param bucketFinalizationTimestamp - the finalization timestamp of the bucket
     * @dev this function is used to calculate the bucket submission start timestamp
     *     - under normal conditions, a bucket should be finalized 2 weeks after its submission period has open
     *     - however, if a slash event occurs, the bucket submission start timestamp will be shifted to the WCEIL() of the slash nonce
     *     - if the slash event occurs after the bucket has been finalized, the bucket submission start timestamp will be shifted to the WCEIL() of the slash nonce
     *         - this is to ensure the gcas have enough time to reinstante proper reports
     */
    function _calculateBucketSubmissionEndTimestamp(
        uint256 bucketId,
        uint256 bucketOriginNonce,
        uint256 bucketLastUpdatedNonce,
        uint256 _slashNonce,
        uint256 bucketFinalizationTimestamp
    ) internal view returns (uint256) {
        // if the bucket has never been initialized
        if (bucketFinalizationTimestamp == 0) return bucketEndSubmissionTimestampNotReinstated(bucketId);
        if (bucketOriginNonce == _slashNonce) return bucketEndSubmissionTimestampNotReinstated(bucketId);
        if (bucketLastUpdatedNonce == _slashNonce) return bucketFinalizationTimestamp;
        uint256 bucketSubmissionStartTimestamp = bucketStartSubmissionTimestampNotReinstated(bucketId);
        //If the slash occurred between the start of the submission period and the bucket finalization timestamp
        for (uint256 i = bucketLastUpdatedNonce; i < _slashNonce;) {
            if (_between(slashNonceToSlashTimestamp[i], bucketSubmissionStartTimestamp, bucketFinalizationTimestamp)) {
                bucketSubmissionStartTimestamp = _WCEIL(i);
            } else {
                break;
            }
            unchecked {
                ++i;
            }
        }
        return bucketSubmissionStartTimestamp;
    }

    /**
     * @dev checks if `a` is between `b` and `c`
     * @param a the number to check
     * @param b the lower bound
     * @param c the upper bound
     * @return true if `a` is between `b` and `c`, false otherwise
     */
    function _between(uint256 a, uint256 b, uint256 c) internal pure returns (bool) {
        return a >= b && a <= c;
    }

    function _genesisTimestamp() internal view virtual override(GCASalaryHelper) returns (uint256) {
        return GENESIS_TIMESTAMP;
    }

    /**
     * @dev calculates the shift to apply to the bitpacked compensation plans
     *     @param index - the index of the gca agent
     *     @return the shift to apply to the bitpacked compensation plans
     */
    function _calculateShift(uint256 index) private pure returns (uint256) {
        return index * _UINT24_SHIFT;
    }

    /* -------------------------------------------------------------------------- */
    /*                             functions to override                           */
    /* -------------------------------------------------------------------------- */
    /// @dev this must be overriden to return the current week in the parent contract
    function _currentWeek() internal view virtual override(GCASalaryHelper) returns (uint256) {
        // solhint-disable-next-line reason-string, custom-errors
        revert();
    }

    /// @dev returns the domain seperator for the current contract, must be overriden
    function _domainSeperatorV4Main() internal view virtual override(GCASalaryHelper) returns (bytes32) {
        // solhint-disable-next-line reason-string, custom-errors
        revert();
    }
}

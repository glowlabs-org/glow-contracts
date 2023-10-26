// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IGCA} from "@/interfaces/IGCA.sol";
import {IGlow} from "@/interfaces/IGlow.sol";
import {GCASalaryHelper} from "./GCASalaryHelper.sol";

/**
 * @title GCA (Glow Certification Agent)
 * @author @DavidVorick
 * @author @0xSimon
 */

contract GCA is IGCA, GCASalaryHelper {
    /// @notice the address of the glow token
    IGlow public immutable GLOW_TOKEN;

    /// @notice the address of the governance contract
    address public immutable GOVERNANCE;

    /// @notice the timestamp of the genesis block
    uint256 public immutable GENESIS_TIMESTAMP;

    /// @notice the shift to apply to the bitpacked compensation plans
    uint256 private constant _UINT24_SHIFT = 24;

    /// @notice the mask to apply to the bitpacked compensation plans
    uint256 private constant _UINT24_MASK = 0xFFFFFF;

    /// @dev 200 Billion in 18 decimals
    uint256 private constant _200_BILLION = 200_000_000_000 ether;

    uint256 private constant _UINT64_MAX_DIV5 = type(uint64).max / 5;

    uint256 internal constant _UINT128_MASK = (1 << 128) - 1;
    uint256 internal constant _UINT64_MASK = (1 << 64) - 1;
    uint256 private constant _BOOL_MASK = (1 << 8) - 1;
    uint256 private constant _UINT184_MASK = (1 << 184) - 1;

    // 1 week
    uint256 private constant BUCKET_LENGTH = 7 * uint256(1 days);

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
        GLOW_TOKEN = IGlow(_glowToken);
        GOVERNANCE = _governance;
        _setGCAs(_gcaAgents);
        GENESIS_TIMESTAMP = GLOW_TOKEN.GENESIS_TIMESTAMP();
        for (uint256 i; i < _gcaAgents.length; ++i) {
            _gcaPayouts[_gcaAgents[i]].lastClaimedTimestamp = uint64(GENESIS_TIMESTAMP);
        }
        requirementsHash = _requirementsHash;
        GCASalaryHelper.setZeroPaymentStartTimestamp();
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
    function isGCA(address account, uint256 index) public view returns (bool) {
        if (_isFrozen()) return false;
        return gcaAgents[index] == account;
    }

    /// @inheritdoc IGCA
    function submitCompensationPlan(uint32[5] calldata plan, uint256 indexOfGCA) external {
        _revertIfFrozen();
        uint256 gcaLength = gcaAgents.length;
        if (msg.sender != gcaAgents[indexOfGCA]) _revert(IGCA.CallerNotGCAAtIndex.selector);
        GCASalaryHelper.handleCompensationPlanSubmission(plan, indexOfGCA, gcaLength);
        // emit IGCA.CompensationPlanSubmitted(msg.sender, plans);
    }

    function issueWeeklyReport(
        uint256 bucketId,
        uint256 totalNewGCC,
        uint256 totalGlwRewardsWeight,
        uint256 totalGRCRewardsWeight,
        bytes32 root
    ) external {
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
            //The submission start timestamp always remains the same
            uint256 bucketSubmissionStartTimestamp = bucketStartSubmissionTimestampNotReinstated(bucketId);
            if (block.timestamp < bucketSubmissionStartTimestamp) _revert(IGCA.BucketSubmissionNotOpen.selector);

            //Keep in mind, all bucketNonces start with 0
            //So on the first init, we need to set the bucketNonce to the slashNonce in storage
            {
                uint256 _slashNonce = slashNonce;
                //If not init
                if (bucketFinalizationTimestamp == 0) {
                    bucket.originalNonce = uint64(_slashNonce);
                    bucket.lastUpdatedNonce = uint64(_slashNonce);
                    bucket.finalizationTimestamp = uint128(bucketFinalizationTimestampNotReinstated(bucketId));
                    lastUpdatedNonce = _slashNonce;
                }

                {
                    /**
                     * If it is a reinstating tx,
                     *             we need to set reinstated to true
                     *             and we need to change the finalization timestamp
                     *             lastly, we need to delete all reports in storage if there are any
                     */
                    uint256 bucketSubmissionEndTimestamp = _calculateBucketSubmissionEndTimestamp(
                        bucketId, bucket.originalNonce, lastUpdatedNonce, _slashNonce, bucketFinalizationTimestamp
                    );
                    if (block.timestamp >= bucketSubmissionEndTimestamp) _revert(IGCA.BucketSubmissionEnded.selector);

                    if (lastUpdatedNonce != _slashNonce) {
                        bucket.lastUpdatedNonce = uint64(_slashNonce);
                        //Need to check before storing the finalization timestamp in case
                        //the bucket was delayed.
                        if (bucketSubmissionEndTimestamp + BUCKET_LENGTH > bucketFinalizationTimestamp) {
                            bucket.finalizationTimestamp = uint128(bucketSubmissionEndTimestamp + BUCKET_LENGTH);
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

    function checkBucketSubmissionArithmeticInputs(
        uint256 totalGlwRewardsWeight,
        uint256 totalGRCRewardsWeight,
        uint256 totalNewGCC
    ) internal {
        //Arithmetic Checks
        //To make sure that the weight's dont result in an overflow,
        // we need to make sure that the total weight is less than 1/5 of the max uint256
        if (totalGlwRewardsWeight > _UINT64_MAX_DIV5) _revert(IGCA.ReportWeightMustBeLTUint64MaxDiv5.selector);
        if (totalGRCRewardsWeight > _UINT64_MAX_DIV5) _revert(IGCA.ReportWeightMustBeLTUint64MaxDiv5.selector);
        //Max of 1 trillion GCC per week
        //Since there are a max of 5 GCA's at any point in time,
        // this means that the max amount of GCC that can be minted per GCA is 200 Billion
        if (totalNewGCC > _200_BILLION) _revert(IGCA.ReportGCCMustBeLT200Billion.selector);
    }

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
                        foundIndex = i == 0 ? type(uint256).max : i;
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

        return (foundIndex, reportArrayStartSlot);
    }

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
                    totalNewGCC: uint128(totalNewGCC),
                    totalGLWRewardsWeight: uint64(totalGlwRewardsWeight),
                    totalGRCRewardsWeight: uint64(totalGRCRewardsWeight),
                    merkleRoot: root
                })
            );
            //else we write the the index we found
        } else {
            bucket.reports[foundIndex == type(uint256).max ? 0 : foundIndex] = IGCA.Report({
                //Redundant sstore on {proposingAgent}
                proposingAgent: msg.sender,
                totalNewGCC: uint128(totalNewGCC),
                totalGLWRewardsWeight: uint64(totalGlwRewardsWeight),
                totalGRCRewardsWeight: uint64(totalGRCRewardsWeight),
                merkleRoot: root
            });
        }
    }

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

    function setRequirementsHash(bytes32 _requirementsHash) external {
        if (msg.sender != GOVERNANCE) _revert(IGCA.CallerNotGovernance.selector);
        requirementsHash = _requirementsHash;
        emit IGCA.RequirementsHashUpdated(_requirementsHash);
    }

    function pushHash(bytes32 hash, bool incrementSlashNonce) external {
        if (msg.sender != GOVERNANCE) _revert(IGCA.CallerNotGovernance.selector);
        if (incrementSlashNonce) {
            ++slashNonce;
        }
        proposalHashes.push(hash);
    }

    //************************************************************* */
    //*****************  PUBLIC VIEW FUNCTIONS    ************** */
    //************************************************************* */

    // /// @inheritdoc IGCA
    // function compensationPlan(address gca) public view returns (IGCA.ICompensation[] memory) {
    //     return _compensationPlan(gca, gcaAgents);
    // }

    // function _compensationPlan(address gca, address[] memory gcaAddresses)
    //     internal
    //     view
    //     returns (IGCA.ICompensation[] memory)
    // {
    //     if (!isGCA(gca)) {
    //         _revert(NotGCA.selector);
    //     }
    //     uint256 bitpackedPlans = _compensationPlans[gca];
    //     uint256 gcaLength = gcaAddresses.length;
    //     IGCA.ICompensation[] memory plans = new IGCA.ICompensation[](gcaLength);
    //     for (uint256 i; i < gcaLength; ++i) {
    //         plans[i].shares = uint80((bitpackedPlans >> _calculateShift(i)) & _UINT24_MASK);
    //         plans[i].agent = gcaAddresses[i];
    //     }

    //     return plans;
    // }

    function claimGlowFromInflation() public virtual {
        _claimGlowFromInflation();
    }

    /// @inheritdoc IGCA
    function allGcas() public view returns (address[] memory) {
        return gcaAgents;
    }

    /// @inheritdoc IGCA
    function gcaPayoutData(address gca) public view returns (IGCA.GCAPayout memory) {
        return _gcaPayouts[gca];
    }

    function getProposalHashes() external view returns (bytes32[] memory) {
        return proposalHashes;
    }

    function getProposalHashes(uint256 start, uint256 end) external view returns (bytes32[] memory) {
        if (end > proposalHashes.length) end = proposalHashes.length;
        if (start > end) return new bytes32[](0);
        bytes32[] memory result = new bytes32[](end-start);
        unchecked {
            for (uint256 i = start; i < end; ++i) {
                result[i - start] = proposalHashes[i];
            }
        }
        return result;
    }

    /**
     * @notice returns the start submission timestamp of a bucket
     * @param bucketId - the id of the bucket
     * @return the start submission timestamp of a bucket
     * @dev should not be used for reinstated buckets or buckets that need to be reinstated
     */
    function bucketStartSubmissionTimestampNotReinstated(uint256 bucketId) public view returns (uint128) {
        return _castToUint128OrMax(bucketId * BUCKET_LENGTH + GENESIS_TIMESTAMP);
    }

    /**
     * @notice returns the end submission timestamp of a bucket
     *         - GCA's wont be able to submit if block.timestamp >= endSubmissionTimestamp
     * @param bucketId - the id of the bucket
     * @return the end submission timestamp of a bucket
     * @dev should not be used for reinstated buckets or buckets that need to be reinstated
     */
    function bucketEndSubmissionTimestampNotReinstated(uint256 bucketId) public view returns (uint128) {
        return _castToUint128OrMax(bucketStartSubmissionTimestampNotReinstated(bucketId) + BUCKET_LENGTH);
    }

    /**
     * @notice returns the finalization timestamp of a bucket
     * @param bucketId - the id of the bucket
     * @return the finalization timestamp of a bucket
     * @dev should not be used for reinstated buckets or buckets that need to be reinstated
     */
    function bucketFinalizationTimestampNotReinstated(uint256 bucketId) public view returns (uint128) {
        return _castToUint128OrMax(bucketEndSubmissionTimestampNotReinstated(bucketId) + BUCKET_LENGTH);
    }

    function bucket(uint256 bucketId) public view returns (IGCA.Bucket memory bucket) {
        return _buckets[bucketId];
    }

    function getBucketRootAtIndexEfficient(uint256 bucketId, uint256 index) internal view returns (bytes32 root) {
                // solhint-disable-next-line no-inline-assembly
        assembly {
            //Store the key
            mstore(0x0, bucketId)
            //Store the slot
            mstore(0x20, _buckets.slot)
            //Find storage slot where bucket starts
            let slot := keccak256(0x0, 0x40)
            let len := sload(slot)
            if gt(add(index, 1), len) {
                //cast sig "BucketIndexOutOfBounds()"
                mstore(0x0, 0xfdbe8876)
                revert(0x0, 0x4)
            }
            //Reports start at the second slot so we add 1
            slot := add(slot, 1)
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
        //first 64 bits are nonce, next 8 bits  are reinstated, next 184 bits are finalizationTimestamp
        //no need to us to use a mask since finalizationTimestamp takes up the last 184 bits
        uint256 finalizationTimestamp = packedData >> 128;

        uint256 _slashNonce = slashNonce;
        return _isBucketFinalized(bucketLastUpdatedNonce, finalizationTimestamp, _slashNonce);
    }

    //************************************************************* */
    //***************  INTERNAL  ********************** */
    //************************************************************* */

    //---------------------------- HELPERS ----------------------------------

    /**
     * @dev sets the gca agents and their compensation plans
     *         -  removes all previous gca agents
     *         -  remove all previous compensation plans
     *         -  sets the new gca agents
     *         -  sets the new compensation plans
     */
    function _setGCAs(address[] memory gcaAddresses) internal {
        gcaAgents = gcaAddresses;
    }

    /**
     * @dev slashes the gca agents
     * @param gcasToSlash - the gca agents to slash
     */
    function _slashGCAs(address[] memory gcasToSlash) internal {
        //todo: put logic here
        unchecked {
            for (uint256 i; i < gcasToSlash.length; ++i) {
                GCASalaryHelper._slash(gcasToSlash[i]);
            }
        }
    }

    /**
     * @dev calculates the shift to apply to the bitpacked compensation plans
     *     @param index - the index of the gca agent
     *     @return the shift to apply to the bitpacked compensation plans
     */
    function _calculateShift(uint256 index) private pure returns (uint256) {
        return index * _UINT24_SHIFT;
    }

    function _revertIfFrozen() internal view {
        if (_isFrozen()) _revert(IGCA.ProposalHashesNotUpdated.selector);
    }

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
        if (bucketLastUpdatedNonce != slashNonce) {
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
        uint256 bucketNonceWasSlashedAt = (slashNonceToSlashTimestamp[_slashNonce] - GENESIS_TIMESTAMP) / BUCKET_LENGTH;
        //the end submission period is the bucket + 2
        return (bucketNonceWasSlashedAt + 2) * BUCKET_LENGTH + GENESIS_TIMESTAMP;
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

    function bucketGlobalState(uint256 bucketId) external view returns (IGCA.BucketGlobalState memory) {
        return _bucketGlobalState[bucketId];
    }

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

    function _currentWeek() internal view virtual override(GCASalaryHelper) returns (uint256) {
        // solhint-disable-next-line reason-string, custom-errors
        revert();
    }

    function _genesisTimestamp() internal view virtual override(GCASalaryHelper) returns (uint256) {
        return GENESIS_TIMESTAMP;
    }

    function _transferGlow(address to, uint256 amount) internal override(GCASalaryHelper) {
        GLOW_TOKEN.transfer(to, amount);
    }

    function _claimGlowFromInflation() internal virtual override(GCASalaryHelper) {
        GLOW_TOKEN.claimGLWFromGCAAndMinerPool();
    }

    function _domainSeperatorV4Main() internal view virtual override(GCASalaryHelper) returns (bytes32) {
        // solhint-disable-next-line reason-string, custom-errors
        revert();
    }

    function _castToUint128OrMax(uint256 a) internal pure returns (uint128) {
        return a > type(uint128).max ? type(uint128).max : uint128(a);
    }
}

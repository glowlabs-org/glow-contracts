// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {IGCA} from "@/interfaces/IGCA.sol";
import {IGlow} from "@/interfaces/IGlow.sol";
import {VestingMathLib} from "@/libraries/VestingMathLib.sol";
import "forge-std/console.sol";

/**
 * @title GCA (Glow Certification Agent)
 * @author @DavidVorick
 * @author @0xSimon
 */

contract GCA is IGCA {
    /**
     * @notice the amount of shares required per agent when submitting a compensation plan
     * @dev this is not strictly enforced, but rather the
     *         the total shares in a comp plan but equal the SHARES_REQUIRED_PER_COMP_PLAN * gcaAgents.length
     */
    uint256 public constant SHARES_REQUIRED_PER_COMP_PLAN = 100_000;

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

    /// @dev 10_000 GLW Per Week available as rewards to all GCAs
    uint256 public constant REWARDS_PER_SECOND_FOR_ALL = 10_000 ether / uint256(7 days);

    /// @dev 1% of the rewards vest per week
    uint256 public constant VESTING_REWARDS_PER_SECOND_FOR_ALL = REWARDS_PER_SECOND_FOR_ALL / (100 * 86400 * 7);

    /// @dev 200 Billion in 18 decimals
    uint256 private constant _200_BILLION = 200_000_000_000 ether;

    uint256 private constant _UINT64_MAX_DIV5 = type(uint64).max / 5;

    uint256 private constant _UINT128_MASK = (1 << 128) - 1;
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

    /// @notice the requirements hash of GCA Agents
    bytes32 public requirementsHash;

    /// @notice the current slash nonce
    uint256 public slashNonce;

    mapping(uint256 => uint256) public slashNonceToSlashTimestamp;

    /// @notice the bitpacked compensation plans
    mapping(address => uint256) public _compensationPlans;

    /// @notice the gca payouts
    mapping(address => IGCA.GCAPayout) private _gcaPayouts;

    mapping(uint256 => IGCA.Bucket) private _buckets;

    mapping(uint256 => IGCA.BucketGlobalState) private _bucketGlobalState;

    /**
     * @notice constructs a new GCA contract
     * @param _gcaAgents the addresses of the gca agents the contract starts with
     * @param _glowToken the address of the glow token
     * @param _governance the address of the governance contract
     * @param _requirementsHash the requirements hash of GCA Agents
     */
    constructor(address[] memory _gcaAgents, address _glowToken, address _governance, bytes32 _requirementsHash) {
        GLOW_TOKEN = IGlow(_glowToken);
        GOVERNANCE = _governance;
        _setGCAs(_gcaAgents);
        GENESIS_TIMESTAMP = GLOW_TOKEN.GENESIS_TIMESTAMP();
        for (uint256 i; i < _gcaAgents.length; ++i) {
            _gcaPayouts[_gcaAgents[i]].lastClaimedTimestamp = uint64(GENESIS_TIMESTAMP);
        }
        requirementsHash = _requirementsHash;
    }

    /// @inheritdoc IGCA
    function isGCA(address account) public view returns (bool) {
        return _compensationPlans[account] > 0;
    }

    /**
     * TODO: Make sure this pays out all active gcas as well
     */
    /// @inheritdoc IGCA
    function submitCompensationPlan(IGCA.ICompensation[] calldata plans) external {
        _revertIfFrozen();
        uint256 bitpackedPlans;
        if (plans.length == 0) {
            _revert(CompensationPlanLengthMustBeGreaterThanZero.selector);
        }
        uint256 gcaLength = gcaAgents.length;
        uint256 requiredShares = SHARES_REQUIRED_PER_COMP_PLAN;
        uint256 sumOfShares;
        if (!isGCA(msg.sender)) {
            _revert(NotGCA.selector);
        }

        for (uint256 i; i < gcaLength; ++i) {
            address agentInGca = gcaAgents[i];
            bool found;
            for (uint256 j; j < plans.length; ++j) {
                if (agentInGca == plans[j].agent) {
                    sumOfShares += plans[i].shares;
                    bitpackedPlans |= plans[j].shares << _calculateShift(i);
                    found = true;
                    break;
                }
            }

            if (!found) {
                _revert(NotGCA.selector);
            }
            _compensationPlans[agentInGca] = bitpackedPlans;
        }

        if (sumOfShares < requiredShares) {
            _revert(InsufficientShares.selector);
        }
        emit IGCA.CompensationPlanSubmitted(msg.sender, plans);
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
        checkBucketSubmissionArithmeticInputs(totalGlwRewardsWeight, totalGRCRewardsWeight, totalNewGCC);
        if (!isGCA(msg.sender)) _revert(NotGCA.selector);
        //Need to check if bucket is slashed
        Bucket storage bucket = _buckets[bucketId];
        //Cache values
        uint256 len = bucket.reports.length;
        {
            bool reinstated = bucket.reinstated;
            bool alreadyInitialized = bucket.finalizationTimestamp != 0;
            uint256 bucketNonce = bucket.nonce;
            //The submission start timestamp always remains the same
            uint256 bucketSubmissionStartTimestamp = bucketStartSubmissionTimestampNotReinstated(bucketId);
            if (block.timestamp < bucketSubmissionStartTimestamp) _revert(IGCA.BucketSubmissionNotOpen.selector);

            //Keep in mind, all bucketNonces start with 0
            //So on the first init, we need to set the bucketNonce to the slashNonce in storage
            {
                uint256 _slashNonce = slashNonce;
                if (!alreadyInitialized) {
                    bucket.nonce = uint64(_slashNonce);
                    bucketNonce = _slashNonce;
                    alreadyInitialized = true;
                    bucket.finalizationTimestamp = bucketFinalizationTimestampNotReinstated(bucketId);
                }

                {
                    //We only reinstante if the bucketNonce is not the same as the slashNonce
                    // and the bucket has not been reinstated
                    // and the bucket has already been initialized
                    bool reinstatingTx = (bucketNonce != _slashNonce) && !reinstated && alreadyInitialized;

                    /**
                     * If it is a reinstating tx,
                     *             we need to set reinstated to true
                     *             and we need to change the finalization timestamp
                     *             lastly, we need to delete all reports in storage if there are any
                     */
                    if (reinstatingTx) {
                        bucket.reinstated = true;
                        reinstated = true;
                        // //Finalizes one week after submission period ends
                        // alreadyInitialized = true;
                        bucket.finalizationTimestamp = uint184(_WCEIL(bucketNonce) + BUCKET_LENGTH);
                        //conditionally delete all reports in storage
                        if (len > 0) {
                            len = 0;
                            //TODO: figure out if we want to override length with assembly for cheaper gas
                            // or if we replace with a delete
                            assembly {
                                //1 slot offset for buckets length
                                sstore(add(1, bucket.slot), 0)
                            }
                            delete _bucketGlobalState[bucketId];
                        }
                    }
                }
            }
            checkBucketSubmissionEnd(reinstated, bucketSubmissionStartTimestamp, bucketNonce);
        }
        uint256 reportArrayStartSlot;
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
            assembly {
                sstore(slot, packedGlobalState)
            }
            return;
        }

        // foundIndex = foundIndex == type(uint256).max ? 0 : foundIndex;

        uint256 packedDataInReport;
        assembly {
            packedDataInReport := sload(gcaReportStartSlot)
        }

        gccInBucketPlusGcaGcc -= packedDataInReport & _UINT128_MASK;
        glwWeightInBucketPlusGcaGlwWeight -= (packedDataInReport >> 128) & _UINT64_MASK;
        //no need to mask since the grcWeight is the last 64 bits
        grcWeightInBucketPlusGcaGrcWeight -= (packedDataInReport >> 192);

        packedGlobalState = gccInBucketPlusGcaGcc | (glwWeightInBucketPlusGcaGlwWeight << 128)
            | (grcWeightInBucketPlusGcaGrcWeight << 192);
        assembly {
            sstore(slot, packedGlobalState)
        }
    }

    function checkBucketSubmissionEnd(bool reinstated, uint256 bucketSubmissionStartTimestamp, uint256 bucketNonce)
        internal
    {
        //If we have reinstated, we need to check if the bucket is still taking submissions
        //if it's not reinstated, the end submission time is the same as the {bucketSubmissionStartTimestamp} + 1 week
        //This enforces that GCA's can only submit for one week
        if (!reinstated) {
            //Submissions are only open for one week
            if (block.timestamp >= bucketSubmissionStartTimestamp + BUCKET_LENGTH) {
                _revert(IGCA.BucketSubmissionEnded.selector);
            }
            //If the bucket has been reinstated, we need to check if the bucket is still taking submissions
            // by comparing it to the WCEIL of the bucket
        } else {
            if (block.timestamp > (_WCEIL(bucketNonce))) {
                _revert(IGCA.BucketSubmissionEnded.selector);
            }
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
                    assembly {
                        //the address is stored in the [0,1,2] - 3rd slot
                        //                                  ^
                        //that means the slot to read from is i*3 + startSlot + 2
                        proposingAgent := sload(add(reportArrayStartSlot, 2))
                        reportArrayStartSlot := add(reportArrayStartSlot, 3)
                    }
                    if (proposingAgent == msg.sender) {
                        foundIndex = i == 0 ? type(uint256).max : i;
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

    function getProposingAgentFromBucketEfficient(uint256 startSlot, uint256 index)
        internal
        view
        returns (address proposingAgent)
    {
        //Each
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
            {}
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
        bytes32 derivedHash = keccak256(abi.encodePacked(gcasToSlash, newGCAs, proposalCreationTimestamp));

        if (proposalHashes[_nextProposalIndexToUpdate] != derivedHash) {
            _revert(IGCA.ProposalHashDoesNotMatch.selector);
        }

        //TODO: Insert payment mechanism here
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

    /// @inheritdoc IGCA
    function compensationPlan(address gca) public view returns (IGCA.ICompensation[] memory) {
        return _compensationPlan(gca, gcaAgents);
    }

    function _compensationPlan(address gca, address[] memory gcaAddresses)
        internal
        view
        returns (IGCA.ICompensation[] memory)
    {
        if (!isGCA(gca)) {
            _revert(NotGCA.selector);
        }
        uint256 bitpackedPlans = _compensationPlans[gca];
        uint256 gcaLength = gcaAddresses.length;
        IGCA.ICompensation[] memory plans = new IGCA.ICompensation[](gcaLength);
        for (uint256 i; i < gcaLength; ++i) {
            plans[i].shares = uint80((bitpackedPlans >> _calculateShift(i)) & _UINT24_MASK);
            plans[i].agent = gcaAddresses[i];
        }

        return plans;
    }

    function claimGlowFromInflation() public virtual {
        GLOW_TOKEN.claimGLWFromGCAAndMinerPool();
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
    }

    /**
     * @notice returns the start submission timestamp of a bucket
     * @param bucketId - the id of the bucket
     * @return the start submission timestamp of a bucket
     * @dev should not be used for reinstated buckets or buckets that need to be reinstated
     */
    function bucketStartSubmissionTimestampNotReinstated(uint256 bucketId) public view returns (uint184) {
        return uint184(bucketId * BUCKET_LENGTH + GENESIS_TIMESTAMP);
    }

    /**
     * @notice returns the end submission timestamp of a bucket
     *         - GCA's wont be able to submit if block.timestamp >= endSubmissionTimestamp
     * @param bucketId - the id of the bucket
     * @return the end submission timestamp of a bucket
     * @dev should not be used for reinstated buckets or buckets that need to be reinstated
     */
    function bucketEndSubmissionTimestampNotReinstated(uint256 bucketId) public view returns (uint184) {
        return uint184(bucketStartSubmissionTimestampNotReinstated(bucketId) + BUCKET_LENGTH);
    }

    /**
     * @notice returns the finalization timestamp of a bucket
     * @param bucketId - the id of the bucket
     * @return the finalization timestamp of a bucket
     * @dev should not be used for reinstated buckets or buckets that need to be reinstated
     */
    function bucketFinalizationTimestampNotReinstated(uint256 bucketId) public view returns (uint184) {
        return uint184(bucketEndSubmissionTimestampNotReinstated(bucketId) + BUCKET_LENGTH);
    }

    /**
     * @dev Find total owed now and slashable balance using the summation of an arithmetic series
     * @dev formula = n/2 * (2a + (n-1)d) or n/2 * (a + l)
     * @dev read more about this  https://github.com/glowlabs-org/glow-docs/issues/4
     * @dev SB stands for slashable balance
     * @param secondsSinceLastPayout - the  amount of seconds since the last payout
     * @param shares - the amount of shares the gca has
     * @param totalShares - the total amount of shares
     * @return amountNow - the amount of glow owed now
     * @return slashableBalance - the amount of glow that is added to the slashable balance
     */
    function getAmountNowAndSB(uint256 secondsSinceLastPayout, uint256 shares, uint256 totalShares)
        public
        pure
        returns (uint256 amountNow, uint256 slashableBalance)
    {
        (amountNow, slashableBalance) = VestingMathLib.getAmountNowAndSB(
            secondsSinceLastPayout, shares, totalShares, REWARDS_PER_SECOND_FOR_ALL, VESTING_REWARDS_PER_SECOND_FOR_ALL
        );
    }

    /**
     * @param agent - the address of the agent to payout
     * @param gcas - should always be allGcas in storage, but passed through memory for gas savings
     */
    function _payoutAgent(address agent, address[] memory gcas) internal {
        uint256 totalToPayNow;
        uint256 amountToAddToSlashable;
        uint256 totalShares = SHARES_REQUIRED_PER_COMP_PLAN * gcas.length;
        //If the agent is a gca, we need to pay everyone out?
        uint256 lastClaimTimestamp = _gcaPayouts[agent].lastClaimedTimestamp;
        uint256 timeElapsed = block.timestamp - lastClaimTimestamp;
        if (isGCA(agent)) {
            //Check how much they've worked
            //TODO: make sure that lastClaimTimestamp can never be zero
            (uint256 shares,) = _getShares(agent, gcas);
            (totalToPayNow, amountToAddToSlashable) = getAmountNowAndSB(timeElapsed, shares, totalShares);
        }

        //Now we need to calculate how uch
    }

    function bucket(uint256 bucketId) public view returns (IGCA.Bucket memory bucket) {
        return _buckets[bucketId];
    }

    function getBucketRootAtIndexEfficient(uint256 bucketId, uint256 index) internal view returns (bytes32 root) {
        assembly {
            //Store the key
            mstore(0x0, bucketId)
            //Store the slot
            mstore(0x20, _buckets.slot)
            //Find storage slot where bucket starts
            let slot := keccak256(0x0, 0x40)
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

    function getShares(address agent) external view returns (uint256 shares, uint256 totalShares) {
        return _getShares(agent, gcaAgents);
    }

    function isBucketFinalized(uint256 bucketId) public view returns (bool) {
        Bucket storage bucket = _buckets[bucketId];

        uint256 packedData;
        assembly {
            mstore(0x0, bucketId)
            mstore(0x20, _buckets.slot)
            let slot := keccak256(0x0, 0x40)
            // nonce, reinstated and finalizationTimestamp are all in the first slot
            packedData := sload(slot)
        }
        uint256 nonce = packedData & _UINT64_MASK;
        //first 64 bits are nonce, next 8 bits  are reinstated, next 184 bits are finalizationTimestamp
        //no need to us to use a mask since finalizationTimestamp takes up the last 184 bits
        uint256 finalizationTimestamp = packedData >> 72;

        uint256 _slashNonce = slashNonce;
        return _isBucketFinalized(nonce, finalizationTimestamp, _slashNonce);
    }

    //************************************************************* */
    //***************  INTERNAL  ********************** */
    //************************************************************* */

    function _getShares(address agent, address[] memory gcas)
        internal
        view
        returns (uint256 shares, uint256 totalShares)
    {
        uint256 indexOfAgent;
        for (uint256 i; i < gcas.length; i++) {
            if (gcas[i] == agent) {
                indexOfAgent = i;
                break;
            }
        }
        for (uint256 i; i < gcas.length; i++) {
            uint256 bitpackedPlans = _compensationPlans[gcas[i]];
            shares += (bitpackedPlans >> _calculateShift(indexOfAgent)) & _UINT24_MASK;
        }
        totalShares = SHARES_REQUIRED_PER_COMP_PLAN * gcas.length;
    }

    //---------------------------- HELPERS ----------------------------------

    /**
     * @dev sets the gca agents and their compensation plans
     *         -  removes all previous gca agents
     *         -  remove all previous compensation plans
     *         -  sets the new gca agents
     *         -  sets the new compensation plans
     *     TODO: Make sure this pays out all GCA's and handles slashes
     */
    function _setGCAs(address[] memory gcaAddresses) internal {
        address[] memory oldGCAs = gcaAgents;
        for (uint256 i; i < oldGCAs.length; ++i) {
            delete _compensationPlans[oldGCAs[i]];
        }

        gcaAgents = gcaAddresses;
        //log all the gcaAddresses
        for (uint256 i; i < gcaAddresses.length; ++i) {
            _compensationPlans[gcaAddresses[i]] = (SHARES_REQUIRED_PER_COMP_PLAN) << _calculateShift(i);
            //If they have any slashable balance that's unclaimed, we should clean that up here...
        }
    }

    function _slashGCAs(address[] memory gcasToSlash) internal {
        //todo: put logic here
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
        uint256 len = proposalHashes.length;
        //If no proposals have been submitted, we don't need to check
        if (len == 0) return;
        if (len != nextProposalIndexToUpdate) {
            _revert(IGCA.ProposalHashesNotUpdated.selector);
        }
    }

    /**
     * @dev checks if a bucket is finalized
     * @param bucketNonce the slash nonce of the bucket
     * @param bucketFinalizationTimestamp the finalization timestamp of the bucket
     * @return true if the bucket is finalized, false otherwise
     */
    function _isBucketFinalized(uint256 bucketNonce, uint256 bucketFinalizationTimestamp, uint256 _slashNonce)
        internal
        view
        returns (bool)
    {
        if (bucketNonce == _slashNonce && block.timestamp >= bucketFinalizationTimestamp) return true;
        //TODO: there's prbably an easier way than the method below.
        //We could probably do if (bucketNonce < slashNonce && reinitilized &&
        //if(bucketFinalizationTimestamp == 0) return false
        //if(block.timestamp < bucketFinalizationTimestamp) return false
        // if(slashNonce != bucketNonce) { if(!reinitilized) return false }
        //return true;
        if (
            bucketNonce < _slashNonce && bucketFinalizationTimestamp < slashNonceToSlashTimestamp[bucketNonce]
                && block.timestamp >= bucketFinalizationTimestamp
        ) return true;
        return false;
    }

    /**
     * @notice More efficiently reverts with a bytes4 selector
     * @param selector The selector to revert with
     */

    function _revert(bytes4 selector) internal pure {
        assembly {
            mstore(0x0, selector)
            revert(0x0, 0x04)
        }
    }

    /**
     * @dev will underflow and revert if slashNonceToSlashTimestamp[_slashNonce] has not yet been written to
     * @dev returns the WCEIL for the given slash nonce.
     * @dev WCEIL is equal to the end bucket submission time for the bucket that the slash nonce was slashed in + 2 weeks
     * @dev it's two weeks instead of one to make sure there is adequate time for GCA's to submit reports
     */
    function _WCEIL(uint256 _slashNonce) internal view returns (uint256) {
        //This will underflow if slashNonceToSlashTimestamp[_slashNonce] has not yet been written to
        uint256 bucketNonceWasSlashedAt = (slashNonceToSlashTimestamp[_slashNonce] - GENESIS_TIMESTAMP) / BUCKET_LENGTH;
        //the end submission period is the bucket + 2
        return (bucketNonceWasSlashedAt + 2) * BUCKET_LENGTH + GENESIS_TIMESTAMP;
    }

    function getPackedBucketGlobalState(uint256 bucketId) internal view returns (uint256 packedGlobalState) {
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
}

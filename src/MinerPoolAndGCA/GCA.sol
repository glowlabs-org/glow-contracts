// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {IGCA} from "@/interfaces/IGCA.sol";
import {IGlow} from "@/interfaces/IGlow.sol";
import "forge-std/console.sol";
import {VestingMathLib} from "@/libraries/VestingMathLib.sol";
import "forge-std/console.sol";
// TODO: note to self -- im brain fried rn, go back to the slashable vesting in your notebook

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

    uint256 private constant _UINT256_MAX_DIV5 = type(uint256).max / 5;

    // 1 week
    uint256 private constant BUCKET_LENGTH = 7 * uint256(1 days);

    /// @notice the index of the last proposal that was updated + 1
    uint256 public lastUpdatedProposalIndexPlusOne;

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
        if (!isGCA(msg.sender)) _revert(NotGCA.selector);
        //Need to check if bucket is slashed
        Bucket storage bucket = _buckets[bucketId];
        //Cache values
        (uint256 bucketNonce, uint256 bucketFinalizationTimestamp, bool reinstated) =
            (bucket.nonce, bucket.finalizationTimestamp, bucket.reinstated);
        uint256 _slashNonce = slashNonce;
        bool alreadyInitialized = bucketFinalizationTimestamp != 0;
        uint256 len = bucket.reports.length;

        //idea: what if current bucket was not init and then slash nonce happens
        // so current bucket has a diff slash nonce and is not init, what do we do?
        // a: not allow the bucket to be written to
        // b: allow the bucket to be written to

        /**
         * We don't check the endSubmissionTimestamp when
         *         the bucket needs to be reinstated.
         *         When does the bucket need to be reinstated?
         *         When slashNonce != slashNonce and it's not reinstated
         */
        {
            bool reinstatingTx = (bucketNonce != _slashNonce) && !reinstated;

            if (reinstatingTx) {
                bucket.reinstated = true;
                reinstated = true;
                if (!alreadyInitialized) {
                    alreadyInitialized = true;
                }
                //Finalizes one week after submission period ends
                bucketFinalizationTimestamp = (_WCEIL(bucketNonce) + BUCKET_LENGTH);
                bucket.finalizationTimestamp = bucketFinalizationTimestamp;
                //conditionally delete all reports in storage
                if (len > 0) {
                    len = 0;
                    delete bucket.reports;
                }
            }
        }

        //If the bucket has not been reinstated, we need to make sure that the submission period is still open
        //The submission period is open if the current timestamp is less than the endSubmissionTimestamp
        if (!reinstated) {
            uint256 bucketSubmissionStartTimestamp = bucketStartSubmissionTimestampNotReinstated(bucketId);
            if (block.timestamp < bucketSubmissionStartTimestamp) _revert(IGCA.BucketSubmissionNotOpen.selector);
            //Submissions are only open for one week
            if (block.timestamp >= bucketSubmissionStartTimestamp + BUCKET_LENGTH) {
                _revert(IGCA.BucketSubmissionEnded.selector);
            }
        }

        if (reinstated) {
            if (block.timestamp > (bucketFinalizationTimestamp - BUCKET_LENGTH)) {
                _revert(IGCA.BucketSubmissionNotOpen.selector);
            }
        }

        // if(_isBucketFinalized(bucketNonce, bucketFinalizationTimestamp,_slashNonce))
        //     _revert(IGCA.BucketAlreadyFinalized.selector);
        // if(bucket.nonce != _slashNonce) revert("simon fill this in");
        if (totalGlwRewardsWeight > _UINT256_MAX_DIV5) _revert(IGCA.ReportWeightMustBeLTUintMaxDiv5.selector);
        if (totalGRCRewardsWeight > _UINT256_MAX_DIV5) _revert(IGCA.ReportWeightMustBeLTUintMaxDiv5.selector);
        if (totalNewGCC > _200_BILLION) _revert(IGCA.ReportGCCMustBeLT200Billion.selector);

        uint256 foundIndex;
        unchecked {
            for (uint256 i; i < len; ++i) {
                if (bucket.reports[i].proposingAgent == msg.sender) {
                    foundIndex = i == 0 ? type(uint256).max : i;
                    break;
                }
            }

            if (foundIndex == 0) {
                bucket.reports.push(
                    IGCA.Report({
                        proposingAgent: msg.sender,
                        totalNewGCC: totalNewGCC,
                        totalGLWRewardsWeight: totalGlwRewardsWeight,
                        totalGRCRewardsWeight: totalGRCRewardsWeight,
                        merkleRoot: root
                    })
                );
                if (!reinstated) {
                    bucket.nonce = uint192(_slashNonce);
                    if (!alreadyInitialized) {
                        bucket.finalizationTimestamp = bucketFinalizationTimestampNotReinstated(bucketId);
                    }
                }
            } else {
                bucket.reports[foundIndex == type(uint256).max ? 0 : foundIndex] = IGCA.Report({
                    proposingAgent: msg.sender,
                    totalNewGCC: totalNewGCC,
                    totalGLWRewardsWeight: totalGlwRewardsWeight,
                    totalGRCRewardsWeight: totalGRCRewardsWeight,
                    merkleRoot: root
                });
            }
        }
    }

    function executeAgainstHash(
        uint256 index,
        address[] calldata gcasToSlash,
        address[] calldata newGCAs,
        uint256 proposalCreationTimestamp
    ) external {
        uint256 _lastUpdatedProposalIndexPlusOne = lastUpdatedProposalIndexPlusOne;
        uint256 len = proposalHashes.length;
        bytes32 derivedHash = keccak256(abi.encodePacked(gcasToSlash, newGCAs, proposalCreationTimestamp));
        //On firt submit
        if (_lastUpdatedProposalIndexPlusOne == 0) {
            if (derivedHash != requirementsHash) {
                _revert(IGCA.ProposalHashDoesNotMatch.selector);
            }
            _setGCAs(newGCAs);
            _slashGCAs(gcasToSlash);
            //TODO: Insert payment mechanism here
            lastUpdatedProposalIndexPlusOne = 1;
            emit IGCA.ProposalHashUpdate(index, derivedHash);
            return;
        }

        if (index + 1 < lastUpdatedProposalIndexPlusOne) {
            _revert(IGCA.ProposalAlreadyUpdated.selector);
        }

        if (proposalHashes[index] != derivedHash) {
            _revert(IGCA.ProposalHashDoesNotMatch.selector);
        }

        //TODO: Insert payment mechanism here
        _setGCAs(newGCAs);
        _slashGCAs(gcasToSlash);
        lastUpdatedProposalIndexPlusOne = index + 1;
        emit IGCA.ProposalHashUpdate(index, derivedHash);
    }

    function setRequirementsHash(bytes32 _requirementsHash) external {
        if (msg.sender != GOVERNANCE) _revert(IGCA.CallerNotGovernance.selector);
        requirementsHash = _requirementsHash;
        emit IGCA.RequirementsHashUpdated(_requirementsHash);
    }

    function pushHash(bytes32 hash) external {
        if (msg.sender != GOVERNANCE) _revert(IGCA.CallerNotGovernance.selector);
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
        public
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
    function bucketStartSubmissionTimestampNotReinstated(uint256 bucketId) public view returns (uint256) {
        return bucketId * BUCKET_LENGTH + GENESIS_TIMESTAMP;
    }

    /**
     * @notice returns the end submission timestamp of a bucket
     *         - GCA's wont be able to submit if block.timestamp >= endSubmissionTimestamp
     * @param bucketId - the id of the bucket
     * @return the end submission timestamp of a bucket
     * @dev should not be used for reinstated buckets or buckets that need to be reinstated
     */
    function bucketEndSubmissionTimestampNotReinstated(uint256 bucketId) public view returns (uint256) {
        return bucketStartSubmissionTimestampNotReinstated(bucketId) + BUCKET_LENGTH;
    }

    /**
     * @notice returns the finalization timestamp of a bucket
     * @param bucketId - the id of the bucket
     * @return the finalization timestamp of a bucket
     * @dev should not be used for reinstated buckets or buckets that need to be reinstated
     */
    function bucketFinalizationTimestampNotReinstated(uint256 bucketId) public view returns (uint256) {
        return bucketEndSubmissionTimestampNotReinstated(bucketId) + BUCKET_LENGTH;
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

    function bucket(uint256 bucketId) external view returns (IGCA.Bucket memory bucket) {
        return _buckets[bucketId];
    }

    function getShares(address agent) external view returns (uint256 shares, uint256 totalShares) {
        return _getShares(agent, gcaAgents);
    }

    function isBucketFinalized(uint256 bucketId) external view returns (bool) {
        Bucket storage bucket = _buckets[bucketId];
        uint256 _slashNonce = slashNonce;
        return _isBucketFinalized(bucket.nonce, bucket.finalizationTimestamp, _slashNonce);
    }

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
        if (len != lastUpdatedProposalIndexPlusOne) {
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

    function _WCEIL(uint256 _slashNonce) private view returns (uint256) {
        uint256 bucketNonceWasSlashedAt = (slashNonceToSlashTimestamp[_slashNonce] - GENESIS_TIMESTAMP) / BUCKET_LENGTH;
        //the end submission period is the bucket + 2
        return (bucketNonceWasSlashedAt + 2) * BUCKET_LENGTH + GENESIS_TIMESTAMP;
    }
}

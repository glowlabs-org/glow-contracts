// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IGCA {
    error NotGCA();
    error CallerNotGCA();
    error CompensationPlanLengthMustBeGreaterThanZero();
    error InsufficientShares();
    error NoBalanceToPayout();
    error CallerNotGovernance();
    error ProposalHashesNotUpdated();
    error ProposalHashDoesNotMatch();
    error IndexDoesNotMatchNextProposalIndex();
    error ProposalHashesEmpty();
    error ProposalAlreadyUpdated();
    error BucketAlreadyFinalized();
    error ReportGCCMustBeLT200Billion();
    error ReportWeightMustBeLTUint64MaxDiv5();
    error BucketSubmissionNotOpen();
    error BucketSubmissionEnded();
    error EmptyRoot();
    error CallerNotGCAAtIndex();
    error GCCAlreadySet();
    error BucketIndexOutOfBounds();

    /**
     * @notice returns true if the caller is a gca
     * @param account - the address of the account to check
     * @return status -  true if the account is a gca , false otherwise
     */
    function isGCA(address account) external view returns (bool);

    /**
     * @notice returns true if the caller is a gca
     * @param account - the address of the account to check
     * @param index - the index of the gca in the gca array
     * @return status -  true if the account is a gca , false otherwise
     */
    function isGCA(address account, uint256 index) external view returns (bool);

    /// @dev allows GCAs to submit a compensation plan
    function submitCompensationPlan(uint32[5] calldata plan, uint256 indexOfGCA) external;

    /// @return - returns the compensation plan for a gca by unpacking the packed compensation plan
    // function compensationPlan(address gca) external view returns (ICompensation[] memory);

    /// @return - returns all thFe gcas
    function allGcas() external view returns (address[] memory);

    /// @dev allows the contrac to pull glow from inflation
    function claimGlowFromInflation() external;

    /**
     * @param gca - the address of the gca to check
     * @return - returns the {GCAPayout} struct data for a gca
     */
    function gcaPayoutData(address gca) external view returns (GCAPayout memory);

    function pushHash(bytes32 hash, bool incrementSlashNonce) external;
    function setRequirementsHash(bytes32 _requirementsHash) external;
    /**
     * @return shares - the amount of shares the gca has
     * @return totalShares - the total amount of shares across all GCAs
     */

    // function getShares(address gca) external view returns (uint256 shares, uint256 totalShares);

    /**
     * @dev a struct to represent a compensation plan
     * @dev packed into a single uint256
     * @param shares - the amount of shares to be distributed
     * @param agent - the address of the gca agent to receive the shares
     */
    struct ICompensation {
        uint80 shares;
        address agent;
    }

    /**
     * @dev a struct to represent a gca payout
     * @param lastClaimedTimestamp - the last time the gca claimed their payout
     * @param totalSlashableBalance - the total slashable balance of the gca
     */
    struct GCAPayout {
        uint64 lastClaimedTimestamp;
        uint64 maxClaimTimestamp;
        uint128 totalSlashableBalance;
    }

    /**
     * @dev a struct to represent a report
     * @param totalNewGCC - the total amount of new gcc
     * @param totalGLWRewardsWeight - the total amount of glw rewards weight
     * @param totalGRCRewardsWeight - the total amount of grc rewards weight
     * @param merkleRoot - the root containing all the reports (leaves) for the period
     *             - The leaf structure is as follows:
     *                 -   (address payoutWallet,uint256 glwRewardsWeight,uint256 grcRewardsWeight)
     * @param proposingAgent - the address of the gca agent proposing the report
     */
    struct Report {
        uint128 totalNewGCC;
        uint64 totalGLWRewardsWeight;
        uint64 totalGRCRewardsWeight;
        bytes32 merkleRoot;
        address proposingAgent;
    }
    //3 slots

    /**
     * @param originalNonce - the slash nonce in storage at the time of report submission
     * @param lastUpdatedNonce - the slash nonce in storage at the time of the last report submission
     * @param finalizationTimestamp - the finalization timestamp for the bucket according to the weekly bucket schedule
     * @param reports - the reports for the bucket
     */
    struct Bucket {
        uint64 originalNonce;
        uint64 lastUpdatedNonce;
        uint128 finalizationTimestamp;
        Report[] reports;
    }

    /**
     * @dev a struct to represent a bucket global state
     * @dev its used as a caching mechanism to avoid iterating over all buckets
     * @param totalNewGCC - the total amount of new gcc
     * @param totalGLWRewardsWeight - the total amount of glw rewards weight
     * @param totalGRCRewardsWeight - the total amount of grc rewards weight
     */
    struct BucketGlobalState {
        uint128 totalNewGCC;
        uint64 totalGLWRewardsWeight;
        uint64 totalGRCRewardsWeight;
    }

    /**
     * @dev Emitted when a gca submits a new compensation plan.
     * @param agent - the address of the gca agent proposing
     * @param plan - the compensation plan of the agent
     */
    event CompensationPlanSubmitted(address indexed agent, uint32[5] plan);

    /**
     * @dev Emitted when a gca claims their payout
     * @param agent - the address of the gca agent claiming
     * @param amount - the amount of tokens claimed
     * @param totalSlashableBalance - the total slashable balance of the gca
     */
    event GCAPayoutClaimed(address indexed agent, uint256 amount, uint256 totalSlashableBalance);

    /**
     * @dev Emitted when a proposal hash is acted upon
     * @param index - the index of the proposal hash inside the {proposalHashes} array
     * @param proposalHash - the proposal hash
     */
    event ProposalHashUpdate(uint256 indexed index, bytes32 proposalHash);

    /**
     * @dev Emitted when governacne updates the {requirementsHash}
     * @param requirementsHash - the new requirements hash gcas must abide by
     */
    event RequirementsHashUpdated(bytes32 requirementsHash);

    event BucketSubmissionEvent(
        uint256 indexed bucketId,
        address gca,
        uint256 slashNonce,
        uint256 totalNewGCC,
        uint256 totalGlwRewardsWeight,
        uint256 totalGRCRewardsWeight,
        bytes32 root,
        bytes extraData
    );
}

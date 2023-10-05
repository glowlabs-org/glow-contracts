// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

interface IGCA {
    error NotGCA();
    error CallerNotGCA();
    error CompensationPlanLengthMustBeGreaterThanZero();
    error InsufficientShares();
    error NoBalanceToPayout();
    error CallerNotGovernance();
    error ProposalHashesNotUpdated();
    error ProposalHashDoesNotMatch();
    error ProposalAlreadyUpdated();
    error BucketAlreadyFinalized();
    error ReportGCCMustBeLT200Billion();
    error ReportWeightMustBeLTUintMaxDiv5();
    error BucketSubmissionNotOpen();
    error BucketSubmissionEnded();
    // error BucketNotReinitilizable();

    /**
     * @return = true if the account is a gca , false otherwise
     */
    function isGCA(address account) external view returns (bool);

    /// @dev allows GCAs to submit a compensation plan
    function submitCompensationPlan(ICompensation[] calldata plans) external;

    /// @return - returns the compensation plan for a gca by unpacking the packed compensation plan
    function compensationPlan(address gca) external view returns (ICompensation[] memory);

    /// @return - returns all the gcas
    function allGcas() external view returns (address[] memory);

    /// @dev allows the contrac to pull glow from inflation
    function claimGlowFromInflation() external;

    /**
     * @param gca - the address of the gca to check
     * @return - returns the {GCAPayout} struct data for a gca
     */
    function gcaPayoutData(address gca) external view returns (GCAPayout memory);

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
        uint256 totalNewGCC;
        uint256 totalGLWRewardsWeight;
        uint256 totalGRCRewardsWeight;
        bytes32 merkleRoot;
        address proposingAgent;
    }

    /**
     * @param nonce - the slash nonce in storage at the time of report submission
     * @param finalizationTimestamp - the finalization timestamp for the bucket according to the weekly bucket schedule
     * @param reports - the reports for the bucket
     */
    struct Bucket {
        uint192 nonce;
        bool reinstated;
        //if finalizationTimestamp > 0
        uint256 finalizationTimestamp;
        Report[] reports;
    }

    /**
     * @dev Emitted when a gca submits a new compensation plan.
     * @param agent - the address of the gca agent proposing
     * @param plans - the compensation plans
     */
    event CompensationPlanSubmitted(address indexed agent, ICompensation[] plans);

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
}

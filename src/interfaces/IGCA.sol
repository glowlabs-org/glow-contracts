// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IGCA {
    /* -------------------------------------------------------------------------- */
    /*                                   errors                                  */
    /* -------------------------------------------------------------------------- */
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

    /* -------------------------------------------------------------------------- */
    /*                                   structs                                  */
    /* -------------------------------------------------------------------------- */
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

    /* -------------------------------------------------------------------------- */
    /*                                   events                                   */
    /* -------------------------------------------------------------------------- */
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
     * @dev emitted when a proposal hash is pushed
     * @param proposalHash - the proposal hash
     */
    event ProposalHashPushed(bytes32 proposalHash);

    /**
     * @dev Emitted when governacne updates the {requirementsHash}
     * @param requirementsHash - the new requirements hash gcas must abide by
     */
    event RequirementsHashUpdated(bytes32 requirementsHash);

    /**
     * @dev emitted when new GCAs are appointed
     * @dev the new GCAs completely replace the old ones
     * @param newGcas - the new GCAs
     */
    event NewGCAsAppointed(address[] newGcas);

    /**
     * @dev emitted when GCAs are slashed
     * @param slashedGcas - the slashed GCAs
     */
    event GCAsSlashed(address[] slashedGcas);

    /**
     * @notice emitted when a GCA submits a report for a bucket
     * @param bucketId - the id of the bucket
     * @param gca - the address of the gca agent submitting the report
     * @param slashNonce - the slash nonce at the time of report submission
     * @param totalNewGCC - the total amount of new gcc from the farms the GCA is reporting on
     * @param totalGlwRewardsWeight - the total amount of glw rewards weight from the farms the GCA is reporting on
     * @param totalGRCRewardsWeight - the total amount of grc rewards weight from the farms the GCA is reporting on
     * @param root - the merkle root of the reports
     * @param extraData - extra data to be emitted.
     *                         - This extra data can be anything as long as the GCA communicates it to the community
     *                         - and should ideally, if possible, be the leaves of the merkle tree
     */
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

    /* -------------------------------------------------------------------------- */
    /*                                 state changing funcs                       */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice allows governance to push a hash to execute against
     * @param hash - the hash to execute against
     * @param incrementSlashNonce - whether or not to increment the slash nonce
     *         - incrementing the slash nonce means that all non-finalized buckets will be slashed
     *             - and must be reinstated
     * @dev the hash is the abi.encode of the following:
     *         - the gca agents to slash
     *         - the new gca agents
     *         - the proposal creation timestamp
     */
    function pushHash(bytes32 hash, bool incrementSlashNonce) external;

    /**
     * @notice allows governance to change the requirements hash of GCA's
     *         - the requirements hash represents a hash of the duties and responsibilities of a GCA
     * @param  _requirementsHash - the new requirements hash
     */
    function setRequirementsHash(bytes32 _requirementsHash) external;

    /// @dev allows GCAs to submit a compensation plan
    function submitCompensationPlan(uint32[5] calldata plan, uint256 indexOfGCA) external;

    /// @dev allows the contract to pull glow from inflation
    function claimGlowFromInflation() external;

    /* -------------------------------------------------------------------------- */
    /*                                   view functions                            */
    /* -------------------------------------------------------------------------- */
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

    /// @return - returns all the gcas
    function allGcas() external view returns (address[] memory);

    /**
     * @param gca - the address of the gca to check
     * @return - returns the {GCAPayout} struct data for a gca
     */
    function gcaPayoutData(address gca) external view returns (GCAPayout memory);

    /**
     * @notice - returns all proposal hashes
     * @return proposalHashes - the proposal hashes
     */
    function getProposalHashes() external view returns (bytes32[] memory);

    /**
     * @notice - returns a range of proposal hashes
     * @param start - the start index
     * @param end - the end index
     * @return proposalHashes - the proposal hashes
     */
    function getProposalHashes(uint256 start, uint256 end) external view returns (bytes32[] memory);

    /**
     * @notice returns the global state of a bucket
     * @param bucketId - the id of the bucket
     * @return the global state of a bucket
     */
    function bucketGlobalState(uint256 bucketId) external view returns (BucketGlobalState memory);

    /**
     * @notice returns the {Bucket} struct for a given week / bucketId
     * @param bucketId - the id of the bucket
     * @return bucket - the {Bucket} struct for a given bucketId
     */
    function bucket(uint256 bucketId) external view returns (Bucket memory);

    /**
     * @notice returns if the bucket is finalized or not
     * @param bucketId - the id of the bucket
     */

    function isBucketFinalized(uint256 bucketId) external view returns (bool);
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IGovernance {
    //---------- ERRORS -----------------//
    error ProposalNotInitialized();
    error ProposalHasNotExpired();

    enum ProposalType {
        None,
        VetoCouncilElectionOrSlash,
        GcaCountilElectionOrSlash,
        AddReserveCurrencies,
        GrantsProposal,
        ChangeGcaRequirements,
        RequestForComment
    }

    enum ProposalStatus {
        Pending,
        UnderReviewForApproval,
        RejectedByStakers,
        Approved,
        ExecutedWithError,
        ExecutedSuccessfully,
        Expired,
        Vetoed
    }

    /**
     * @param proposalType the type of the proposal
     * @param expirationTimestamp the timestamp at which the proposal expires
     * @param data the data of the proposal
     */
    struct Proposal {
        ProposalType proposalType;
        ProposalStatus status;
        uint64 expirationTimestamp;
        bytes data;
    }

    /**
     * @notice gets the proposal and the status of the proposal with the given id
     * @param proposalId the id of the proposal
     * @return proposal the proposal
     */
    function getProposalWithStatus(uint256 proposalId) external view returns (Proposal memory proposal);

    /**
     * @notice Allows the GCC contract to grant nominations to {to} when they retire GCC
     * @param to the address to grant nominations to
     * @param amount the amount of nominations to grant
     */
    function grantNominations(address to, uint256 amount) external;

    /**
     * @notice Emitted when a Veto Council Election or Slash proposal is created
     * @param proposalId the id of the proposal
     * @param proposer the address of the proposer
     * @param oldAgent the address of the old agent
     * @param newAgent the address of the new agent
     * @param slashOldAgent whether or not to slash the old agent
     */
    event VetoCouncilElectionOrSlash(
        uint256 indexed proposalId, address indexed proposer, address oldAgent, address newAgent, bool slashOldAgent
    );

    /**
     * @notice Emitted when a GCA Council Election or Slash proposal is created
     * @param proposalId the id of the proposal
     * @param proposer the address of the proposer
     * @param agentsToSlash the addresses of the agents to slash
     * @param newGCAs the addresses of the new GCAs
     * @param proposalCreationTimestamp the timestamp at which the proposal was created
     *         -   This is necessary due to the proposalHashes logic in GCA
     */
    event GCACouncilElectionOrSlashCreation(
        uint256 indexed proposalId,
        address indexed proposer,
        address[] agentsToSlash,
        address[] newGCAs,
        uint256 proposalCreationTimestamp
    );

    /**
     * @notice emitted when a proposal to change the reserve currencies is created
     * @param proposalId the id of the proposal
     * @param proposer the address of the proposer
     * @param newReserveCurrencies the new reserve currencies
     *         - max length 3
     */
    event ChangeReserveCurrenciesProposal(
        uint256 indexed proposalId, address indexed proposer, address[] newReserveCurrencies
    );

    /**
     * @notice emitted when a grants proposal is created
     * @param proposalId the id of the proposal
     * @param proposer the address of the proposer
     * @param recipient the address of the recipient
     * @param amount the amount of tokens to send
     * @param hash the hash of the proposal contents
     */
    event GrantsProposalCreation(
        uint256 indexed proposalId, address indexed proposer, address recipient, uint256 amount, bytes32 hash
    );

    /**
     * @notice emitted when a proposal to change the GCA requirements is created
     * @param proposalId the id of the proposal
     * @param proposer the address of the proposer
     * @param requirementsHash the hash of the requirements
     */
    event ChangeGCARequirementsProposalCreation(
        uint256 indexed proposalId, address indexed proposer, bytes32 requirementsHash
    );

    /**
     * @notice emitted when a request for comment is created
     * @param proposalId the id of the proposal
     * @param proposer the address of the proposer
     * @param requirementsHash the hash of the requirements string
     */
    event RFCProposalCreation(uint256 indexed proposalId, address indexed proposer, bytes32 requirementsHash);
}

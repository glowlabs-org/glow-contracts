// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IGovernance {
    //---------- ERRORS -----------------//
    error ProposalHasNotExpired(uint256 proposalId);
    error ProposalExpired();
    error InsufficientNominations();
    error GCAContractAlreadySet();
    error CallerNotGCA();
    error CallerNotGCC();
    error CallerNotVetoCouncilMember();
    error ZeroAddressNotAllowed();
    error ContractsAlreadySet();
    error NominationCostGreaterThanAllowance();
    error ProposalDoesNotExist();
    error WeekNotFinalized();
    error InsufficientRatifyOrRejectVotes();
    error RatifyOrRejectPeriodEnded();
    error RatifyOrRejectPeriodNotEnded();
    error MostPopularProposalNotSelected();
    error ProposalAlreadyVetoed();
    error AlreadyEndorsedWeek();
    error OnlyGCAElectionsCanBeEndorsed();
    error MaxGCAEndorsementsReached();
    error VetoCouncilElectionsCannotBeVetoed();
    error GCACouncilElectionsCannotBeVetoed();
    error ProposalsMustBeExecutedSynchonously();
    error ProposalNotInitialized();
    error RFCPeriodNotEnded();

    enum ProposalType {
        NONE, //default value for unset proposals
        VETO_COUNCIL_ELECTION_OR_SLASH,
        GCA_COUNCIL_ELECTION_OR_SLASH,
        CHANGE_RESERVE_CURRENCIES,
        GRANTS_PROPOSAL,
        CHANGE_GCA_REQUIREMENTS,
        REQUEST_FOR_COMMENT
    }

    // uint256 constant PENDING_MASK = 0x1;
    // uint256 constant UNDER_REVIEW_FOR_APPROVAL_MASK = 0x2;
    // uint256 constant REJECTED_BY_STAKERS_MASK = 0x4;
    // uint256 constant APPROVED_MASK = 0x8;
    // uint256 constant EXECUTED_WITH_ERROR_MASK = 0x10;
    // uint256 constant EXECUTED_SUCCESSFULLY_MASK = 0x20;
    // uint256 constant EXPIRED_MASK = 0x40;
    // uint256 constant VETOED_MASK = 0x80;

    enum ProposalStatus {
        PENDING,
        UNDER_REVIEW_FOR_APPROVAL,
        REJECTED_BY_STAKERS,
        APPROVED,
        EXECUTED_WITH_ERROR,
        EXECUTED_SUCCESSFULLY,
        EXPIRED,
        VETOED
    }

    /**
     * @param proposalType the type of the proposal
     * @param expirationTimestamp the timestamp at which the proposal expires
     * @param data the data of the proposal
     */
    struct Proposal {
        ProposalType proposalType;
        uint64 expirationTimestamp;
        uint184 votes;
        bytes data;
    }

    /**
     * @notice gets the proposal and the status of the proposal with the given id
     * @param proposalId the id of the proposal
     * @return proposal the proposal
     * @return status the status of the proposal
     */
    function getProposalWithStatus(uint256 proposalId)
        external
        view
        returns (Proposal memory proposal, ProposalStatus);

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
     * @param nominationsUsed the amount of nominations used
     */
    event VetoCouncilElectionOrSlash(
        uint256 indexed proposalId,
        address indexed proposer,
        address oldAgent,
        address newAgent,
        bool slashOldAgent,
        uint256 nominationsUsed
    );

    /**
     * @notice Emitted when a GCA Council Election or Slash proposal is created
     * @param proposalId the id of the proposal
     * @param proposer the address of the proposer
     * @param agentsToSlash the addresses of the agents to slash
     * @param newGCAs the addresses of the new GCAs
     * @param proposalCreationTimestamp the timestamp at which the proposal was created
     *         -   This is necessary due to the proposalHashes logic in GCA
     * @param nominationsUsed the amount of nominations used
     */
    event GCACouncilElectionOrSlashCreation(
        uint256 indexed proposalId,
        address indexed proposer,
        address[] agentsToSlash,
        address[] newGCAs,
        uint256 proposalCreationTimestamp,
        uint256 nominationsUsed
    );

    /**
     * @notice emitted when a proposal to change the reserve currencies is created
     * @param proposalId the id of the proposal
     * @param proposer the address of the proposer
     * @param currencyToRemove  the address of the currency to remove
     * @param newReserveCurrency the address of the new reserve currency
     * @param nominationsUsed the amount of nominations used
     * @dev currencyToRemove can be address(0) to add a new reserve currency
     * @dev there should never be more than 3 active reserve currencies
     */
    event ChangeReserveCurrenciesProposal(
        uint256 indexed proposalId,
        address indexed proposer,
        address currencyToRemove,
        address newReserveCurrency,
        uint256 nominationsUsed
    );

    /**
     * @notice emitted when a grants proposal is created
     * @param proposalId the id of the proposal
     * @param proposer the address of the proposer
     * @param recipient the address of the recipient
     * @param amount the amount of tokens to send
     * @param hash the hash of the proposal contents
     * @param nominationsUsed the amount of nominations used
     */
    event GrantsProposalCreation(
        uint256 indexed proposalId,
        address indexed proposer,
        address recipient,
        uint256 amount,
        bytes32 hash,
        uint256 nominationsUsed
    );

    /**
     * @notice emitted when a proposal to change the GCA requirements is created
     * @param proposalId the id of the proposal
     * @param proposer the address of the proposer
     * @param requirementsHash the hash of the requirements
     * @param nominationsUsed the amount of nominations used
     */
    event ChangeGCARequirementsProposalCreation(
        uint256 indexed proposalId, address indexed proposer, bytes32 requirementsHash, uint256 nominationsUsed
    );

    /**
     * @notice emitted when a request for comment is created
     * @param proposalId the id of the proposal
     * @param proposer the address of the proposer
     * @param requirementsHash the hash of the requirements string
     * @param nominationsUsed the amount of nominations used
     */
    event RFCProposalCreation(
        uint256 indexed proposalId, address indexed proposer, bytes32 requirementsHash, uint256 nominationsUsed
    );

    /**
     * @notice emitted when nominations are used on a proposal
     * @param proposalId the id of the proposal
     * @param spender the address of the spender
     * @param amount the amount of nominations used
     */
    event NominationsUsedOnProposal(uint256 indexed proposalId, address indexed spender, uint256 amount);

    /**
     * @notice emitted when a proposal is ratified
     * @param weekId - the weekId in which the proposal to be vetoed was selected as the most popular proposal
     * @param vetoer - the address of the veto council member who vetoed the proposal
     * @param proposalId - the id of the proposal that was vetoed
     *  TODO: see if we can remove the last param for gas savings
     */
    event ProposalVetoed(uint256 indexed weekId, address indexed vetoer, uint256 proposalId);

    event RFCProposalExecuted(uint256 indexed proposalId, bytes32 requirementsHash);
}

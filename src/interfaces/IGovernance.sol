// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IGovernance {
    /* -------------------------------------------------------------------------- */
    /*                                   errors                                   */
    /* -------------------------------------------------------------------------- */
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
    error WeekNotStarted();
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
    error ProposalAlreadyExecuted();
    error ProposalIdDoesNotMatchMostPopularProposal();
    error ProposalNotMostPopular();
    error VetoCouncilProposalCreationOldMemberCannotEqualNewMember();
    error MaximumNumberOfGCAS();
    error InvalidSpendNominationsOnProposalSignature();

    error MaxSlashesInGCAElection();
    error SpendNominationsOnProposalSignatureExpired();
    error ProposalIsVetoed();
    error VetoMemberCannotBeNullAddress();
    error WeekMustHaveEndedToAcceptRatifyOrRejectVotes();

    /* -------------------------------------------------------------------------- */
    /*                                    enums                                   */
    /* -------------------------------------------------------------------------- */
    enum ProposalType {
        NONE, //default value for unset proposals
        VETO_COUNCIL_ELECTION_OR_SLASH,
        GCA_COUNCIL_ELECTION_OR_SLASH,
        GRANTS_PROPOSAL,
        CHANGE_GCA_REQUIREMENTS,
        REQUEST_FOR_COMMENT
    }

    enum ProposalStatus {
        NONE,
        EXECUTED_WITH_ERROR,
        EXECUTED_SUCCESSFULLY,
        VETOED
    }

    /* -------------------------------------------------------------------------- */
    /*                                   structs                                  */
    /* -------------------------------------------------------------------------- */
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

    /* -------------------------------------------------------------------------- */
    /*                                   events                                   */
    /* -------------------------------------------------------------------------- */
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
     * @param rfcHash the hash of the requirements string
     * @param nominationsUsed the amount of nominations used
     */
    event RFCProposalCreation(
        uint256 indexed proposalId, address indexed proposer, bytes32 rfcHash, uint256 nominationsUsed
    );

    /**
     * @notice emitted when a long glow staker casts a ratify vote on a proposal
     * @param proposalId the id of the proposal
     * @param voter the address of the voter
     * @param numVotes the number of ratify votes
     */
    event RatifyCast(uint256 indexed proposalId, address indexed voter, uint256 numVotes);

    /**
     * @notice emitted when a long glow staker casts a reject vote on a proposal
     * @param proposalId the id of the proposal
     * @param voter the address of the voter
     * @param numVotes the number of reject votes
     */
    event RejectCast(uint256 indexed proposalId, address indexed voter, uint256 numVotes);

    /**
     * @notice emitted when nominations are used on a proposal
     * @param proposalId the id of the proposal
     * @param spender the address of the spender
     * @param amount the amount of nominations used
     */
    event NominationsUsedOnProposal(uint256 indexed proposalId, address indexed spender, uint256 amount);

    /**
     * @notice emitted when a proposal is set as the most popular proposal at a week
     * @param weekId - the weekId in which the proposal was selected as the most popular proposal
     * @param proposalId - the id of the proposal that was selected as the most popular proposal
     */
    event MostPopularProposalSet(uint256 indexed weekId, uint256 indexed proposalId);

    /**
     * @notice emitted when a proposal is ratified
     * @param weekId - the weekId in which the proposal to be vetoed was selected as the most popular proposal
     * @param vetoer - the address of the veto council member who vetoed the proposal
     * @param proposalId - the id of the proposal that was vetoed
     */
    event ProposalVetoed(uint256 indexed weekId, address indexed vetoer, uint256 proposalId);

    /**
     * @notice emitted when an rfc proposal is executed succesfully.
     * - RFC Proposals don't change the state of the system, so rather than performing state changes
     *         - we emit an event to alert that the proposal was executed succesfully
     *         - and that the rfc requires attention
     * @param proposalId - the id of the proposal from which the rfc was created
     * @param requirementsHash - the hash of the requirements string
     */
    event RFCProposalExecuted(uint256 indexed proposalId, bytes32 requirementsHash);

    /**
     * @notice emitted when a proposal is executed  for the week
     * @param week - the week for which the proposal was the most popular proposal
     * @param proposalId - the id of the proposal that was executed
     * @param proposalType - the type of the proposal that was executed
     * @param success - whether or not the proposal was executed succesfully
     */
    event ProposalExecution(uint256 indexed week, uint256 proposalId, ProposalType proposalType, bool success);

    /**
     * @notice Allows the GCC contract to grant nominations to {to} when they retire GCC
     * @param to the address to grant nominations to
     * @param amount the amount of nominations to grant
     */
    function grantNominations(address to, uint256 amount) external;

    /**
     * @notice Executes a most popular proposal at a given week
     * @dev a proposal that has not been ratified or rejected can be executed
     *         - but should never make any changes to the system (exceptions are detailed in the implementation)
     * @dev proposals that have met their requirements to perform state changes are executed as well
     * @dev no execution of any proposal should ever revert as this will freeze the governance contract
     * @param weekId the weekId that containst the 'mostPopularProposal' at that week
     * @dev proposals must be executed synchronously to ensure that the state of the system is consistent
     */
    function executeProposalAtWeek(uint256 weekId) external;

    /**
     * @notice syncs all proposals that must be synced
     */
    function syncProposals() external;

    /**
     * @notice allows a veto council member to endorse a gca election
     * @param weekId the weekId of the gca election to endorse
     */
    function endorseGCAProposal(uint256 weekId) external;
}

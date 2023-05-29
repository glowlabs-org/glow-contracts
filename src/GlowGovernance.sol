// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract GlowGovernance {
    mapping(address => uint256) private _nominationBalances;

    enum ProposalType {
        VetoCouncilElectionOrSlash,
        GCACouncilElectionOrSlash,
        SelectNewReserveCurrency,
        GrantsProposal
    }

    enum VetoCouncilDecision {
        ABSTAIN,
        VETO,
        APPROVE
    }

    struct Proposal {
        ProposalType proposalType;
        bytes data;
    }

    /// @dev should emit a VetoCouncilElectionOrSlash event
    /// @param proposalId the id of the proposal
    /// @param proposer the address of the proposer
    /// @param oldCouncilMembers the old council members that are to be slashed
    /// @param newCouncilMembers the new council members that are to be elected
    event VetoCouncilElectionOrSlash(
        uint256 indexed proposalId, address indexed proposer, address[] oldCouncilMembers, address[] newCouncilMembers
    );

    /// @dev should emit a GCACouncilElectionOrSlash event
    /// @param proposalId the id of the proposal
    /// @param proposer the address of the proposer
    /// @param oldCouncilMembers the old council members that are to be slashed
    /// @param newCouncilMembers the new council members that are to be elected
    event GCACouncilElectionOrSlash(
        uint256 indexed proposalId, address indexed proposer, address[] oldCouncilMembers, address[] newCouncilMembers
    );

    /// @dev should emit a SelectNewReserveCurrency event
    /// @param proposalId the id of the proposal
    /// @param proposer the address of the proposer
    /// @param oldReserveCurrency the old reserve currency
    event SelectNewReserveCurrency(
        uint256 indexed proposalId, address indexed proposer, address oldReserveCurrency, address newReserveCurrency
    );

    /// @dev should emit a GrantsProposal event
    /// @param proposalId the id of the proposal
    /// @param proposer the address of the proposer
    /// @param recipients the addresses of the recipients
    event GrantsProposal(uint256 indexed proposalId, address indexed proposer, address[] recipients, uint256[] amounts);

    /// @param account the account to check
    /// @return the number of nominations for an account
    function nominationsOf(address account) public view returns (uint256) {
        return _nominationBalances[account];
    }

    /// @dev should return the total number of active nominations
    function numActiveNominations() public view returns (uint256) {
        return 0;
    }

    /// @notice creates a proposal to elect or slash new council members
    /// @param oldCouncilMembers the old council members that are to be slashed
    /// @param newCouncilMembers the new council members that are to be elected
    /// @dev must emit a VetoCouncilElectionOrSlash event
    function createVetoCouncilProposal(address[] memory oldCouncilMembers, address[] memory newCouncilMembers)
        external
    {}

    /// @notice creates a proposal to elect or slash new council members
    /// @param oldCouncilMembers the old council members that are to be slashed
    /// @param newCouncilMembers the new council members that are to be elected
    /// @dev must emit a GCACouncilElectionOrSlash event
    function createGCACouncilProposal(address[] memory oldCouncilMembers, address[] memory newCouncilMembers)
        external
    {}

    /// @notice creates a proposal to select a new reserve currency
    /// @param newReserveCurrency is the new reserve currency the protocol will use
    /// @dev must emit a SelectNewReserveCurrency event
    function createSelectNewReserveCurrencyProposal(address newReserveCurrency) external {}

    /// @notice creates a proposal to fund a grants
    /// @param recipients - the recipients of GLW
    /// @param amounts - the amounts of GLW each recipient will receive
    function createGrantsProposal(address[] memory recipients, uint256[] memory amounts) external {}

    /// @dev should return the current active proposal with the most nominations
    function mostPopularProposal() external view returns (ProposalType, bytes memory) {}

    /// @dev should return the proposalId of the last valid proposal
    /// @dev proposals have a 4 month TTL
    function lastValidProposalId() external view returns (uint256) {}

    /// @dev should return block.timestamp - 4 months
    function _lastValidProposalStartTimestamp() internal pure returns (uint256) {}

    /// @dev should select a proposal for review
    /// @dev can only be called maximum once every 2 weeks.
    /// @dev anyone can call this function
    function selectProposalForReview() external {}

    /// @notice the entry point for veto council members to vote on a proposal
    /// @dev this function must only be called by veto council members, this is fetched from veto council contract
    /// @dev the default is abstain and council members will automatically abstain if they don't take on-chain action
    /// @dev Exception: veto council members can't vote on veto slashing
    /// @param proposalId - the id of the proposal the council member is voting on.
    /// @param decision - the decision the veto council member has made.
    function vetoCouncilVote(uint256 proposalId, VetoCouncilDecision decision) external {}

    /// @notice long staked GLW holders will be able to cast ratify or reject votes on proposals
    /// @param proposalId the id of the proposal to vote on.
    /// @param ratifyOrReject - select true if user wishes to ratify and false if reject
    /// @param numVotes - the number of ratify or reject votes.
    /// @dev Exception: Long Staked GLW Holders can't vote on Grants Proposals
    /// TODO: What happens when a holder unstakes
    function ratifyOrReject(uint256 proposalId, bool ratifyOrReject, uint256 numVotes) external {}

    /// @notice execute's a proposal on-chain
    /// @dev should correctly check against all rules and make proper cross-chain calls
    /// @dev if proposal type is to select a new GRC, then a fair auction contract will be launched between the two ERC20's
    function executeProposal(uint256 proposalId) external {}

    /// @dev only callable by GCC contract to grant an account nominations when they retire GCC
    /// @param account - the account to grant nominations to
    /// @param amount - the amount of nominations to grant
    function grantNominations(address account, uint256 amount) external {}
}

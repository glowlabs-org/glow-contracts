// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {IGovernance} from "@/interfaces/IGovernance.sol";
import {HalfLife} from "@/libraries/HalfLife.sol";
import {ABDKMath64x64} from "@/libraries/ABDKMath64x64.sol";
//TEMP!

//TODO: make sure to put max nominations to spend so it reverts
//TODO: make sure to calculate  num active proposals correctly for when proposals get selected
//  -   could add a bool if it got selected.
contract Governance is IGovernance {
    using ABDKMath64x64 for int128;

    int128 private constant _ONE_64x64 = (1 << 64);
    int128 private constant _ONE_POINT_ONE_128 = (1 << 64) + 0x1999999999999a00;
    /**
     * @dev The maximum duration of a proposal: 16 weeks
     */
    uint256 private constant _MAX_PROPOSAL_DURATION = 9676800;

    struct Nominations {
        uint192 amount;
        uint64 lastUpdate;
    }

    mapping(address => Nominations) private _nominations;
    mapping(uint256 => IGovernance.Proposal) private _proposals;

    uint256[] private _proposalsThatNeedExecution;

    uint256 private _proposalCount;

    address private _gcc;
    address private _gca;
    address private _vetoCouncil;
    address private _grantsTreasury;
    address private _glw;

    uint256 public lastExpiredProposalId;
    uint256 public lastExecutedProposalId;

    /**
     * @notice Allows the GCC contract to grant nominations to {to} when they retire GCC
     * @param to the address to grant nominations to
     * @param amount the amount of nominations to grant
     */

    function grantNominations(address to, uint256 amount) external override {
        if (msg.sender != _gcc) {
            _revert(IGovernance.CallerNotGCC.selector);
        }
        //Step 1: check their current balance
        Nominations memory n = _nominations[to];
        uint256 currentBalance = HalfLife.calculateHalfLifeValue(n.amount, block.timestamp - n.lastUpdate);
        //Step 2: update their balance
        _nominations[to] = Nominations(uint192(currentBalance + amount), uint64(block.timestamp));
        return;
    }

    /**
     * @notice Gets the amount of nominations that an account has
     *             - adjusts for half-life of 12 months
     * @param account the account to get the nominations of
     * @return amount amount of nominations that the account has
     */
    function nominationsOf(address account) public view returns (uint256) {
        Nominations memory n = _nominations[account];
        uint256 elapsedSeconds = block.timestamp - n.lastUpdate;
        return HalfLife.calculateHalfLifeValue(n.amount, elapsedSeconds);
    }

    //TODO: Make sure it updates the most popular proposal
    //TODO: make sure it executes proposals

    /**
     * @notice Allows a user to vote on a proposal
     * @param proposalId the id of the proposal
     * @param amount the amount of nominations to vote with
     */
    function useNominationsOnProposal(uint256 proposalId, uint256 amount) public {
        uint256 currentBalance = nominationsOf(msg.sender);
        uint256 nominationEndTimestamp = _proposals[_proposalCount].expirationTimestamp;
        if (block.timestamp > nominationEndTimestamp) {
            _revert(IGovernance.ProposalExpired.selector);
        }
        if (currentBalance < amount) {
            _revert(IGovernance.InsufficientNominations.selector);
        }
        _proposals[proposalId].votes += uint184(amount);
        _nominations[msg.sender] = Nominations(uint192(currentBalance - amount), uint64(block.timestamp));
    }

    /// @inheritdoc IGovernance
    function getProposalWithStatus(uint256 proposalId)
        public
        view
        returns (Proposal memory proposal, IGovernance.ProposalStatus)
    {}

    function setContractAddresses(address gcc, address gca, address vetoCouncil, address grantsTreasury, address glw)
        external
    {
        if (!_isZeroAddress(_gcc)) {
            _revert(IGovernance.ContractsAlreadySet.selector);
        }
        _checkZeroAddress(gcc);
        _checkZeroAddress(gca);
        _checkZeroAddress(vetoCouncil);
        _checkZeroAddress(grantsTreasury);
        _checkZeroAddress(glw);

        _gcc = gcc;
        _gca = gca;
        _vetoCouncil = vetoCouncil;
        _grantsTreasury = grantsTreasury;
        _glw = glw;
    }
    /**
     * @notice Creates a proposal to send a grant to a recipient
     * @param grantsRecipient the recipient of the grant
     * @param amount the amount of the grant
     * @param hash the hash of the proposal
     *             - the pre-image should be made public off-chain
     */

    function createGrantsProposal(address grantsRecipient, uint256 amount, bytes32 hash) external {
        uint256 proposalId = _proposalCount;
        _proposals[proposalId] = IGovernance.Proposal(
            IGovernance.ProposalType.GRANTS_PROPOSAL,
            uint64(block.timestamp + _MAX_PROPOSAL_DURATION),
            0,
            abi.encode(grantsRecipient, amount, hash)
        );

        _proposalCount = proposalId + 1;

        emit IGovernance.GrantsProposalCreation(proposalId, msg.sender, grantsRecipient, amount, hash);

        _spendNominations(msg.sender, costForNewProposal());
    }

    /**
     * @notice Creates a proposal to change the GCA requirements
     * @param newRequirementsHash the new requirements hash
     *             - the pre-image should be made public off-chain
     */
    function createChangeGCARequirementsProposal(bytes32 newRequirementsHash) external {
        uint256 proposalId = _proposalCount;
        _proposals[proposalId] = IGovernance.Proposal(
            IGovernance.ProposalType.CHANGE_GCA_REQUIREMENTS,
            uint64(block.timestamp + _MAX_PROPOSAL_DURATION),
            0,
            abi.encode(newRequirementsHash)
        );

        _proposalCount = proposalId + 1;

        emit IGovernance.ChangeGCARequirementsProposalCreation(proposalId, msg.sender, newRequirementsHash);

        _spendNominations(msg.sender, costForNewProposal());
    }

    /**
     * @notice Creates a proposal to create an RFC
     *     - the pre-image should be made public off-chain
     *     - if accepted, veto council members must read the RFC (up to 10k Words) and provide a written statement on their thoughts
     *
     * @param hash the hash of the proposal
     */
    function createRFCProposal(bytes32 hash) external {
        uint256 proposalId = _proposalCount;
        _proposals[proposalId] = IGovernance.Proposal(
            IGovernance.ProposalType.REQUEST_FOR_COMMENT,
            uint64(block.timestamp + _MAX_PROPOSAL_DURATION),
            0,
            abi.encode(hash)
        );

        _proposalCount = proposalId + 1;

        emit IGovernance.RFCProposalCreation(proposalId, msg.sender, hash);

        _spendNominations(msg.sender, costForNewProposal());
    }

    function createGCACouncilElectionOrSlashProposal(address[] calldata agentsToSlash, address[] calldata newGCAs)
        external
    {
        //[agentsToSlash,newGCAs,proposalCreationTimestamp]
        bytes32 hash = keccak256(abi.encode(agentsToSlash, newGCAs, block.timestamp));
        uint256 proposalId = _proposalCount;
        _proposals[proposalId] = IGovernance.Proposal(
            IGovernance.ProposalType.GCA_COUNCIL_ELECTION_OR_SLASH,
            uint64(block.timestamp + _MAX_PROPOSAL_DURATION),
            0,
            abi.encode(hash)
        );

        _proposalCount = proposalId + 1;

        emit IGovernance.GCACouncilElectionOrSlashCreation(
            proposalId, msg.sender, agentsToSlash, newGCAs, block.timestamp
        );

        _spendNominations(msg.sender, costForNewProposal());
    }

    function createVetoCouncilElectionOrSlash(address oldAgent, address newAgent, bool slashOldAgent) external {
        uint256 proposalId = _proposalCount;
        _proposals[proposalId] = IGovernance.Proposal(
            IGovernance.ProposalType.VETO_COUNCIL_ELECTION_OR_SLASH,
            uint64(block.timestamp + _MAX_PROPOSAL_DURATION),
            0,
            abi.encode(oldAgent, newAgent, slashOldAgent)
        );

        _proposalCount = proposalId + 1;

        emit IGovernance.VetoCouncilElectionOrSlash(proposalId, msg.sender, oldAgent, newAgent, slashOldAgent);

        _spendNominations(msg.sender, costForNewProposal());
    }

    function createChangeReserveCurrencyProposal(address currencyToRemove, address newReserveCurrency) external {
        uint256 proposalId = _proposalCount;
        _proposals[proposalId] = IGovernance.Proposal(
            IGovernance.ProposalType.CHANGE_RESERVE_CURRENCIES,
            uint64(block.timestamp + _MAX_PROPOSAL_DURATION),
            0,
            abi.encode(currencyToRemove, newReserveCurrency)
        );

        _proposalCount = proposalId + 1;

        emit IGovernance.ChangeReserveCurrenciesProposal(proposalId, msg.sender, currencyToRemove, newReserveCurrency);

        _spendNominations(msg.sender, costForNewProposal());
    }

    function _spendNominations(address account, uint256 amount) private {
        uint256 currentBalance = nominationsOf(account);
        if (currentBalance < amount) {
            _revert(IGovernance.InsufficientNominations.selector);
        }
        _nominations[account] = Nominations(uint192(currentBalance - amount), uint64(block.timestamp));
    }

    function costForNewProposal() public view returns (uint256) {
        return 0;
    }

    function updateLastExpiredProposalIdAndGetNominationsRequired() public {
        (, uint256 _lastExpiredProposalId) = _numActiveProposalsAndLastExpiredProposalId();
        lastExpiredProposalId = _lastExpiredProposalId;
    }

    function _numActiveProposalsAndLastExpiredProposalId()
        public
        view
        returns (uint256 numActiveProposals, uint256 _lastExpiredProposalId)
    {
        uint256 _lastExpiredProposalId = lastExpiredProposalId;
        uint256 _proposalCount = _proposalCount;
        unchecked {
            for (uint256 i = _lastExpiredProposalId; i < _proposalCount; ++i) {
                if (_proposals[i].expirationTimestamp < block.timestamp) {
                    _lastExpiredProposalId = i;
                } else {
                    break;
                }
            }
        }
        numActiveProposals = _proposalCount - _lastExpiredProposalId;
        _lastExpiredProposalId = _lastExpiredProposalId;
    }

    function getNominationCostForProposalCreation() external view returns (uint256) {
        uint256 numActiveProposals;
        (numActiveProposals,) = _numActiveProposalsAndLastExpiredProposalId();
        return _getNominationCostForProposalCreation(numActiveProposals);
    }

    function _getNominationCostForProposalCreation(uint256 numActiveProposals) public pure returns (uint256) {
        int128 res = _ONE_64x64.mul(ABDKMath64x64.pow(_ONE_POINT_ONE_128, numActiveProposals));
        uint256 resInt = res.toUInt();
        return resInt * 1e14;
    }
    /**
     * @notice More efficiently reverts with a bytes4 selector
     * @param selector The selector to revert with
     */

    function _revert(bytes4 selector) private pure {
        assembly {
            mstore(0x0, selector)
            revert(0x0, 0x04)
        }
    }

    /**
     * @dev reverts if the address is the zero address
     * @param a the address to check
     */
    function _checkZeroAddress(address a) private pure {
        if (_isZeroAddress(a)) {
            _revert(IGovernance.ZeroAddressNotAllowed.selector);
        }
    }

    /**
     * @dev efficiently determines if an address is the zero address
     * @param a the address to check
     */
    function _isZeroAddress(address a) private pure returns (bool isZero) {
        assembly {
            isZero := iszero(a)
        }
    }
}

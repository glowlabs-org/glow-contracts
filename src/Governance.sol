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

    /**
     * @param amount the amount of nominations that an account has
     * @param lastUpdate the last time that the account's balance was updated
     *         -   {lastUpdate} is used to calculate the user's balance according to the half-life formula
     *         -   Check {HalfLife.calculateHalfLifeValue} for more details
     */
    struct Nominations {
        uint192 amount;
        uint64 lastUpdate;
    }

    /**
     * @dev The nominations of each account
     */
    mapping(address => Nominations) private _nominations;

    /**
     * @dev The proposals
     */
    mapping(uint256 => IGovernance.Proposal) private _proposals;

    /**
     * @dev The proposals that need to be executed
     */
    uint256[] private _proposalsThatNeedExecution;

    /**
     * @dev The total number of proposals created
     */
    uint256 private _proposalCount;

    /**
     * @dev The GCC contract
     */
    address private _gcc;

    /**
     * @dev The GCA contract
     */
    address private _gca;

    /**
     * @dev The Veto Council contract
     */
    address private _vetoCouncil;

    /**
     * @dev The Grants Treasury contract
     */
    address private _grantsTreasury;

    /**
     * @dev The GLW contract
     */
    address private _glw;

    /**
     * @notice The last updated proposal id (should not be used for anything other than caching)
     * @dev The last proposal that expired (in storage)
     * @dev this may be out of sync with the actual last expired proposal id
     *      -  it's used as a cache to make _numActiveProposalsAndLastExpiredProposalId() more efficient
     * @return lastExpiredProposalId the last expired proposal id
     */
    uint256 public lastExpiredProposalId;

    /**
     * @notice the last executed proposal id (should not be used for anything other than caching)
     * @dev The last proposal that was executed
     * @dev this may be out of sync with the actual last executed proposal id
     */
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
     * @param maxNominations the maximum amount of nominations to spend on this proposal
     */

    function createGrantsProposal(address grantsRecipient, uint256 amount, bytes32 hash, uint256 maxNominations)
        external
    {
        uint256 proposalId = _proposalCount;
        uint256 nominationCost = costForNewProposal();
        if (maxNominations < nominationCost) {
            _revert(IGovernance.NominationCostGreaterThanAllowance.selector);
        }
        _spendNominations(msg.sender, nominationCost);
        _proposals[proposalId] = IGovernance.Proposal(
            IGovernance.ProposalType.GRANTS_PROPOSAL,
            uint64(block.timestamp + _MAX_PROPOSAL_DURATION),
            uint184(nominationCost),
            abi.encode(grantsRecipient, amount, hash)
        );

        _proposalCount = proposalId + 1;

        emit IGovernance.GrantsProposalCreation(proposalId, msg.sender, grantsRecipient, amount, hash);
    }

    /**
     * @notice Creates a proposal to change the GCA requirements
     * @param newRequirementsHash the new requirements hash
     *             - the pre-image should be made public off-chain
     * @param maxNominations the maximum amount of nominations to spend on this proposal
     */
    function createChangeGCARequirementsProposal(bytes32 newRequirementsHash, uint256 maxNominations) external {
        uint256 proposalId = _proposalCount;
        uint256 nominationCost = costForNewProposal();
        if (maxNominations < nominationCost) {
            _revert(IGovernance.NominationCostGreaterThanAllowance.selector);
        }
        _spendNominations(msg.sender, nominationCost);
        _proposals[proposalId] = IGovernance.Proposal(
            IGovernance.ProposalType.CHANGE_GCA_REQUIREMENTS,
            uint64(block.timestamp + _MAX_PROPOSAL_DURATION),
            uint184(nominationCost),
            abi.encode(newRequirementsHash)
        );

        _proposalCount = proposalId + 1;

        emit IGovernance.ChangeGCARequirementsProposalCreation(proposalId, msg.sender, newRequirementsHash);
    }

    /**
     * @notice Creates a proposal to create an RFC
     *     - the pre-image should be made public off-chain
     *     - if accepted, veto council members must read the RFC (up to 10k Words) and provide a written statement on their thoughts
     *
     * @param hash the hash of the proposal
     * @param maxNominations the maximum amount of nominations to spend on this proposal
     */
    function createRFCProposal(bytes32 hash, uint256 maxNominations) external {
        uint256 proposalId = _proposalCount;
        uint256 nominationCost = costForNewProposal();
        if (maxNominations < nominationCost) {
            _revert(IGovernance.NominationCostGreaterThanAllowance.selector);
        }
        _spendNominations(msg.sender, nominationCost);

        _proposals[proposalId] = IGovernance.Proposal(
            IGovernance.ProposalType.REQUEST_FOR_COMMENT,
            uint64(block.timestamp + _MAX_PROPOSAL_DURATION),
            uint184(nominationCost),
            abi.encode(hash)
        );

        _proposalCount = proposalId + 1;

        emit IGovernance.RFCProposalCreation(proposalId, msg.sender, hash);
    }

    /**
     * @notice Creates a proposal to add, replace, or slash GCA council members
     * @param agentsToSlash an array of all gca's that are to be slashed
     *         - could be empty
     *         - could be a subset of the current GCAs
     *         - could be any address [in order to account for previous GCA's]
     * @param newGCAs the new GCAs
     *     -   can be empty if all GCA's are bad actors
     * @param maxNominations the maximum amount of nominations to spend on this proposal
     */
    function createGCACouncilElectionOrSlashProposal(
        address[] calldata agentsToSlash,
        address[] calldata newGCAs,
        uint256 maxNominations
    ) external {
        //[agentsToSlash,newGCAs,proposalCreationTimestamp]
        bytes32 hash = keccak256(abi.encode(agentsToSlash, newGCAs, block.timestamp));
        uint256 proposalId = _proposalCount;
        uint256 nominationCost = costForNewProposal();
        if (maxNominations < nominationCost) {
            _revert(IGovernance.NominationCostGreaterThanAllowance.selector);
        }
        _spendNominations(msg.sender, nominationCost);
        _proposals[proposalId] = IGovernance.Proposal(
            IGovernance.ProposalType.GCA_COUNCIL_ELECTION_OR_SLASH,
            uint64(block.timestamp + _MAX_PROPOSAL_DURATION),
            uint184(nominationCost),
            abi.encode(hash)
        );

        _proposalCount = proposalId + 1;

        emit IGovernance.GCACouncilElectionOrSlashCreation(
            proposalId, msg.sender, agentsToSlash, newGCAs, block.timestamp
        );
    }

    /**
     * @notice Creates a proposal to add, replace, or slash Veto a single veto council member
     * @param oldAgent the old agent to be replaced
     *         -   If the agent is address(0), it means we are simply adding a new agent
     * @param newAgent the new agent to replace the old agent
     *         -   If the agent is address(0), it means we are simply removing an agent
     * @param slashOldAgent whether or not to slash the old agent
     * @param maxNominations the maximum amount of nominations to spend on this proposal
     */
    function createVetoCouncilElectionOrSlash(
        address oldAgent,
        address newAgent,
        bool slashOldAgent,
        uint256 maxNominations
    ) external {
        uint256 proposalId = _proposalCount;
        uint256 nominationCost = costForNewProposal();
        if (maxNominations < nominationCost) {
            _revert(IGovernance.NominationCostGreaterThanAllowance.selector);
        }
        _spendNominations(msg.sender, nominationCost);
        _proposals[proposalId] = IGovernance.Proposal(
            IGovernance.ProposalType.VETO_COUNCIL_ELECTION_OR_SLASH,
            uint64(block.timestamp + _MAX_PROPOSAL_DURATION),
            uint184(nominationCost),
            abi.encode(oldAgent, newAgent, slashOldAgent, block.timestamp)
        );

        _proposalCount = proposalId + 1;

        emit IGovernance.VetoCouncilElectionOrSlash(proposalId, msg.sender, oldAgent, newAgent, slashOldAgent);
    }

    /**
     * @notice Creates a proposal to change a reserve currency
     * @param currencyToRemove the currency to remove
     *     -   If the currency is address(0), it means we are simply adding a new reserve currency
     * @param newReserveCurrency the new reserve currency
     *     -   If the currency is address(0), it means we are simply removing a reserve currency
     * @param maxNominations the maximum amount of nominations to spend on this proposal
     */
    function createChangeReserveCurrencyProposal(
        address currencyToRemove,
        address newReserveCurrency,
        uint256 maxNominations
    ) external {
        uint256 proposalId = _proposalCount;
        uint256 nominationCost = costForNewProposal();
        if (maxNominations < nominationCost) {
            _revert(IGovernance.NominationCostGreaterThanAllowance.selector);
        }
        _proposals[proposalId] = IGovernance.Proposal(
            IGovernance.ProposalType.CHANGE_RESERVE_CURRENCIES,
            uint64(block.timestamp + _MAX_PROPOSAL_DURATION),
            uint184(nominationCost),
            abi.encode(currencyToRemove, newReserveCurrency)
        );

        _proposalCount = proposalId + 1;

        emit IGovernance.ChangeReserveCurrenciesProposal(proposalId, msg.sender, currencyToRemove, newReserveCurrency);

        _spendNominations(msg.sender, nominationCost);
    }

    /**
     * @dev helper func to spend nominations from an account
     *         -   should never be public
     * @param account the account to spend nominations from
     * @param amount the amount of nominations to spend
     */
    function _spendNominations(address account, uint256 amount) private {
        uint256 currentBalance = nominationsOf(account);
        if (currentBalance < amount) {
            _revert(IGovernance.InsufficientNominations.selector);
        }
        _nominations[account] = Nominations(uint192(currentBalance - amount), uint64(block.timestamp));
    }

    /**
     * @notice Gets the cost for a new proposal
     * @return cost the cost for a new proposal
     * @dev calculates cost as 1 * 1.1^numActiveProposals
     */
    function costForNewProposal() public view returns (uint256) {
        uint256 numActiveProposals;
        (numActiveProposals,) = _numActiveProposalsAndLastExpiredProposalId();
        return _getNominationCostForProposalCreation(numActiveProposals);
    }

    /**
     * @notice Updates the last expired proposal id
     *         - could be called by a good actor to update the last expired proposal id
     *         - so that _numActiveProposalsAndLastExpiredProposalId() is more efficient
     */
    function updateLastExpiredProposalId() public {
        (, uint256 _lastExpiredProposalId) = _numActiveProposalsAndLastExpiredProposalId();
        lastExpiredProposalId = _lastExpiredProposalId;
    }

    /**
     * @notice Gets the number of active proposals and the last expired proposal id
     * @return numActiveProposals the number of active proposals
     * @return _lastExpiredProposalId the last expired proposal id
     */
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

    /**
     * @notice Gets the total number of proposals created
     * @return proposalCount - the total number of proposals created
     */
    function proposalCount() external view returns (uint256) {
        return _proposalCount;
    }

    /**
     * @notice Gets the proposal at a given id
     * @param proposalId the id of the proposal
     * @return proposal the proposal at the given id
     */
    function proposals(uint256 proposalId) external view returns (IGovernance.Proposal memory) {
        return _proposals[proposalId];
    }

    /**
     * @notice Gets the nomination cost for proposal creation based on {numActiveProposals}
     * @param numActiveProposals the number of active proposals
     * @return res the nomination cost for proposal creation
     * @dev calculates cost as 1 * 1.1^numActiveProposals
     * @dev we only use 4 decimals of precision
     */
    function _getNominationCostForProposalCreation(uint256 numActiveProposals) public pure returns (uint256) {
        uint256 res = _ONE_64x64.mul(ABDKMath64x64.pow(_ONE_POINT_ONE_128, numActiveProposals)).mulu(1e4);
        // uint256 resInt = res.toUInt();
        return res * 1e14;
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

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {IGovernance} from "@/interfaces/IGovernance.sol";
import {HalfLife} from "@/libraries/HalfLife.sol";
import {ABDKMath64x64} from "@/libraries/ABDKMath64x64.sol";
import {IGlow} from "@/interfaces/IGlow.sol";
import {IVetoCouncil} from "@/interfaces/IVetoCouncil.sol";
import {IGCA} from "@/interfaces/IGCA.sol";
import {IGrantsTreasury} from "@/interfaces/IGrantsTreasury.sol";
import {IMinerPool} from "@/interfaces/IMinerPool.sol";
import "forge-std/console.sol";

contract Governance is IGovernance {
    using ABDKMath64x64 for int128;

    /// @dev one in 64x64 fixed point
    int128 private constant _ONE_64x64 = (1 << 64);

    /// @dev one point one in 64x64 fixed point
    int128 private constant _ONE_POINT_ONE_128 = (1 << 64) + 0x1999999999999a00;

    /// @dev The duration of a bucket: 1 week
    uint256 private constant _ONE_WEEK = uint256(7 days);

    /**
     * @dev The maximum duration of a proposal: 16 weeks
     */
    uint256 private constant _MAX_PROPOSAL_DURATION = 9676800;

    /// @dev the maximum number of weeks a proposal can be ratified or rejected
    ///      - from the time it it has been finalized (i.e. the week has passed)
    /// For example: If proposal 1 is the most popular proposal for week 2, then it can be ratified or rejected until the end of week 6
    uint256 private constant _NUM_WEEKS_TO_VOTE_ON_MOST_POPULAR_PROPOSAL = 4;

    uint256 private constant _DEFAULT_PERCENTAGE_TO_EXECUTE_PROPOSAL = 60; //60%
    uint256 private constant _MAX_ENDORSEMENTS_ON_GCA_PROPOSALS = 5;
    uint256 private constant _ENDORSEMENT_WEIGHT = 5;

    /**
     * @dev The total number of proposals created
     * @dev we start at one to ensure that a proposal with id 0 is invalid
     */
    uint256 private _proposalCount = 1;

    /**
     * @dev The GCC contract
     */
    address private _gcc;

    /**
     * @dev The GCA contract
     */
    address private _gca;

    /**
     * @dev The Genesis Timestamp of the protocol from GLW
     */
    uint256 private _genesisTimestamp;

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
    uint256 public lastExecutedWeek = type(uint256).max;

    /**
     * @notice Allows the GCC contract to grant nominations to {to} when they retire GCC
     * @param to the address to grant nominations to
     * @param amount the amount of nominations to grant
     */

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
     * @param ratifyVotes - the amount of ratify votes on the proposal
     * @param rejectionVotes - the amount of rejection votes on the proposal
     * @dev only most popular proposals can be voted on
     */
    struct ProposalLongStakerVotes {
        uint128 ratifyVotes;
        uint128 rejectionVotes;
    }

    /**
     * @dev proposalId -> _proposalLongStakerVotes
     * @dev long stakers can only vote on proposals that are the most popular proposal for their respective week
     *             - The week must have already passed
     */
    mapping(uint256 => ProposalLongStakerVotes) private _proposalLongStakerVotes;

    /**
     * @dev address -> proposalId -> numVotes
     * @dev long stakers can only vote on proposals that are the most popular proposal for their respective week
     *             - The week must have already passed
     * @dev Users can have as many votes as number of glow staked they have.
     *         -   we need this mapping to prevent double spend.
     *         -   the protocol does not worry about adjusting for unstaked glow
     *             - for example, a user is allowed to stake 100 glw , vote on a proposal, and then unstake 100 glw
     *             - the protocol will not adjust for the unstaked glw
     *             - there is a 5 year cooldown for unstaking glw so this should not be a problem
     */
    mapping(address => mapping(uint256 => uint256)) public longStakerVotesForProposal;

    /**
     * @dev The nominations of each account
     */
    mapping(address => Nominations) private _nominations;

    /**
     * @dev The proposals
     */
    mapping(uint256 => IGovernance.Proposal) private _proposals;

    /**
     * @notice the most popular proposal at a given week
     * @dev It is manually updated whenever an action is triggered
     */
    mapping(uint256 => uint256) public mostPopularProposal;

    /// @dev The most popular proposal status at a given week
    /// @dev for example, if the most popular proposal at week 0 is 5,
    ///     -   then mostPopularProposalStatusByWeek[0] =  Proposal 5 Status
    /// @dev since there are only 8 proposal statuses, we can use a uint256 to store the status
    /// @dev each uint256 is 32 bytes, so we can store 32 statuses in a single uint256
    mapping(uint256 => uint256) private _packedMostPopularProposalStatusByWeek;

    mapping(uint256 => uint256) public numEndorsementsOnWeek;
    mapping(address => mapping(uint256 => uint256)) private _hasEndorsedProposalBitmap;

    function executeProposalAtWeek(uint256 week) public {
        uint256 _nextProposalToExecute = lastExecutedWeek;
        unchecked {
            //We actually want this to overflow
            ++_nextProposalToExecute;
        }

        //We need all proposals to be executed synchronously
        if (_nextProposalToExecute != week) {
            _revert(IGovernance.ProposalsMustBeExecutedSynchonously.selector);
        }

        //If the proposal is vetoed, we can skip the execution
        //We still need to update the lastExecutedWeek so the next proposal can be executed
        if (getMostPopularProposalStatus(week) == IGovernance.ProposalStatus.VETOED) {
            lastExecutedWeek = week;
            return;
        }

        uint256 proposalId = mostPopularProposal[week];

        IGovernance.Proposal memory proposal = _proposals[proposalId];
        IGovernance.ProposalType proposalType = proposal.proposalType;
        ProposalLongStakerVotes memory longStakerVotes = _proposalLongStakerVotes[proposalId];

        //RFC Proposals  an grant proposals Are The Only Types that don't need to be ratified or rejected
        //So we can execute them as soon as they are passed
        // all others need to wait 4 weeks after they are passed
        //None can also be executed immediately
        if (
            proposalType == IGovernance.ProposalType.REQUEST_FOR_COMMENT
                || proposalType == IGovernance.ProposalType.GRANTS_PROPOSAL || proposalType == IGovernance.ProposalType.NONE
        ) {
            //as sooon as the RFC is passed, we can execute it
            //we don't need to wait for the ratify/reject period to end
            if (block.timestamp < _weekEndTime(week) + 1) {
                _revert(IGovernance.RatifyOrRejectPeriodNotEnded.selector);
            }
            //If a most popular proposal never got chosen for the week,
            //we can execute it at the end of the week
            //since it can never be chosen as a most popular proposal again
            if (proposalType == IGovernance.ProposalType.NONE) {
                lastExecutedWeek = week;
                return;
            }
        } else {
            //For all other proposals, we need to make sure that the ratify/reject period has ended
            if (block.timestamp < _weekEndTime(week + _NUM_WEEKS_TO_VOTE_ON_MOST_POPULAR_PROPOSAL)) {
                _revert(IGovernance.RatifyOrRejectPeriodNotEnded.selector);
            }
        }

        //Start C2:
        //C2 checks to see if there are enough ratify votes to execute the proposal

        //If the proposal is a gca election, we can check endorsements to
        //dynamically determine the required percentage to execute the proposal
        //The default percentage to execute a  proposal is 60%
        //The minimum percentage to execute a gca proposal is 35%
        //RFC and Grants Treasury proposals don't need to be ratified to pass
        if (proposalType == IGovernance.ProposalType.GCA_COUNCIL_ELECTION_OR_SLASH) {
            uint256 numEndorsements = numEndorsementsOnWeek[week];
            uint256 requiredWeight = _DEFAULT_PERCENTAGE_TO_EXECUTE_PROPOSAL - (numEndorsements * _ENDORSEMENT_WEIGHT);
            uint256 totalVotes = longStakerVotes.ratifyVotes + longStakerVotes.rejectionVotes;
            //If no one votes, we don't execute the proposal
            if (totalVotes == 0) {
                lastExecutedWeek = week;
                return;
            }
            uint256 percentage = (longStakerVotes.ratifyVotes * 100) / totalVotes;
            if (percentage < requiredWeight) {
                lastExecutedWeek = week;
                return;
            }
        } else {
            if (
                (
                    proposalType != IGovernance.ProposalType.REQUEST_FOR_COMMENT
                        || proposalType != IGovernance.ProposalType.GRANTS_PROPOSAL
                )
            ) {
                uint256 totalVotes = longStakerVotes.ratifyVotes + longStakerVotes.rejectionVotes;
                if (totalVotes == 0) {
                    lastExecutedWeek = week;
                    return;
                }
                uint256 percentage = (longStakerVotes.ratifyVotes * 100) / totalVotes;
                if (percentage < _DEFAULT_PERCENTAGE_TO_EXECUTE_PROPOSAL) {
                    lastExecutedWeek = week;
                    return;
                }
            }
        }

        handleProposalExecution(proposalId, proposalType, proposal.data);
        lastExecutedWeek = week;
    }

    function syncProposals() public {
        uint256 currentWeek = currentWeek();
        if (currentWeek == 0) return;
        uint256 _nextProposalToExecute = lastExecutedWeek;
        unchecked {
            //We actually want this to overflow since we start at type(uint256).max
            ++_nextProposalToExecute;
            //increment current week to not have to <= check, we can just < check in the for loop
            ++currentWeek;
            //we increment up the the current week to make sure that _weekEndTime(_nextProposalToExecute)
            //eventually becomes greater than block.timestamp so we can stop the loop and update state
        }

        for (_nextProposalToExecute; _nextProposalToExecute < currentWeek; ++_nextProposalToExecute) {
            //If the proposal is vetoed, we can skip the execution
            //We still need to update the lastExecutedWeek so the next proposal can be executed
            if (getMostPopularProposalStatus(_nextProposalToExecute) == IGovernance.ProposalStatus.VETOED) {
                continue;
            }

            uint256 proposalId = mostPopularProposal[_nextProposalToExecute];

            IGovernance.Proposal memory proposal = _proposals[proposalId];
            IGovernance.ProposalType proposalType = proposal.proposalType;
            ProposalLongStakerVotes memory longStakerVotes = _proposalLongStakerVotes[proposalId];

            //RFC Proposals  an grant proposals Are The Only Types that don't need to be ratified or rejected
            //So we can execute them as soon as they are passed
            // all others need to wait 4 weeks after they are passed
            //None can also be executed immediately
            if (
                proposalType == IGovernance.ProposalType.REQUEST_FOR_COMMENT
                    || proposalType == IGovernance.ProposalType.GRANTS_PROPOSAL
                    || proposalType == IGovernance.ProposalType.NONE
            ) {
                //as sooon as the RFC is passed, we can execute it
                //we don't need to wait for the ratify/reject period to end
                //This makes sure that we don't execute a proposal before the end of the week

                if (block.timestamp < _weekEndTime(_nextProposalToExecute) + 1) {
                    lastExecutedWeek = _nextProposalToExecute - 1;
                    return;
                }

                //If a most popular proposal never got chosen for the week,
                //we can execute it at the end of the week
                //since it can never be chosen as a most popular proposal again
                if (proposalType == IGovernance.ProposalType.NONE) {
                    continue;
                }
            } else {
                //For all other proposals, we need to make sure that the ratify/reject period has ended
                if (
                    block.timestamp < _weekEndTime(_nextProposalToExecute + _NUM_WEEKS_TO_VOTE_ON_MOST_POPULAR_PROPOSAL)
                ) {
                    lastExecutedWeek = _nextProposalToExecute - 1;
                    return;
                }
            }

            //Start C2:
            //C2 checks to see if there are enough ratify votes to execute the proposal

            //If the proposal is a gca election, we can check endorsements to
            //dynamically determine the required percentage to execute the proposal
            //The default percentage to execute a  proposal is 60%
            //The minimum percentage to execute a gca proposal is 35%
            //RFC and Grants Treasury proposals don't need to be ratified to pass
            if (proposalType == IGovernance.ProposalType.GCA_COUNCIL_ELECTION_OR_SLASH) {
                uint256 numEndorsements = numEndorsementsOnWeek[_nextProposalToExecute];
                uint256 requiredWeight =
                    _DEFAULT_PERCENTAGE_TO_EXECUTE_PROPOSAL - (numEndorsements * _ENDORSEMENT_WEIGHT);
                uint256 totalVotes = longStakerVotes.ratifyVotes + longStakerVotes.rejectionVotes;
                //If no one votes, we don't execute the proposal
                if (totalVotes == 0) {
                    continue;
                }
                uint256 percentage = (longStakerVotes.ratifyVotes * 100) / totalVotes;
                if (percentage < requiredWeight) {
                    continue;
                }
            } else {
                if (
                    (
                        proposalType != IGovernance.ProposalType.REQUEST_FOR_COMMENT
                            || proposalType != IGovernance.ProposalType.GRANTS_PROPOSAL
                    )
                ) {
                    uint256 totalVotes = longStakerVotes.ratifyVotes + longStakerVotes.rejectionVotes;
                    if (totalVotes == 0) {
                        continue;
                    }
                    uint256 percentage = (longStakerVotes.ratifyVotes * 100) / totalVotes;
                    if (percentage < _DEFAULT_PERCENTAGE_TO_EXECUTE_PROPOSAL) {
                        continue;
                    }
                }
            }

            handleProposalExecution(proposalId, proposalType, proposal.data);
        }
    }

    function handleProposalExecution(uint256 proposalId, IGovernance.ProposalType proposalType, bytes memory data)
        internal
    {
        if (proposalType == IGovernance.ProposalType.VETO_COUNCIL_ELECTION_OR_SLASH) {
            (address oldAgent, address newAgent, bool slashOldAgent) = abi.decode(data, (address, address, bool));
            IVetoCouncil(_vetoCouncil).addAndRemoveCouncilMember(oldAgent, newAgent, slashOldAgent);
        }

        if (proposalType == IGovernance.ProposalType.GCA_COUNCIL_ELECTION_OR_SLASH) {
            (bytes32 hash, bool incrementSlashNonce) = abi.decode(data, (bytes32, bool));
            IGCA(_gca).pushHash(hash, incrementSlashNonce);
        }

        if (proposalType == IGovernance.ProposalType.CHANGE_RESERVE_CURRENCIES) {
            (address oldReserveCurrency, address newReserveCurrency) = abi.decode(data, (address, address));
            IMinerPool(_gca).editReserveCurrencies(oldReserveCurrency, newReserveCurrency);
        }

        if (proposalType == IGovernance.ProposalType.GRANTS_PROPOSAL) {
            (address grantsRecipient, uint256 amount,) = abi.decode(data, (address, uint256, bytes32));
            bool success = IGrantsTreasury(_grantsTreasury).allocateGrantFunds(grantsRecipient, amount);
            //do something with success?
        }

        if (proposalType == IGovernance.ProposalType.CHANGE_GCA_REQUIREMENTS) {
            (bytes32 newRequirementsHash) = abi.decode(data, (bytes32));
            IGCA(_gca).setRequirementsHash(newRequirementsHash);
        }

        if (proposalType == IGovernance.ProposalType.REQUEST_FOR_COMMENT) {
            bytes32 rfcHash = abi.decode(data, (bytes32));
            emit IGovernance.RFCProposalExecuted(proposalId, rfcHash);
        }
    }

    //TODO: make sure that the same proposal can't be executed twice :)
    // we cant enforce that the same proposal cant become the most popular proposal twice
    // but we can enforce it doesent
    //or can we add it in the struct -- tbd

    function endorseGCAProposal(uint256 weekId) external {
        if (!IVetoCouncil(_vetoCouncil).isCouncilMember(msg.sender)) {
            _revert(IGovernance.CallerNotVetoCouncilMember.selector);
        }

        uint256 _currentWeek = currentWeek();
        if (weekId >= _currentWeek) {
            _revert(IGovernance.WeekNotFinalized.selector);
        }
        //Also make sure it's not already finalized
        uint256 _weekEndTime = _weekEndTime(weekId + _NUM_WEEKS_TO_VOTE_ON_MOST_POPULAR_PROPOSAL);
        if (block.timestamp > _weekEndTime) {
            _revert(IGovernance.RatifyOrRejectPeriodEnded.selector);
        }

        uint256 key = weekId / 256;
        uint256 shift = weekId % 256;
        uint256 existingEndorsementBitmap = _hasEndorsedProposalBitmap[msg.sender][key];
        uint256 bitVal = (1 << shift);
        if (existingEndorsementBitmap & bitVal != 0) {
            _revert(IGovernance.AlreadyEndorsedWeek.selector);
        }
        _hasEndorsedProposalBitmap[msg.sender][key] = existingEndorsementBitmap | bitVal;
        uint256 numEndorsements = numEndorsementsOnWeek[weekId];
        uint256 proposalId = mostPopularProposal[weekId];
        IGovernance.ProposalType proposalType = _proposals[proposalId].proposalType;
        if (proposalType != IGovernance.ProposalType.GCA_COUNCIL_ELECTION_OR_SLASH) {
            _revert(IGovernance.OnlyGCAElectionsCanBeEndorsed.selector);
        }

        numEndorsements += 1;
        if (numEndorsements > _MAX_ENDORSEMENTS_ON_GCA_PROPOSALS) {
            _revert(IGovernance.MaxGCAEndorsementsReached.selector);
        }

        //todo: add an invariant to test the bitsettings
        numEndorsementsOnWeek[weekId] = numEndorsements;
    }

    /**
     * @notice returns {true} if a gca has endorsed the proposal at {weekId}
     */
    function hasEndorsedProposal(address gca, uint256 weekId) external view returns (bool) {
        uint256 key = weekId / 256;
        uint256 shift = weekId % 256;
        return _hasEndorsedProposalBitmap[gca][key] & (1 << shift) != 0;
    }

    //************************************************************* */
    //************  EXTERNAL/STATE CHANGING FUNCS    ************* */
    //************************************************************* */
    /**
     * @notice entrypoint for veto council members to veto a most popular proposal
     * @param weekId - the id of the week to veto the most popular proposal in
     * @dev be sure not to confuse weekId with proposalId
     *             - the veto council members veto the most popular proposal at the  week
     */
    function vetoProposal(uint256 weekId) external {
        if (!IVetoCouncil(_vetoCouncil).isCouncilMember(msg.sender)) {
            _revert(IGovernance.CallerNotVetoCouncilMember.selector);
        }

        uint256 _currentWeek = currentWeek();
        if (weekId >= _currentWeek) {
            _revert(IGovernance.WeekNotFinalized.selector);
        }
        //Also make sure it's not already finalized
        uint256 _weekEndTime = _weekEndTime(weekId + _NUM_WEEKS_TO_VOTE_ON_MOST_POPULAR_PROPOSAL);
        if (block.timestamp > _weekEndTime) {
            _revert(IGovernance.RatifyOrRejectPeriodEnded.selector);
        }

        ProposalType proposalType = _proposals[mostPopularProposal[weekId]].proposalType;
        //Elections can't be vetoed
        if (proposalType == ProposalType.VETO_COUNCIL_ELECTION_OR_SLASH) {
            _revert(IGovernance.VetoCouncilElectionsCannotBeVetoed.selector);
        }

        if (proposalType == ProposalType.GCA_COUNCIL_ELECTION_OR_SLASH) {
            _revert(IGovernance.GCACouncilElectionsCannotBeVetoed.selector);
        }

        _setMostPopularProposalStatus(weekId, IGovernance.ProposalStatus.VETOED);
        emit IGovernance.ProposalVetoed(weekId, msg.sender, mostPopularProposal[weekId]);
    }

    /**
     * @notice Entry point for GCC contract to grant nominations to {to} when they retire GCC
     * @param to the address to grant nominations to
     * @param amount the amount of nominations to grant
     * @dev this function is only callable by the GCC contract
     * @dev nominations decay according to the half-life formula
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

    //TODO: make sure it executes proposals

    /**
     * @notice Allows a user to vote on a proposal
     * @param proposalId the id of the proposal
     * @param amount the amount of nominations to vote with
     */
    function useNominationsOnProposal(uint256 proposalId, uint256 amount) public {
        uint256 currentBalance = nominationsOf(msg.sender);
        uint256 nominationEndTimestamp = _proposals[proposalId].expirationTimestamp;

        /// @dev we don't need this check, but we add it for clarity on the revert reason
        if (nominationEndTimestamp == 0) {
            _revert(IGovernance.ProposalDoesNotExist.selector);
        }
        if (block.timestamp > nominationEndTimestamp) {
            _revert(IGovernance.ProposalExpired.selector);
        }

        _spendNominations(msg.sender, amount);
        uint184 newTotalVotes = uint184(_proposals[proposalId].votes + amount);
        _proposals[proposalId].votes = newTotalVotes;
        uint256 currentWeek = currentWeek();
        uint256 _mostPopularProposal = mostPopularProposal[currentWeek];
        if (proposalId != _mostPopularProposal) {
            if (newTotalVotes > _proposals[_mostPopularProposal].votes) {
                mostPopularProposal[currentWeek] = proposalId;
            }
        }

        emit IGovernance.NominationsUsedOnProposal(proposalId, msg.sender, amount);
    }

    /**
     * @notice entrypoint for long staked glow holders to vote on proposals
     * @param weekOfMostPopularProposal - the week that the proposal got selected as the most popular proposal for
     * @param trueForRatify  - if true the stakers are ratifying the proposal
     *                             - if false they are rejecting it
     * @param numVotes - the number of ratify/reject votes they want to apply on this proposal
     *                       - the total number of ratify/reject votes must always be lte than
     *                             - the total glw they have staked
     */
    function ratifyOrReject(uint256 weekOfMostPopularProposal, bool trueForRatify, uint256 numVotes) external {
        uint256 currentWeek = currentWeek();
        //Week needs to finalize.
        if (getMostPopularProposalStatus(weekOfMostPopularProposal) == IGovernance.ProposalStatus.VETOED) {
            _revert(IGovernance.ProposalAlreadyVetoed.selector);
        }
        if (weekOfMostPopularProposal >= currentWeek) {
            _revert(IGovernance.WeekNotFinalized.selector);
        }

        if (block.timestamp > _weekEndTime(weekOfMostPopularProposal + _NUM_WEEKS_TO_VOTE_ON_MOST_POPULAR_PROPOSAL)) {
            _revert(IGovernance.RatifyOrRejectPeriodEnded.selector);
        }
        //We also need to check to make sure that the proposal was created.
        uint256 userNumStakedGlow = IGlow(_glw).numStaked(msg.sender);
        uint256 _mostPopularProposal = mostPopularProposal[weekOfMostPopularProposal];
        if (_mostPopularProposal == 0) {
            _revert(IGovernance.MostPopularProposalNotSelected.selector);
        }
        uint256 amountVotesUsed = longStakerVotesForProposal[msg.sender][_mostPopularProposal];
        if (amountVotesUsed + numVotes > userNumStakedGlow) {
            _revert(IGovernance.InsufficientRatifyOrRejectVotes.selector);
        }
        if (trueForRatify) {
            _proposalLongStakerVotes[_mostPopularProposal].ratifyVotes += uint128(numVotes);
        } else {
            _proposalLongStakerVotes[_mostPopularProposal].rejectionVotes += uint128(numVotes);
        }
        longStakerVotesForProposal[msg.sender][_mostPopularProposal] = amountVotesUsed + numVotes;
    }

    /**
     * @notice A one time setter to set the contract addresses
     * @param gcc the GCC contract address
     * @param gca the GCA contract address
     * @param vetoCouncil the Veto Council contract address
     * @param grantsTreasury the Grants Treasury contract address
     * @param glw the GLW contract address
     * @dev also sets the genesis timestamp
     */
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
        _genesisTimestamp = IGlow(glw).GENESIS_TIMESTAMP();
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

        uint256 currentWeek = currentWeek();
        uint256 _mostPopularProposal = mostPopularProposal[currentWeek];
        if (nominationCost > _proposals[_mostPopularProposal].votes) {
            mostPopularProposal[currentWeek] = proposalId;
        }

        _proposalCount = proposalId + 1;

        emit IGovernance.GrantsProposalCreation(proposalId, msg.sender, grantsRecipient, amount, hash, nominationCost);
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

        uint256 currentWeek = currentWeek();
        uint256 _mostPopularProposal = mostPopularProposal[currentWeek];
        if (nominationCost > _proposals[_mostPopularProposal].votes) {
            mostPopularProposal[currentWeek] = proposalId;
        }

        _proposalCount = proposalId + 1;

        emit IGovernance.ChangeGCARequirementsProposalCreation(
            proposalId, msg.sender, newRequirementsHash, nominationCost
        );
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

        uint256 currentWeek = currentWeek();
        uint256 _mostPopularProposal = mostPopularProposal[currentWeek];
        if (nominationCost > _proposals[_mostPopularProposal].votes) {
            mostPopularProposal[currentWeek] = proposalId;
        }

        _proposalCount = proposalId + 1;

        emit IGovernance.RFCProposalCreation(proposalId, msg.sender, hash, nominationCost);
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
        bool incrementSlashNonce = agentsToSlash.length > 0;
        _spendNominations(msg.sender, nominationCost);
        _proposals[proposalId] = IGovernance.Proposal(
            IGovernance.ProposalType.GCA_COUNCIL_ELECTION_OR_SLASH,
            uint64(block.timestamp + _MAX_PROPOSAL_DURATION),
            uint184(nominationCost),
            abi.encode(hash, incrementSlashNonce)
        );

        uint256 currentWeek = currentWeek();
        uint256 _mostPopularProposal = mostPopularProposal[currentWeek];
        if (nominationCost > _proposals[_mostPopularProposal].votes) {
            mostPopularProposal[currentWeek] = proposalId;
        }

        _proposalCount = proposalId + 1;

        emit IGovernance.GCACouncilElectionOrSlashCreation(
            proposalId, msg.sender, agentsToSlash, newGCAs, block.timestamp, nominationCost
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
        uint256 currentWeek = currentWeek();
        uint256 _mostPopularProposal = mostPopularProposal[currentWeek];
        if (nominationCost > _proposals[_mostPopularProposal].votes) {
            mostPopularProposal[currentWeek] = proposalId;
        }

        _proposalCount = proposalId + 1;

        emit IGovernance.VetoCouncilElectionOrSlash(
            proposalId, msg.sender, oldAgent, newAgent, slashOldAgent, nominationCost
        );
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
        uint256 currentWeek = currentWeek();
        uint256 _mostPopularProposal = mostPopularProposal[currentWeek];
        if (nominationCost > _proposals[_mostPopularProposal].votes) {
            mostPopularProposal[currentWeek] = proposalId;
        }
        _proposalCount = proposalId + 1;

        emit IGovernance.ChangeReserveCurrenciesProposal(
            proposalId, msg.sender, currencyToRemove, newReserveCurrency, nominationCost
        );

        _spendNominations(msg.sender, nominationCost);
    }

    /**
     * @notice Updates the last expired proposal id
     *         - could be called by a good actor to update the last expired proposal id
     *         - so that _numActiveProposalsAndLastExpiredProposalId() is more efficient
     */
    function updateLastExpiredProposalId() public {
        (, uint256 _lastExpiredProposalId) = _numActiveProposalsAndLastExpiredProposalId();
        console.log("lastExpiredProposalId: %s", _lastExpiredProposalId);
        lastExpiredProposalId = _lastExpiredProposalId;
    }

    //************************************************************* */
    //***************  PUBLIC/EXTERNAL VIEW FUNCTIONS    **************** */
    //************************************************************* */

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
     * @notice Gets the current week (since genesis)
     * @return currentWeek - the current week (since genesis)
     */
    function currentWeek() public view returns (uint256) {
        return (block.timestamp - _genesisTimestamp) / _ONE_WEEK;
    }

    /**
     * @notice Gets the status of the most popular proposal at a given week
     * @param weekId the week id
     * @return status the status of the proposal
     */
    function getMostPopularProposalStatus(uint256 weekId) public view returns (IGovernance.ProposalStatus) {
        uint256 key = weekId / 32;
        uint256 shift = (weekId % 32) * 8;
        uint256 mask = uint256(0xff) << shift;
        uint256 value = (_packedMostPopularProposalStatusByWeek[key] & mask) >> shift;
        return IGovernance.ProposalStatus(value);
    }

    /// @inheritdoc IGovernance
    function getProposalWithStatus(uint256 proposalId)
        public
        view
        returns (Proposal memory proposal, IGovernance.ProposalStatus)
    {}

    /**
     * @notice Gets the total number of proposals created
     * @return proposalCount - the total number of proposals created
     * @dev we have to subtract 1 because we start at 1
     */
    function proposalCount() public view returns (uint256) {
        return _proposalCount - 1;
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
     * @notice returns the number of ratify and reject votes on a given proposal
     * @param proposalId - the id of the proposal to query for
     * @dev the proposalId is different than the weekId
     * @return proposalLongStakerVotes - the {ProposalLongStakerVotes struct} for a proposal
     */
    function proposalLongStakerVotes(uint256 proposalId) external view returns (ProposalLongStakerVotes memory) {
        return _proposalLongStakerVotes[proposalId];
    }

    //************************************************************* */
    //*****************  INTERNAL/PRIVATE FUNCS   ****************** */
    //************************************************************* */

    /**
     * @notice Gets the nomination cost for proposal creation based on {numActiveProposals}
     * @param numActiveProposals the number of active proposals
     * @return res the nomination cost for proposal creation
     * @dev calculates cost as 1 * 1.1^numActiveProposals
     * @dev we only use 4 decimals of precision
     */
    function _getNominationCostForProposalCreation(uint256 numActiveProposals) internal pure returns (uint256) {
        uint256 res = _ONE_64x64.mul(ABDKMath64x64.pow(_ONE_POINT_ONE_128, numActiveProposals)).mulu(1e4);
        // uint256 resInt = res.toUInt();
        return res * 1e14;
    }

    /**
     * @dev sets the proposal status for the most popular proposal at a given week
     * @param weekId the week id
     * @param status the status of the proposal
     *  TODO: check the bitpos stuff
     */
    function _setMostPopularProposalStatus(uint256 weekId, IGovernance.ProposalStatus status) internal {
        //Each uint256 is 32 bytes, and can hold 32 uint8 statuses
        uint256 key = weekId / 32;
        //Each enum takes up 8 bits since it's casted to a uint8
        uint256 shift = (weekId % 32) * 8;
        //8 bits << shift
        uint256 mask = uint256(0xff) << shift;
        //the status bitshifted
        uint256 value = uint256(status) << shift;
        _packedMostPopularProposalStatusByWeek[key] = (_packedMostPopularProposalStatusByWeek[key] & ~mask) | value;
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
     * @notice Gets the number of active proposals and the last expired proposal id
     * @return numActiveProposals the number of active proposals
     * @return _lastExpiredProposalId the last expired proposal id
     */
    function _numActiveProposalsAndLastExpiredProposalId()
        internal
        view
        returns (uint256 numActiveProposals, uint256 _lastExpiredProposalId)
    {
        _lastExpiredProposalId = lastExpiredProposalId;
        uint256 __proposalCount = _proposalCount;
        _lastExpiredProposalId = _lastExpiredProposalId == 0 ? 1 : _lastExpiredProposalId;
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
     * @notice finds the time at which the week ends
     * @dev for example, {weekNumber = 1} would give the timestamp at which week 1 would be over
     * @param weekNumber - the week number to find the end timestamp for
     * @return endTimestamp - the end timestamp of the week number
     */
    function _weekEndTime(uint256 weekNumber) internal view returns (uint256) {
        return _genesisTimestamp + ((weekNumber + 1) * _ONE_WEEK);
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
}

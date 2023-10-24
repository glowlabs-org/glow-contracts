// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IGovernance} from "@/interfaces/IGovernance.sol";
import {HalfLife} from "@/libraries/HalfLife.sol";
import {ABDKMath64x64} from "@/libraries/ABDKMath64x64.sol";
import {IGlow} from "@/interfaces/IGlow.sol";
import {IVetoCouncil} from "@/interfaces/IVetoCouncil.sol";
import {IGCA} from "@/interfaces/IGCA.sol";
import {IGrantsTreasury} from "@/interfaces/IGrantsTreasury.sol";
import {IMinerPool} from "@/interfaces/IMinerPool.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "forge-std/console.sol";
/**
 * @title Governance
 * @author DavidVorick
 * @author 0xSimon , 0xSimbo
 * @notice This contract is used to manage the Glow governance
 *               - The governance contract is used to manage the Glow protocol
 *               - Proposals are denoted by their types in {ProposalType} enum
 *               - Proposals can be created by anyone and cost nominations
 *               - It should cost (1.1)^n nominations where n = # of active proposals
 *                 - Proposals can be ratified or rejected by long stakers
 *                 - Veto council members can veto proposals (besides elections)
 *                 - Proposals can be executed if they are ratified
 *                     -   RFC Proposals and Grants Proposals don't need to be ratified to be executed
 *                 - Once created, proposals are active for 16 weeks
 *                 - Each week, a most popular proposal is selected
 *                 - Governance also handles rewarding and depreciating nominations
 *                 - Nominations have a half-life of 52 weeks and are earned by retiring GCC
 *                 - Nominations are used to create and vote on proposals
 */

contract Governance is IGovernance, EIP712 {
    using ABDKMath64x64 for int128;
    /**
     * @notice  Spend nominations EIP712 Typehash
     */

    bytes32 public constant SPEND_NOMINATIONS_ON_PROPOSAL_TYPEHASH = keccak256(
        "SpendNominationsOnProposal(uint8 proposalType,uint256 nominationsToSpend,uint256 nonce,uint256 deadline,bytes data)"
    );

    /**
     * @notice The next nonce of a user to use in a spend nominations on proposal transaction
     * @dev This is used to prevent replay attacks
     */
    mapping(address => uint256) public spendNominationsOnProposalNonce;
    /**
     * @dev one in 64x64 fixed point
     */
    int128 private constant _ONE_64x64 = (1 << 64);

    /**
     * @dev 1.1 in 128x128 fixed point
     * @dev used in the nomination cost calculation
     */
    int128 private constant _ONE_POINT_ONE_128 = (1 << 64) + 0x1999999999999a00;

    /**
     * @dev The duration of a bucket: 1 week
     */
    uint256 private constant _ONE_WEEK = uint256(7 days);

    /**
     * @dev The maximum duration of a proposal: 16 weeks
     */
    uint256 private constant _MAX_PROPOSAL_DURATION = 9676800;

    /**
     *   @dev the maximum number of weeks a proposal can be ratified or rejected
     *      - from the time it it has been finalized (i.e. the week has passed)
     *  For example: If proposal 1 is the most popular proposal for week 2, then it can be ratified or rejected until the end of week 6
     */
    uint256 private constant _NUM_WEEKS_TO_VOTE_ON_MOST_POPULAR_PROPOSAL = 4;

    /**
     * @dev The percentage of ratify to reject votes that is required to execute a proposal
     * @dev exceptions are noted in the implemntation of executeProposalAtWeek
     */
    uint256 private constant _DEFAULT_PERCENTAGE_TO_EXECUTE_PROPOSAL = 60; //60%

    /**
     * @dev there can be a maximum of 5 endorsements on a GCA election proposal
     */
    uint256 private constant _MAX_ENDORSEMENTS_ON_GCA_PROPOSALS = 5;

    /**
     * @dev the maximum number of GCA council members that can be concurrently active
     */
    uint256 private constant _MAX_GCAS_AT_ONE_POINT_IN_TIME = 5;

    /**
     * @dev the maximum number of slashes that can be executed in a single GCA election
     * @dev this is to prevent DoS attacks that could cause the execution to run out of gas
     */
    uint256 private constant _MAX_SLASHES_IN_ONE_GCA_ELECTION = 10;

    /**
     * @dev the maximum number of concurrently actibe GCA council members
     */
    uint256 private constant _MAX_GCAS = 5;

    /**
     * @dev each endorsement decreases the required percentage to execute a GCA election proposal by 5%
     */
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

    /// @dev The most popular proposal status at a proposal id
    /// @dev since there are only 8 proposal statuses, we can use a uint256 to store the status
    /// @dev each uint256 is 32 bytes, so we can store 32 statuses in a single uint256
    mapping(uint256 => uint256) private _packedProposalStatus;

    /**
     * @notice the number of endorsements on the most popular proposal at a given week
     * @dev only GCA elections can be endorsed
     * @dev only veto council members can endorse a proposal
     * @dev an endorsement represents a 5% drop to the default percentage to execute a proposal
     * @dev the default percentage to execute a proposal is 60%
     * @dev the weight of an endorsement is 5%
     * @dev the minimum percentage to execute GCA election proposal is 35%
     *             -  that means there can be a maximumn of 5 endorsements on a GCA election proposal
     */
    mapping(uint256 => uint256) public numEndorsementsOnWeek;

    /**
     * @dev veto council agent -> key -> bitmap
     * @dev one mapping slot holds 256 bits
     *             - each bit represents a week
     *             - if the bit is set, then the veto council agent has vetoed the most popular proposal for that week
     */
    mapping(address => mapping(uint256 => uint256)) private _hasEndorsedProposalBitmap;
    //************************************************************* */
    //*****************  CONSTRUCTOR   ************** */
    //************************************************************* */

    constructor() payable EIP712("Glow Governance", "1") {}

    //************************************************************* */
    //************  EXTERNAL/STATE CHANGING FUNCS    ************* */
    //************************************************************* */

    /**
     * @inheritdoc IGovernance
     * @dev proposal execution should be sub-100k gas
     */
    function executeProposalAtWeek(uint256 week) public {
        uint256 _nextWeekToExecute = lastExecutedWeek;
        unchecked {
            //We actually want this to overflow
            ++_nextWeekToExecute;
        }

        //We need all proposals to be executed synchronously
        if (_nextWeekToExecute != week) {
            _revert(IGovernance.ProposalsMustBeExecutedSynchonously.selector);
        }

        uint256 proposalId = mostPopularProposal[week];

        if (!isProposalEligibleForExecution(proposalId)) {
            lastExecutedWeek = week;
            return;
        }

        IGovernance.Proposal memory proposal = _proposals[proposalId];
        IGovernance.ProposalType proposalType = proposal.proposalType;
        ProposalLongStakerVotes memory longStakerVotes = _proposalLongStakerVotes[proposalId];

        //For all other proposals, we need to make sure that the ratify/reject period has ended
        if (block.timestamp < _weekEndTime(week + _NUM_WEEKS_TO_VOTE_ON_MOST_POPULAR_PROPOSAL)) {
            _revert(IGovernance.RatifyOrRejectPeriodNotEnded.selector);
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
                        && proposalType != IGovernance.ProposalType.GRANTS_PROPOSAL
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

    /**
     *     Note: Sync proposals should be max 100k gas per proposal
     *     to make sure that users aren't too heavily penalized for
     *     syncing proposals
     */

    /**
     * @inheritdoc IGovernance
     */
    function syncProposals() public {
        uint256 currentWeek = currentWeek();
        if (currentWeek == 0) return;
        uint256 _nextWeekToExecute = lastExecutedWeek;
        unchecked {
            //We actually want this to overflow since we start at type(uint256).max
            ++_nextWeekToExecute;
            //increment current week to not have to <= check, we can just < check in the for loop
            ++currentWeek;
            //we increment up the the current week to make sure that _weekEndTime(_nextWeekToExecute)
            //eventually becomes greater than block.timestamp so we can stop the loop and update state
        }
        for (_nextWeekToExecute; _nextWeekToExecute < currentWeek; ++_nextWeekToExecute) {
            //If the proposal is vetoed, we can skip the execution
            //We still need to update the lastExecutedWeek so the next proposal can be executed
            uint256 proposalId = mostPopularProposal[_nextWeekToExecute];
            if (!isProposalEligibleForExecution(proposalId)) {
                continue;
            }

            IGovernance.Proposal memory proposal = _proposals[proposalId];
            IGovernance.ProposalType proposalType = proposal.proposalType;
            ProposalLongStakerVotes memory longStakerVotes = _proposalLongStakerVotes[proposalId];

            //For all other proposals, we need to make sure that the ratify/reject period has ended

            if (block.timestamp < _weekEndTime(_nextWeekToExecute + _NUM_WEEKS_TO_VOTE_ON_MOST_POPULAR_PROPOSAL)) {
                lastExecutedWeek = _nextWeekToExecute == 0 ? type(uint256).max : _nextWeekToExecute - 1;
                return;
            }

            //Start C2:
            //C2 checks to see if there are enough ratify votes to execute the proposal

            //If the proposal is a gca election, we can check endorsements to
            //dynamically determine the required percentage to execute the proposal
            //The default percentage to execute a  proposal is 60%
            //The minimum percentage to execute a gca proposal is 35%
            //RFC and Grants Treasury proposals don't need to be ratified to pass
            if (proposalType == IGovernance.ProposalType.GCA_COUNCIL_ELECTION_OR_SLASH) {
                uint256 numEndorsements = numEndorsementsOnWeek[_nextWeekToExecute];
                uint256 requiredWeight =
                    _DEFAULT_PERCENTAGE_TO_EXECUTE_PROPOSAL - (numEndorsements * _ENDORSEMENT_WEIGHT);
                uint256 totalVotes = longStakerVotes.ratifyVotes + longStakerVotes.rejectionVotes;
                //If no one votes, we don't execute the proposal
                //This also prevents division by zero error
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
                            && proposalType != IGovernance.ProposalType.GRANTS_PROPOSAL
                    )
                ) {
                    uint256 totalVotes = longStakerVotes.ratifyVotes + longStakerVotes.rejectionVotes;
                    //If no one votes, we don't execute the proposal
                    //Prevent division by zero error
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

    /**
     * @inheritdoc IGovernance
     */
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

        numEndorsementsOnWeek[weekId] = numEndorsements;
    }

    /**
     * @notice Allows a user to increase their nonce
     * - This is in case they set a deadline that is too far in the future
     * - The user can increase their nonce to invalidate the previous signature
     */
    function selfIncrementNonce() external {
        ++spendNominationsOnProposalNonce[msg.sender];
    }

    /**
     * @notice entrypoint for veto council members to veto a most popular proposal
     * @param weekId - the id of the week to veto the most popular proposal in
     * @param proposalId - the id of the proposal to veto
     */
    function vetoProposal(uint256 weekId, uint256 proposalId) external {
        if (!IVetoCouncil(_vetoCouncil).isCouncilMember(msg.sender)) {
            _revert(IGovernance.CallerNotVetoCouncilMember.selector);
        }

        if (mostPopularProposal[weekId] != proposalId) {
            _revert(IGovernance.ProposalIdDoesNotMatchMostPopularProposal.selector);
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

        ProposalType proposalType = _proposals[proposalId].proposalType;
        //Elections can't be vetoed
        if (proposalType == ProposalType.VETO_COUNCIL_ELECTION_OR_SLASH) {
            _revert(IGovernance.VetoCouncilElectionsCannotBeVetoed.selector);
        }

        if (proposalType == ProposalType.GCA_COUNCIL_ELECTION_OR_SLASH) {
            _revert(IGovernance.GCACouncilElectionsCannotBeVetoed.selector);
        }

        _setProposalStatus(proposalId, IGovernance.ProposalStatus.VETOED);
        emit IGovernance.ProposalVetoed(weekId, msg.sender, proposalId);
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

    /**
     * @notice Allows a user to vote on a proposal
     * @param proposalId the id of the proposal
     * @param amount the amount of nominations to vote with
     * @dev also syncs proposals if need be.
     */
    function useNominationsOnProposal(uint256 proposalId, uint256 amount) public {
        syncProposals();
        _revertIfProposalExecuted(proposalId);
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
     * @notice sets the proposal as the most popular proposal for the current week
     * @dev
     * @param proposalId The ID of the proposal to set as the most popular.
     */
    /**
     * @notice sets the proposal as the most popular proposal for the current week
     * @dev checks if the proposal is the most popular proposal for the current week and sets it if it is
     * @dev throws an error if the proposal is not the most popular proposal or if the proposal has expired
     * @param proposalId The ID of the proposal to set as the most popular.
     */
    function setMostPopularProposalForCurrentWeek(uint256 proposalId) external {
        syncProposals();
        _revertIfProposalExecuted(proposalId);
        // get the current week
        uint256 currentWeek = currentWeek();
        // get the most popular proposal for the current week
        uint256 _mostPopularProposal = mostPopularProposal[currentWeek];
        // get the expiration timestamp of the proposal
        uint256 expirationTimestamp = _proposals[proposalId].expirationTimestamp;
        // get the number of votes on the proposal
        uint256 numVotesOnProposal = _proposals[proposalId].votes;
        // check if the proposal has expired
        if (expirationTimestamp < block.timestamp) {
            _revert(IGovernance.ProposalExpired.selector);
        }
        // check if the proposal is already the most popular proposal
        if (proposalId != _mostPopularProposal) {
            // check if the number of votes on the proposal is greater than the number of votes on the current most popular proposal
            if (numVotesOnProposal > _proposals[_mostPopularProposal].votes) {
                // set the proposal as the most popular proposal for the current week
                mostPopularProposal[currentWeek] = proposalId;
            } else {
                // throw an error if the proposal is not the most popular proposal
                _revert(IGovernance.ProposalNotMostPopular.selector);
            }
        }
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
        uint256 _mostPopularProposal = mostPopularProposal[weekOfMostPopularProposal];

        IGovernance.ProposalStatus status = getProposalStatus(_mostPopularProposal);
        if (status == IGovernance.ProposalStatus.VETOED) {
            _revert(IGovernance.ProposalAlreadyVetoed.selector);
        }
        if (
            status == IGovernance.ProposalStatus.EXECUTED_SUCCESSFULLY
                || status == IGovernance.ProposalStatus.EXECUTED_WITH_ERROR
        ) {
            _revert(IGovernance.ProposalAlreadyExecuted.selector);
        }

        if (weekOfMostPopularProposal >= currentWeek) {
            _revert(IGovernance.WeekNotFinalized.selector);
        }

        if (block.timestamp > _weekEndTime(weekOfMostPopularProposal + _NUM_WEEKS_TO_VOTE_ON_MOST_POPULAR_PROPOSAL)) {
            _revert(IGovernance.RatifyOrRejectPeriodEnded.selector);
        }
        //We also need to check to make sure that the proposal was created.
        uint256 userNumStakedGlow = IGlow(_glw).numStaked(msg.sender);
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
        uint256 nominationCost = costForNewProposalAndUpdateLastExpiredProposalId();
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
        uint256 nominationCost = costForNewProposalAndUpdateLastExpiredProposalId();
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
        uint256 nominationCost = costForNewProposalAndUpdateLastExpiredProposalId();
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
        if (newGCAs.length > _MAX_GCAS_AT_ONE_POINT_IN_TIME) {
            _revert(IGovernance.MaximumNumberOfGCAS.selector);
        }
        if (agentsToSlash.length > _MAX_SLASHES_IN_ONE_GCA_ELECTION) {
            _revert(IGovernance.MaxSlashesInGCAElection.selector);
        }
        //[agentsToSlash,newGCAs,proposalCreationTimestamp]
        bytes32 hash = keccak256(abi.encode(agentsToSlash, newGCAs, block.timestamp));
        uint256 proposalId = _proposalCount;
        uint256 nominationCost = costForNewProposalAndUpdateLastExpiredProposalId();
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
        if (oldAgent == newAgent) {
            _revert(IGovernance.VetoCouncilProposalCreationOldAgentCannotEqualNewAgent.selector);
        }
        uint256 proposalId = _proposalCount;
        uint256 nominationCost = costForNewProposalAndUpdateLastExpiredProposalId();
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
        uint256 nominationCost = costForNewProposalAndUpdateLastExpiredProposalId();
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
     * @notice Creates a proposal to send a grant to a recipient
     */
    function createGrantsProposalSigs(
        address grantsRecipient,
        uint256 amount,
        bytes32 hash,
        uint256[] memory deadlines,
        uint256[] memory nominationsToSpend,
        address[] memory signers,
        bytes[] memory sigs
    ) external {
        bytes memory data = abi.encode(grantsRecipient, amount, hash);

        (uint256 proposalId, uint256 nominationsSpent) = checkBulkSignaturesAndCheckSufficientNominations(
            deadlines, nominationsToSpend, signers, sigs, data, IGovernance.ProposalType.GRANTS_PROPOSAL
        );
        emit IGovernance.GrantsProposalCreation(proposalId, msg.sender, grantsRecipient, amount, hash, nominationsSpent);
    }

    /**
     * @notice Creates a proposal to change the GCA requirements
     */
    function createChangeGCARequirementsProposalSigs(
        bytes32 newRequirementsHash,
        uint256[] memory deadlines,
        uint256[] memory nominationsToSpend,
        address[] memory signers,
        bytes[] memory sigs
    ) external {
        bytes memory data = abi.encode(newRequirementsHash);
        (uint256 proposalId, uint256 nominationsSpent) = checkBulkSignaturesAndCheckSufficientNominations(
            deadlines, nominationsToSpend, signers, sigs, data, IGovernance.ProposalType.CHANGE_GCA_REQUIREMENTS
        );

        emit IGovernance.ChangeGCARequirementsProposalCreation(
            proposalId, msg.sender, newRequirementsHash, nominationsSpent
        );
    }

    /**
     * @notice Creates a proposal to create an RFC
     *     - the pre-image should be made public off-chain
     *     - if accepted, veto council members must read the RFC (up to 10k Words) and provide a written statement on their thoughts
     */
    function createRFCProposalSigs(
        bytes32 hash,
        uint256[] memory deadlines,
        uint256[] memory nominationsToSpend,
        address[] memory signers,
        bytes[] memory sigs
    ) external {
        bytes memory data = abi.encode(hash);
        (uint256 proposalId, uint256 nominationsSpent) = checkBulkSignaturesAndCheckSufficientNominations(
            deadlines, nominationsToSpend, signers, sigs, data, IGovernance.ProposalType.REQUEST_FOR_COMMENT
        );
        emit IGovernance.RFCProposalCreation(proposalId, msg.sender, hash, nominationsSpent);
    }

    /**
     * @notice Creates a proposal to add, replace, or slash GCA council members
     * @param agentsToSlash an array of all gca's that are to be slashed
     *         - could be empty
     *         - could be a subset of the current GCAs
     *         - could be any address [in order to account for previous GCA's]
     * @param newGCAs the new GCAs
     *     -   can be empty if all GCA's are bad actors
     */
    function createGCACouncilElectionOrSlashProposalSigs(
        address[] memory agentsToSlash,
        address[] memory newGCAs,
        uint256[] memory deadlines,
        uint256[] memory nominationsToSpend,
        address[] memory signers,
        bytes[] memory sigs
    ) external {
        {
            if (newGCAs.length > _MAX_GCAS_AT_ONE_POINT_IN_TIME) {
                _revert(IGovernance.MaximumNumberOfGCAS.selector);
            }
            if (agentsToSlash.length > _MAX_SLASHES_IN_ONE_GCA_ELECTION) {
                _revert(IGovernance.MaxSlashesInGCAElection.selector);
            }
        }

        bytes32 hash = keccak256(abi.encode(agentsToSlash, newGCAs, block.timestamp));
        bool incrementSlashNonce = agentsToSlash.length > 0;
        bytes memory data = abi.encode(hash, incrementSlashNonce);

        (uint256 proposalId, uint256 nominationsSpent) = checkBulkSignaturesAndCheckSufficientNominations(
            deadlines, nominationsToSpend, signers, sigs, data, IGovernance.ProposalType.GCA_COUNCIL_ELECTION_OR_SLASH
        );
        emit IGovernance.GCACouncilElectionOrSlashCreation(
            proposalId, msg.sender, agentsToSlash, newGCAs, block.timestamp, nominationsSpent
        );
    }

    /**
     * @notice Creates a proposal to add, replace, or slash Veto a single veto council member
     * @param oldAgent the old agent to be replaced
     *         -   If the agent is address(0), it means we are simply adding a new agent
     * @param newAgent the new agent to replace the old agent
     *         -   If the agent is address(0), it means we are simply removing an agent
     * @param slashOldAgent whether or not to slash the old agent
     */
    function createVetoCouncilElectionOrSlashSigs(
        address oldAgent,
        address newAgent,
        bool slashOldAgent,
        uint256[] memory deadlines,
        uint256[] memory nominationsToSpend,
        address[] memory signers,
        bytes[] memory sigs
    ) external {
        if (oldAgent == newAgent) {
            _revert(IGovernance.VetoCouncilProposalCreationOldAgentCannotEqualNewAgent.selector);
        }

        bytes memory data = abi.encode(oldAgent, newAgent, slashOldAgent, block.timestamp);
        (uint256 proposalId, uint256 nominationsSpent) = checkBulkSignaturesAndCheckSufficientNominations(
            deadlines, nominationsToSpend, signers, sigs, data, IGovernance.ProposalType.VETO_COUNCIL_ELECTION_OR_SLASH
        );

        emit IGovernance.VetoCouncilElectionOrSlash(
            proposalId, msg.sender, oldAgent, newAgent, slashOldAgent, nominationsSpent
        );
    }

    /**
     * @notice Creates a proposal to change a reserve currency
     * @param currencyToRemove the currency to remove
     *     -   If the currency is address(0), it means we are simply adding a new reserve currency
     * @param newReserveCurrency the new reserve currency
     *     -   If the currency is address(0), it means we are simply removing a reserve currency
     */
    function createChangeReserveCurrencyProposalSigs(
        address currencyToRemove,
        address newReserveCurrency,
        uint256[] memory deadlines,
        uint256[] memory nominationsToSpend,
        address[] memory signers,
        bytes[] memory sigs
    ) external {
        bytes memory data = abi.encode(currencyToRemove, newReserveCurrency);
        (uint256 proposalId, uint256 nominationsSpent) = checkBulkSignaturesAndCheckSufficientNominations(
            deadlines, nominationsToSpend, signers, sigs, data, IGovernance.ProposalType.CHANGE_RESERVE_CURRENCIES
        );
        emit IGovernance.ChangeReserveCurrenciesProposal(
            proposalId, msg.sender, currencyToRemove, newReserveCurrency, nominationsSpent
        );
    }

    /**
     * @notice Updates the last expired proposal id
     *         - could be called by a good actor to update the last expired proposal id
     *         - so that _numActiveProposalsAndLastExpiredProposalId() is more efficient
     */
    function updateLastExpiredProposalId() public {
        (, uint256 _lastExpiredProposalId,) = _numActiveProposalsAndLastExpiredProposalId();
        lastExpiredProposalId = _lastExpiredProposalId;
    }

    //************************************************************* */
    //***************  PUBLIC/EXTERNAL VIEW FUNCTIONS    **************** */
    //************************************************************* */
    /**
     * @notice returns {true} if a gca has endorsed the proposal at {weekId}
     */
    function hasEndorsedProposal(address gca, uint256 weekId) external view returns (bool) {
        uint256 key = weekId / 256;
        uint256 shift = weekId % 256;
        return _hasEndorsedProposalBitmap[gca][key] & (1 << shift) != 0;
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

    /**
     * @notice Gets the cost for a new proposal
     * @return cost the cost for a new proposal
     * @dev calculates cost as 1 * 1.1^numActiveProposals
     */
    function costForNewProposal() public view returns (uint256) {
        uint256 numActiveProposals;
        (numActiveProposals,,) = _numActiveProposalsAndLastExpiredProposalId();
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
     * @param proposalId the id of the proposal
     * @return status the status of the proposal
     */
    function getProposalStatus(uint256 proposalId) public view returns (IGovernance.ProposalStatus) {
        uint256 key = proposalId / 32;
        uint256 shift = (proposalId % 32) * 8;
        uint256 mask = uint256(0xff) << shift;
        uint256 value = (_packedProposalStatus[key] & mask) >> shift;
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
     * @dev internal function to execute a proposal
     * @param proposalId the id of the proposal
     * @param proposalType the type of the proposal
     * @param data the data of the proposal
     */
    function handleProposalExecution(uint256 proposalId, IGovernance.ProposalType proposalType, bytes memory data)
        internal
    {
        bool success;
        if (proposalType == IGovernance.ProposalType.VETO_COUNCIL_ELECTION_OR_SLASH) {
            (address oldAgent, address newAgent, bool slashOldAgent) = abi.decode(data, (address, address, bool));
            success = IVetoCouncil(_vetoCouncil).addAndRemoveCouncilMember(oldAgent, newAgent, slashOldAgent);
        }

        if (proposalType == IGovernance.ProposalType.GCA_COUNCIL_ELECTION_OR_SLASH) {
            (bytes32 hash, bool incrementSlashNonce) = abi.decode(data, (bytes32, bool));
            //push hash should never revert;
            IGCA(_gca).pushHash(hash, incrementSlashNonce);
            success = true;
        }

        if (proposalType == IGovernance.ProposalType.CHANGE_RESERVE_CURRENCIES) {
            (address oldReserveCurrency, address newReserveCurrency) = abi.decode(data, (address, address));
            success = IMinerPool(_gca).editReserveCurrencies(oldReserveCurrency, newReserveCurrency);
        }

        if (proposalType == IGovernance.ProposalType.GRANTS_PROPOSAL) {
            (address grantsRecipient, uint256 amount,) = abi.decode(data, (address, uint256, bytes32));
            success = IGrantsTreasury(_grantsTreasury).allocateGrantFunds(grantsRecipient, amount);
        }

        if (proposalType == IGovernance.ProposalType.CHANGE_GCA_REQUIREMENTS) {
            (bytes32 newRequirementsHash) = abi.decode(data, (bytes32));
            //setRequirementsHash should never revert
            IGCA(_gca).setRequirementsHash(newRequirementsHash);
            success = true;
        }

        if (proposalType == IGovernance.ProposalType.REQUEST_FOR_COMMENT) {
            bytes32 rfcHash = abi.decode(data, (bytes32));
            //Emitting the event should never revert
            emit IGovernance.RFCProposalExecuted(proposalId, rfcHash);
            success = true;
        }

        if (success) {
            _setProposalStatus(proposalId, IGovernance.ProposalStatus.EXECUTED_SUCCESSFULLY);
        } else {
            _setProposalStatus(proposalId, IGovernance.ProposalStatus.EXECUTED_WITH_ERROR);
        }
    }

    /**
     * @dev internal function to get the cost for a new proposal and also update the
     *         -  last expired proposal id if need be
     */
    function costForNewProposalAndUpdateLastExpiredProposalId() internal returns (uint256) {
        (uint256 numActiveProposals, uint256 _lastExpiredProposalId) =
            _numActiveProposalsAndLastExpiredProposalIdAndUpdateState();
        return _getNominationCostForProposalCreation(numActiveProposals);
    }

    /**
     * @dev helper func to spend nominations from an account
     *         -   should never be public
     * @param account the account to spend nominations from
     * @param amount the amount of nominations to spend
     */
    function _spendNominations(address account, uint256 amount) internal {
        uint256 currentBalance = nominationsOf(account);
        if (currentBalance < amount) {
            _revert(IGovernance.InsufficientNominations.selector);
        }
        _nominations[account] = Nominations(uint192(currentBalance - amount), uint64(block.timestamp));
    }

    /**
     * @dev sets the proposal status for the most popular proposal at a given week
     * @param proposalId the id of the proposal
     * @param status the status of the proposal
     */
    function _setProposalStatus(uint256 proposalId, IGovernance.ProposalStatus status) internal {
        //Each uint256 is 32 bytes, and can hold 32 uint8 statuses
        uint256 key = proposalId / 32;
        //Each enum takes up 8 bits since it's casted to a uint8
        uint256 shift = (proposalId % 32) * 8;
        //8 bits << shift
        uint256 mask = uint256(0xff) << shift;
        //the status bitshifted
        uint256 value = uint256(status) << shift;
        _packedProposalStatus[key] = (_packedProposalStatus[key] & ~mask) | value;
    }

    /**
     * @notice Gets the number of active proposals and the last expired proposal id
     * @dev also updates state
     * @return numActiveProposals the number of active proposals
     * @return _lastExpiredProposalId the last expired proposal id
     */

    function _numActiveProposalsAndLastExpiredProposalIdAndUpdateState()
        internal
        returns (uint256 numActiveProposals, uint256 _lastExpiredProposalId)
    {
        bool updateState;
        (numActiveProposals, _lastExpiredProposalId, updateState) = _numActiveProposalsAndLastExpiredProposalId();
        if (updateState) {
            lastExpiredProposalId = _lastExpiredProposalId;
        }
    }

    /**
     * @dev helper function that
     *             1. Checks the signatures of the signers
     *             2. Checks that the total nominations to spend is greater than the nomination cost
     *             3. Checks that the deadline has not passed
     *             4. Spends the nominations
     *             5. Updates the most popular proposal
     *             6. Creates the proposal
     * @param deadlines the deadlines of the signatures
     * @param nominationsToSpend the nominations to spend of the signatures
     * @param signers the signers of the signatures
     * @param sigs the sigs of the signatures
     * @param data the data of the proposal
     * @param proposalType the type of the proposal
     * @return proposalId the id of the proposal that was created
     * @return totalNominationsToSpend the total nominations that were spent on the proposal
     */
    function checkBulkSignaturesAndCheckSufficientNominations(
        uint256[] memory deadlines,
        uint256[] memory nominationsToSpend,
        address[] memory signers,
        bytes[] memory sigs,
        bytes memory data,
        IGovernance.ProposalType proposalType
    ) internal returns (uint256, uint256) {
        uint256 proposalId = _proposalCount;
        uint256 totalNominationsToSpend;
        for (uint256 i; i < signers.length;) {
            _checkSpendNominationsOnProposalDigest(
                proposalType, nominationsToSpend[i], deadlines[i], signers[i], sigs[i], data
            );
            _spendNominations(signers[i], nominationsToSpend[i]);
            totalNominationsToSpend += nominationsToSpend[i];
            unchecked {
                ++i;
            }
        }
        uint256 nominationCost = costForNewProposalAndUpdateLastExpiredProposalId();

        if (totalNominationsToSpend < nominationCost) {
            _revert(IGovernance.NominationCostGreaterThanAllowance.selector);
        }

        uint256 currentWeek = currentWeek();
        uint256 _mostPopularProposal = mostPopularProposal[currentWeek];
        if (nominationCost > _proposals[_mostPopularProposal].votes) {
            mostPopularProposal[currentWeek] = proposalId;
        }

        _proposals[proposalId] = IGovernance.Proposal(
            proposalType, uint64(block.timestamp + _MAX_PROPOSAL_DURATION), uint184(nominationCost), data
        );

        ++proposalId;
        _proposalCount = proposalId;

        return (proposalId, totalNominationsToSpend);
    }

    /**
     * @dev helper function that checks the signature of a signer
     * @param proposalType the type of the proposal
     * @param nominationsToSpend the nominations to spend of the signature
     * @param deadline the deadline of the signature
     * @param signer the signer of the signature
     * @param sig the sig of the signature
     * @param data the data of the proposal
     */
    function _checkSpendNominationsOnProposalDigest(
        ProposalType proposalType,
        uint256 nominationsToSpend,
        uint256 deadline,
        address signer,
        bytes memory sig,
        bytes memory data
    ) internal {
        uint256 nonce = spendNominationsOnProposalNonce[signer];
        if (block.timestamp > deadline) {
            _revert(IGovernance.SpendNominationsOnProposalSignatureExpired.selector);
        }
        bytes32 digest =
            _createSpendNominationsOnProposalDigest(proposalType, nominationsToSpend, nonce, deadline, data);
        if (!SignatureChecker.isValidSignatureNow(signer, digest, sig)) {
            _revert(IGovernance.InvalidSpendNominationsOnProposalSignature.selector);
        }
        spendNominationsOnProposalNonce[signer] = nonce + 1;
    }

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
     * @notice Gets the number of active proposals and the last expired proposal id
     * @return numActiveProposals the number of active proposals
     * @return _lastExpiredProposalId the last expired proposal id
     * @return updateState whether or not to update the state
     */
    function _numActiveProposalsAndLastExpiredProposalId()
        internal
        view
        returns (uint256 numActiveProposals, uint256 _lastExpiredProposalId, bool updateState)
    {
        uint256 cachedLastExpiredProposalId = lastExpiredProposalId;
        _lastExpiredProposalId = cachedLastExpiredProposalId;
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
        updateState = _lastExpiredProposalId != cachedLastExpiredProposalId;
    }

    /**
     * @dev returns true if the proposal is eligible for execution
     * returns false otherwise
     * @param proposalId - the proposal id to check
     */
    function isProposalEligibleForExecution(uint256 proposalId) internal view returns (bool) {
        //If the proposal is vetoed, we can skip the execution
        //We still need to update the lastExecutedWeek so the next proposal can be executed
        //We also skip execution if the proposal somehow gets elected twice for execution
        IGovernance.ProposalStatus status = getProposalStatus(proposalId);
        if (status == IGovernance.ProposalStatus.VETOED) {
            return false;
        }
        if (
            status == IGovernance.ProposalStatus.EXECUTED_SUCCESSFULLY
                || status == IGovernance.ProposalStatus.EXECUTED_WITH_ERROR
        ) {
            return false;
        }

        return true;
    }
    /**
     * @dev reverts if the proposal has already been executed
     * @param proposalId the id of the proposal
     */

    function _revertIfProposalExecuted(uint256 proposalId) internal view {
        IGovernance.ProposalStatus status = getProposalStatus(proposalId);
        if (
            status == IGovernance.ProposalStatus.EXECUTED_SUCCESSFULLY
                || status == IGovernance.ProposalStatus.EXECUTED_WITH_ERROR
        ) {
            _revert(IGovernance.ProposalAlreadyExecuted.selector);
        }
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
     * @dev helper function that creates the digest for a spend nominations on proposal signature
     * @param proposalType the type of the proposal
     * @param nominationsToSpend the nominations to spend of the signature
     * @param nonce the nonce of the signature
     * @param deadline the deadline of the signature
     * @param data the data of the proposal
     * @return digest the digest of the signature
     */
    function _createSpendNominationsOnProposalDigest(
        ProposalType proposalType,
        uint256 nominationsToSpend,
        uint256 nonce,
        uint256 deadline,
        bytes memory data
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                _domainSeparatorV4(),
                keccak256(
                    abi.encode(
                        SPEND_NOMINATIONS_ON_PROPOSAL_TYPEHASH,
                        uint8(proposalType),
                        nominationsToSpend,
                        nonce,
                        deadline,
                        keccak256(data)
                    )
                )
            )
        );
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

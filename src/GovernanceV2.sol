// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IGovernanceV2 as IGovernance} from "@/interfaces/IGovernanceV2.sol";
import {HalfLife} from "@/libraries/HalfLife.sol";
import {ABDKMath64x64} from "@/libraries/ABDKMath64x64.sol";
import {IGlow} from "@/interfaces/IGlow.sol";
import {IVetoCouncil} from "@/interfaces/IVetoCouncil.sol";
import {IGCA} from "@/interfaces/IGCA.sol";
import {IGrantsTreasury} from "@/interfaces/IGrantsTreasury.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {NULL_ADDRESS} from "@/VetoCouncil/VetoCouncilSalaryHelper.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {_BUCKET_DURATION} from "@/Constants/Constants.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {GCC as GCCContract} from "@/GCC.sol";
import {console} from "forge-std/console.sol";
/**
 * @title Governance
 * @author DavidVorick
 * @author 0xSimon(twitter) - 0xSimbo(githuhb)
 * @notice This contract is used to manage the Glow governance
 *               - The governance contract is used to manage the Glow protocol
 *               - Proposals are denoted by their types in {ProposalType} enum
 *               - Proposals can be created by anyone and cost nominations
 *               - It should cost (1.1)^n nominations where n = # of active proposals
 *                 - Proposals can be ratified or rejected by long stakers
 *                 - Veto council members can veto proposals (besides elections proposals)
 *                 - Proposals can be executed if they are ratified
 *                     -   RFC Proposals and Grants Proposals don't need to be ratified to be executed
 *                 - Once created, proposals are active for 16 weeks
 *                 - Each week, a most popular proposal is selected
 *                 - Governance also handles rewarding and depreciating nominations
 *                 - Nominations have a half-life of 52 weeks and are earned by committing GCC
 *                 - Nominations are used to create and vote on proposals
 *                 - Nominations are in 12 decimals
 *                      - the equation for calculating nominations is sqrt(amount gcc added to lp * amount usdc added in lp) from a 'commit' event
 *                      - multiplying gcc (18 decimals) and usdc (6 decimals) gives us an output in 24 decimals.
 *                      - since we are sqrt'ing this, we factor out 12 decimals of precision since sqrt(1e24) = 1e12
 *                      - and end up in 12 decimals of precision
 *                In order to prevent a single user from dominating the governance process, the protocol allows for `intents`
 *                - If a single participant does not have enough nominations to create a proposal, they can create an intent
 *                      - Other members can contribute to the intent, and when the intent has enough nominations, it can be converted into a proposal
 *                      - Any participant to the intent can withdraw their nominations at any time
 *                      -  Nominations that were used on an intent have the half life applied to them as well to prevent a half life loophole
 */

contract GovernanceV2 is IGovernance, EIP712 {
    using ABDKMath64x64 for int128;

    /* -------------------------------------------------------------------------- */
    /*                                  constants                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @dev one in 64x64 fixed point
     */
    int128 private constant ONE_64x64 = (1 << 64);

    /**
     * @dev 1.1 in 128x128 fixed point
     * @dev used in the nomination cost calculation
     */
    int128 private constant ONE_POINT_ONE_128 = (1 << 64) + 0x1999999999999a00;

    /**
     * @dev The maximum duration of a proposal: 16 weeks
     */
    uint256 private constant MAX_PROPOSAL_DURATION = 9676800;

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
    uint256 private constant DEFAULT_PERCENTAGE_TO_EXECUTE_PROPOSAL = 60; //60%

    /**
     * @dev The percentage of ratify to reject votes that is required to execute an USDG
     */
    uint256 private constant PERCENTAGE_REQUIRED_TO_EXECUTE_USDG_UPGRADE_PROPOSAL = 66; //66%

    /**
     * @dev there can be a maximum of 5 endorsements on a GCA election proposal
     */
    uint256 private constant MAX_ENDORSEMENTS_ON_GCA_PROPOSALS = 5;

    /**
     * @dev the maximum number of GCA council members that can be concurrently active
     */
    uint256 private constant MAX_GCAS_AT_ONE_POINT_IN_TIME = 5;

    /**
     * @dev the maximum number of slashes that can be executed in a single GCA election
     * @dev this is to prevent DoS attacks that could cause the execution to run out of gas
     */
    uint256 private constant MAX_SLASHES_IN_ONE_GCA_ELECTION = 10;

    /**
     * @dev the maximum number of concurrently active GCA council members
     */
    uint256 private constant MAX_GCAS = 5;

    /**
     * @dev each endorsement decreases the required percentage to execute a GCA election proposal by 5%
     */
    uint256 private constant ENDORSEMENT_WEIGHT = 5;

    /* -------------------------------------------------------------------------- */
    /*                                  immutables                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @dev The GCC contract
     */
    address public immutable GCC;

    /**
     * @dev The GCA contract
     */
    address public immutable GCA;

    /**
     * @dev The Genesis Timestamp of the protocol from GLW
     */
    uint256 public immutable GENESIS_TIMESTAMP;

    /**
     * @dev The Veto Council contract
     */
    address public immutable VETO_COUNCIL;

    /**
     * @dev The Grants Treasury contract
     */
    address public immutable GRANTS_TREASURY;

    /**
     * @dev The GLW contract
     */
    address public immutable GLOW;

    /**
     * @dev The USDG contrac
     */
    address public immutable USDG;

    /* -------------------------------------------------------------------------- */
    /*                                 state vars                                */
    /* -------------------------------------------------------------------------- */
    /**
     * @dev The total number of proposals created
     * @dev we start at one to ensure that a proposal with id 0 is invalid
     */
    uint256 private _proposalCount = 1;

    /**
     * @dev the total number of proposal intents created
     * @dev we start at one to ensure that a proposal intent with id 0 is invalid
     */
    uint256 private _proposalIntentCount = 1;

    /**
     * @notice The last expired proposal id (should not be used for anything other than caching)
     * @dev The last proposal that expired (in storage)
     * @dev this may be out of sync with the actual last expired proposal id
     *      -  it's used as a cache to make _numActiveProposalsAndLastExpiredProposalId() more efficient
     */
    uint256 internal lastExpiredProposalId;

    /**
     * @notice the last executed week (should not be used for anything other than caching)
     * @dev The last proposal that was executed
     * @dev this may be out of sync with the actual last executed proposal id
     * @dev initiaized as type(uint256).max to avoid conflicts which starting checks at week 0
     */
    uint256 internal lastExecutedWeek = type(uint256).max;

    /* -------------------------------------------------------------------------- */
    /*                                   mappings                                  */
    /* -------------------------------------------------------------------------- */

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
     *             - the protocol will not adjust for the unstaked glow
     *             - there is a 5 year cooldown when claiming tokens after unstaking glow so this should not be a problem
     */
    mapping(address => mapping(uint256 => uint256)) public longStakerVotesForProposal;

    /**
     * @dev The nominations of each account
     */
    mapping(address => Nominations) private _nominations;

    /**
     * @dev proposalId -> Proposal
     */
    mapping(uint256 => IGovernance.Proposal) private _proposals;

    /**
     * @dev proposalIntentId -> ProposalIntent
     */
    mapping(uint256 => IGovernance.ProposalIntent) private _proposalIntents;

    /**
     * @dev user -> proposalIntentId -> ProposalIntentSpend
     */
    mapping(address => mapping(uint256 => IGovernance.ProposalIntentSpend)) private _proposalIntentSpends;

    /**
     * @notice the most popular proposal of a given week
     * @dev Certain actions such as using nominations will trigger this update for the current week
     * @dev At the start of every new week, there is no mostt popular proposal stored for that week
     *         -  the {setMostPopularProposalForCurrentWeek} or {useNominationsOnProposal} are the only ways to update
     *         - the mostPopularProposalOfWeek
     *         - Governance relies on those functions to be called to correctly set the most popular proposal
     * @dev if neither of the functions mentioned above are called within the week, the week will not contain a most popular proposal
     *        - as it was not explicitly set
     * @dev it is also possible for a proposal that is not actually the most popular to be selected as the most popular proposal for that week
     *         - For example, if it's a new week and Proposal A and Proposal B have 20 and 10 nominations respectively,
     *         - It is possible to set the most popular proposal to Proposal A.
     *         - If {setMostPopularProposalForCurrentWeek} isn't called to set Proposal B as the most popular proposal
     *         - Or if no nominations are used on Proposal B during that week,
     *         - The week will finalize with Proposal A as the most popular proposal for that week even though proposal B had more nominations
     *         - This is not a problem as the {setMostPopularProposalForCurrentWeek} is permissionless
     * @dev updating the mostPopularProposalOfWeek can be manu
     */
    mapping(uint256 => uint256) public mostPopularProposalOfWeek;

    /// @dev The most popular proposal status at a proposal id
    /// @dev since there are only 8 proposal statuses, we can use a uint256 to store the status
    /// @dev each uint256 is 32 bytes, so we can store 32 statuses in a single uint256
    mapping(uint256 => uint256) private _packedProposalStatus;

    /**
     * @notice the number of endorsements on the most popular proposal of a given week
     * @dev only GCA elections can be endorsed
     * @dev only veto council members can endorse a proposal
     * @dev an endorsement represents a 5% drop to the default percentage to execute a proposal
     * @dev the default percentage to execute a proposal is 60%
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

    /* -------------------------------------------------------------------------- */
    /*                                   structs                                  */
    /* -------------------------------------------------------------------------- */
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

    /* -------------------------------------------------------------------------- */
    /*                                 constructor                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @param gcc - the GCC contract
     * @param gca - the GCA contract
     * @param vetoCouncil - the Veto Council contract
     * @param grantsTreasury - the Grants Treasury contract
     * @param glw - the GLW contract
     */
    constructor(address gcc, address gca, address vetoCouncil, address grantsTreasury, address glw)
        payable
        EIP712("Glow Governance", "2.0")
    {
        GCC = gcc;
        GCA = gca;
        GENESIS_TIMESTAMP = IGlow(glw).GENESIS_TIMESTAMP();
        VETO_COUNCIL = vetoCouncil;
        GRANTS_TREASURY = grantsTreasury;
        GLOW = glw;
        USDG = GCCContract(gcc).USDC();
    }

    /* -------------------------------------------------------------------------- */
    /*                               proposal execution                           */
    /* -------------------------------------------------------------------------- */

    /**
     * @inheritdoc IGovernance
     * @dev proposal execution should be sub-100k gas
     */
    function executeProposalAtWeek(uint256 week) public {
        uint256 _nextWeekToExecute = lastExecutedWeek;
        unchecked {
            //We actually want this to overflow since we start at type(uint256).max
            ++_nextWeekToExecute;
        }
        //We need all proposals to be executed synchronously
        if (_nextWeekToExecute != week) {
            _revert(IGovernance.ProposalsMustBeExecutedSynchonously.selector);
        }
        _handleProposalForWeeekNumber(week);
        lastExecutedWeek = week;
    }

    function _handleProposalForWeeekNumber(uint256 week) internal {
        uint256 proposalId = mostPopularProposalOfWeek[week];

        if (!isProposalEligibleForExecution(proposalId)) {
            lastExecutedWeek = week;
            return;
        }

        IGovernance.Proposal memory proposal = _proposals[proposalId];
        IGovernance.ProposalType proposalType = proposal.proposalType;
        ProposalLongStakerVotes memory longStakerVotes = _proposalLongStakerVotes[proposalId];

        //Revert if the ratify/reject period and veto period is not yet ended
        if (block.timestamp < _weekEndTime(week + _NUM_WEEKS_TO_VOTE_ON_MOST_POPULAR_PROPOSAL)) {
            _revert(IGovernance.RatifyOrRejectPeriodNotEnded.selector);
        }

        //If the proposal is a gca election, we can check endorsements to
        //dynamically determine the required percentage to execute the proposal
        //The default percentage to execute a  proposal is 60%
        //The minimum percentage to execute a gca proposal is 35%
        //RFC and Grants Treasury proposals don't need to be ratified to pass
        if (proposalType == IGovernance.ProposalType.GCA_COUNCIL_ELECTION_OR_SLASH) {
            uint256 numEndorsements = numEndorsementsOnWeek[week];
            uint256 requiredWeight = DEFAULT_PERCENTAGE_TO_EXECUTE_PROPOSAL - (numEndorsements * ENDORSEMENT_WEIGHT);
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
                if (percentage < DEFAULT_PERCENTAGE_TO_EXECUTE_PROPOSAL) {
                    lastExecutedWeek = week;
                    return;
                }
            }
        }

        handleProposalExecution(week, proposalId, proposalType, proposal.data);
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
        //Week needs to be at least 5,
        //First proposal gets selected on the start of week 1
        // and gets finalized in week 1 + 4 = week 5
        //Return to make sure that syncProposals never fails when called
        if (currentWeek < 5) return;
        uint256 _lastExecutedWeek = lastExecutedWeek;
        unchecked {
            ++_lastExecutedWeek;
        }

        //
        uint256 finalWeekToExecutePlusOne = currentWeek - _NUM_WEEKS_TO_VOTE_ON_MOST_POPULAR_PROPOSAL;

        for (_lastExecutedWeek; _lastExecutedWeek < finalWeekToExecutePlusOne; ++_lastExecutedWeek) {
            _handleProposalForWeeekNumber(_lastExecutedWeek);
        }

        if (_lastExecutedWeek != finalWeekToExecutePlusOne - 1) {
            lastExecutedWeek = finalWeekToExecutePlusOne - 1;
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                            proposal   endorsement                          */
    /* -------------------------------------------------------------------------- */

    /**
     * @inheritdoc IGovernance
     */
    function endorseGCAProposal(uint256 weekId) external {
        if (!IVetoCouncil(VETO_COUNCIL).isCouncilMember(msg.sender)) {
            _revert(IGovernance.CallerNotVetoCouncilMember.selector);
        }

        uint256 _currentWeek = currentWeek();
        if (weekId >= _currentWeek) {
            _revert(IGovernance.WeekNotStarted.selector);
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
        uint256 proposalId = mostPopularProposalOfWeek[weekId];
        IGovernance.ProposalType proposalType = _proposals[proposalId].proposalType;
        if (proposalType != IGovernance.ProposalType.GCA_COUNCIL_ELECTION_OR_SLASH) {
            _revert(IGovernance.OnlyGCAElectionsCanBeEndorsed.selector);
        }

        numEndorsements += 1;
        if (numEndorsements > MAX_ENDORSEMENTS_ON_GCA_PROPOSALS) {
            _revert(IGovernance.MaxGCAEndorsementsReached.selector);
        }

        numEndorsementsOnWeek[weekId] = numEndorsements;
    }

    /* -------------------------------------------------------------------------- */
    /*                                veto proposals                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice entrypoint for veto council members to veto a most popular proposal
     * @param weekId - the id of the week to veto the most popular proposal in
     * @param proposalId - the id of the proposal to veto
     */
    function vetoProposal(uint256 weekId, uint256 proposalId) external {
        if (!IVetoCouncil(VETO_COUNCIL).isCouncilMember(msg.sender)) {
            _revert(IGovernance.CallerNotVetoCouncilMember.selector);
        }

        _vetoProposal(weekId, proposalId);
    }

    /* -------------------------------------------------------------------------- */
    /*                                 nominations                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Entry point for GCC contract to grant nominations to {to} when they retire GCC
     * @param to the address to grant nominations to
     * @param amount the amount of nominations to grant
     * @dev this function is only callable by the GCC contract
     * @dev nominations decay with a half life of 1 year.
     *         -for implementation details check {src/libraries/HalfLife.sol}
     */
    function grantNominations(address to, uint256 amount) external override {
        if (msg.sender != GCC) {
            _revert(IGovernance.CallerNotGCC.selector);
        }

        _grantNominations(to, amount);
    }

    /**
     * @notice Allows a user to vote on a proposal
     * @param proposalId the id of the proposal
     * @param amount the amount of nominations to vote with
     * @dev also syncs proposals if need be.
     */
    function useNominationsOnProposal(uint256 proposalId, uint256 amount) public {
        //Sync the proposals
        syncProposals();
        //If the proposal has been executed or vetoed, using nominations should revert
        _revertIfProposalExecutedOrVetoed(proposalId);
        //Cache the nomination end timestamp
        uint256 nominationEndTimestamp = _proposals[proposalId].expirationTimestamp;
        // we don't need this check, but we add it for clarity on the revert reason
        if (nominationEndTimestamp == 0) {
            _revert(IGovernance.ProposalDoesNotExist.selector);
        }
        //nomination spend on expired proposals is not allowed
        if (block.timestamp > nominationEndTimestamp) {
            _revert(IGovernance.ProposalExpired.selector);
        }

        //Spend the nominations
        _spendNominations(msg.sender, amount);
        //Get the new total votes
        uint184 newTotalVotes = SafeCast.toUint184(_proposals[proposalId].votes + amount);
        //Update the state of the proposal with the new total votes
        _proposals[proposalId].votes = newTotalVotes;
        //Get teh current week
        uint256 currentWeek = currentWeek();
        //Grab the currently most popular proposal at the current week
        uint256 _mostPopularProposalOfWeek = mostPopularProposalOfWeek[currentWeek];
        //If the proposal which nominatiosn are being used on
        //has more nominatiosn than the current most popular proposal
        //we update the most popular proposal to the one on which nominations are being used
        if (proposalId != _mostPopularProposalOfWeek) {
            if (newTotalVotes > _proposals[_mostPopularProposalOfWeek].votes) {
                mostPopularProposalOfWeek[currentWeek] = proposalId;
                emit IGovernance.MostPopularProposalSet(currentWeek, proposalId);
            }
        }

        emit IGovernance.NominationsUsedOnProposal(proposalId, msg.sender, amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                         selecting most popular proposal                    */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice sets the proposal as the most popular proposal for the current week
     * @dev checks if the proposal is the most popular proposal for the current week and sets it if it is
     * @dev throws an error if the proposal is not the most popular proposal or if the proposal has expired
     * @param proposalId The ID of the proposal to set as the most popular.
     */
    function setMostPopularProposalForCurrentWeek(uint256 proposalId) external {
        syncProposals();
        _revertIfProposalExecutedOrVetoed(proposalId);
        // get the current week
        uint256 currentWeek = currentWeek();
        // get the most popular proposal for the current week
        uint256 _mostPopularProposalOfWeek = mostPopularProposalOfWeek[currentWeek];
        // get the expiration timestamp of the proposal
        uint256 expirationTimestamp = _proposals[proposalId].expirationTimestamp;
        // get the number of votes on the proposal
        uint256 numVotesOnProposal = _proposals[proposalId].votes;
        // check if the proposal has expired
        if (expirationTimestamp < block.timestamp) {
            _revert(IGovernance.ProposalExpired.selector);
        }
        // check if the proposal is already the most popular proposal
        if (proposalId != _mostPopularProposalOfWeek) {
            // check if the number of votes on the proposal is greater than the number of votes on the current most popular proposal
            if (numVotesOnProposal > _proposals[_mostPopularProposalOfWeek].votes) {
                // set the proposal as the most popular proposal for the current week
                mostPopularProposalOfWeek[currentWeek] = proposalId;
            } else {
                // throw an error if the proposal is not the most popular proposal
                _revert(IGovernance.ProposalNotMostPopular.selector);
            }
        }
        emit IGovernance.MostPopularProposalSet(currentWeek, proposalId);
    }

    /* -------------------------------------------------------------------------- */
    /*                                ratify/reject                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice entrypoint for long staked glow holders to vote on proposals
     * @param weekOfMostPopularProposal - the week that the proposal got selected as the most popular proposal for
     * @param trueForRatify  - if true the stakers are ratifying the proposal
     *                             - if false they are rejecting it
     * @param numVotes  - the number of ratify/reject votes they want to apply on this proposal
     *                  - the total number of ratify/reject votes must always be lte than
     *                  - the total glow they have staked
     */
    function ratifyOrReject(uint256 weekOfMostPopularProposal, bool trueForRatify, uint256 numVotes) external {
        //Cache the current week
        uint256 currentWeek = currentWeek();
        //Cache the most popular propsal at `weekOfMostPopularProposal`
        uint256 _mostPopularProposalOfWeek = mostPopularProposalOfWeek[weekOfMostPopularProposal];

        //Get the proposal status
        IGovernance.ProposalStatus status = getProposalStatus(_mostPopularProposalOfWeek);
        //if the proposal has been vetoed,
        //It cannot accept ratify or reject votes
        if (status == IGovernance.ProposalStatus.VETOED) {
            _revert(IGovernance.ProposalAlreadyVetoed.selector);
        }
        //If the proposal has already been executed
        //The proposal cannot accept ratify or reject votes
        if (
            status == IGovernance.ProposalStatus.EXECUTED_SUCCESSFULLY
                || status == IGovernance.ProposalStatus.EXECUTED_WITH_ERROR
        ) {
            _revert(IGovernance.ProposalAlreadyExecuted.selector);
        }

        //The week of which the proposal is the most popular proposal for
        //must have already ended
        if (weekOfMostPopularProposal >= currentWeek) {
            _revert(IGovernance.WeekMustHaveEndedToAcceptRatifyOrRejectVotes.selector);
        }

        //The proposal cannot accept ratify/reject votes
        //Past the ratify/reject window
        if (block.timestamp > _weekEndTime(weekOfMostPopularProposal + _NUM_WEEKS_TO_VOTE_ON_MOST_POPULAR_PROPOSAL)) {
            _revert(IGovernance.RatifyOrRejectPeriodEnded.selector);
        }
        //If the proposal was not set at all
        //The function must revert as well
        if (_mostPopularProposalOfWeek == 0) {
            _revert(IGovernance.MostPopularProposalNotSelected.selector);
        }

        //Load the amount of glow the sender has staked
        uint256 userNumStakedGlow = IGlow(GLOW).numStaked(msg.sender);
        //Load how many votes the sender has already used on this proposal
        uint256 amountVotesUsed = longStakerVotesForProposal[msg.sender][_mostPopularProposalOfWeek];
        //revert if the amount of votes the sender has already used
        //Plus the additional votes to cast is greater than their total amount of staked glow
        if (amountVotesUsed + numVotes > userNumStakedGlow) {
            _revert(IGovernance.InsufficientRatifyOrRejectVotes.selector);
        }

        //Spend the ratify/reject votes accordingly
        if (trueForRatify) {
            _proposalLongStakerVotes[_mostPopularProposalOfWeek].ratifyVotes += uint128(numVotes);
            emit IGovernance.RatifyCast(_mostPopularProposalOfWeek, msg.sender, numVotes);
        } else {
            _proposalLongStakerVotes[_mostPopularProposalOfWeek].rejectionVotes += uint128(numVotes);
            emit IGovernance.RejectCast(_mostPopularProposalOfWeek, msg.sender, numVotes);
        }
        //Update the amount of votes the sender has spent on this proposal
        longStakerVotesForProposal[msg.sender][_mostPopularProposalOfWeek] = amountVotesUsed + numVotes;
    }

    /* -------------------------------------------------------------------------- */
    /*                              creating proposals                            */
    /* -------------------------------------------------------------------------- */

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
        uint256 proposalId = _createProposal(
            msg.sender,
            maxNominations,
            IGovernance.ProposalType.GRANTS_PROPOSAL,
            abi.encode(grantsRecipient, amount, hash),
            true
        );

        emit IGovernance.GrantsProposalCreation(proposalId, msg.sender, grantsRecipient, amount, hash, maxNominations);
    }

    /**
     * @notice Creates a proposal to change the GCA requirements
     * @param newRequirementsHash the new requirements hash
     *             - the pre-image should be made public off-chain
     * @param maxNominations the maximum amount of nominations to spend on this proposal
     */
    function createChangeGCARequirementsProposal(bytes32 newRequirementsHash, uint256 maxNominations) external {
        uint256 proposalId = _createProposal(
            msg.sender,
            maxNominations,
            IGovernance.ProposalType.CHANGE_GCA_REQUIREMENTS,
            abi.encode(newRequirementsHash),
            true
        );

        emit IGovernance.ChangeGCARequirementsProposalCreation(
            proposalId, msg.sender, newRequirementsHash, maxNominations
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
        uint256 proposalId = _createProposal(
            msg.sender, maxNominations, IGovernance.ProposalType.REQUEST_FOR_COMMENT, abi.encode(hash), true
        );

        emit IGovernance.RFCProposalCreation(proposalId, msg.sender, hash, maxNominations);
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
        if (newGCAs.length > MAX_GCAS_AT_ONE_POINT_IN_TIME) {
            _revert(IGovernance.MaximumNumberOfGCAS.selector);
        }
        if (agentsToSlash.length > MAX_SLASHES_IN_ONE_GCA_ELECTION) {
            _revert(IGovernance.MaxSlashesInGCAElection.selector);
        }
        //[agentsToSlash,newGCAs,proposalCreationTimestamp]
        bytes32 hash = keccak256(abi.encode(agentsToSlash, newGCAs, block.timestamp));
        bool incrementSlashNonce = agentsToSlash.length > 0;

        uint256 proposalId = _createProposal(
            msg.sender,
            maxNominations,
            IGovernance.ProposalType.GCA_COUNCIL_ELECTION_OR_SLASH,
            abi.encode(hash, incrementSlashNonce),
            true
        );

        emit IGovernance.GCACouncilElectionOrSlashCreation(
            proposalId, msg.sender, agentsToSlash, newGCAs, block.timestamp, maxNominations
        );
    }

    /**
     * @notice Creates a proposal to add, replace, or slash Veto a single veto council member
     * @param oldMember the old agent to be replaced
     *         -   If the agent is address(0), it means we are simply adding a new agent
     * @param newMember the new agent to replace the old agent
     *         -   If the agent is address(0), it means we are simply removing an agent
     * @param slashOldMember whether or not to slash the old agent
     * @param maxNominations the maximum amount of nominations to spend on this proposal
     */
    function createVetoCouncilElectionOrSlash(
        address oldMember,
        address newMember,
        bool slashOldMember,
        uint256 maxNominations
    ) external {
        if (oldMember == newMember) {
            _revert(IGovernance.VetoCouncilProposalCreationOldMemberCannotEqualNewMember.selector);
        }

        if (oldMember == NULL_ADDRESS) {
            _revert(IGovernance.VetoMemberCannotBeNullAddress.selector);
        }
        if (newMember == NULL_ADDRESS) {
            _revert(IGovernance.VetoMemberCannotBeNullAddress.selector);
        }

        uint256 proposalId = _createProposal(
            msg.sender,
            maxNominations,
            IGovernance.ProposalType.VETO_COUNCIL_ELECTION_OR_SLASH,
            abi.encode(oldMember, newMember, slashOldMember, block.timestamp),
            true
        );

        emit IGovernance.VetoCouncilElectionOrSlash(
            proposalId, msg.sender, oldMember, newMember, slashOldMember, maxNominations
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                                    intents                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Allows a user to add votes to an intent
     * @dev The intent will be turned into a proposal if the votes exceed or match the cost of a new proposal
     * @param intentId the id of the intent
     * @param amount the amount of nominations to add to the intent
     */
    function addVotesToIntent(uint256 intentId, uint256 amount) external {
        _spendNominations(msg.sender, amount);
        IGovernance.ProposalIntent memory intent = _proposalIntents[intentId];
        if (intent.proposalType == IGovernance.ProposalType.NONE) {
            _revert(IGovernance.NonexistentIntent.selector);
        }
        if (intent.executed) {
            _revert(IGovernance.IntentAlreadyExecuted.selector);
        }
        //If the intent has already been executed, we don't allow votes to be added
        uint256 nominationCostForNewProposal = costForNewProposal();
        intent.votes = SafeCast.toUint184(intent.votes + amount);

        if (intent.votes >= nominationCostForNewProposal) {
            //Then we need to create the proposal without spending nominations from that user
            // Since they are already deducted above.
            uint256 proposalId = _createProposal(address(this), intent.votes, intent.proposalType, intent.data, false);
            _proposalIntents[intentId].executed = true;
            // We can return here since the intent has been turned into a proposal
            // There is no need to add `amount` to the intent since it would be an unnecessary gas cost
            emit IGovernance.IntentExecutedIntoProposal(intentId, proposalId);
            return;
        }
        IGovernance.ProposalIntentSpend memory spend = _proposalIntentSpends[msg.sender][intentId];
        //If this is their first time adding a spend to an intent, simply add it
        if (spend.spendTimestamp == 0) {
            _proposalIntentSpends[msg.sender][intentId] = IGovernance.ProposalIntentSpend({
                votes: SafeCast.toUint184(amount),
                spendTimestamp: SafeCast.toUint64(block.timestamp)
            });
        } else {
            //If it's not their first time, we need to calculate the half life or what those nominations
            // are worth now. We don't worry about deducting the difference in the total votes, just in the
            // amount of votes they have spent. This is necessary because they can withdraw votes that are part
            // of an intent that has not yet been turned into a proposal
            uint256 halfLifeValue = HalfLife.calculateHalfLifeValue(spend.votes, block.timestamp - spend.spendTimestamp);

            _proposalIntentSpends[msg.sender][intentId] = IGovernance.ProposalIntentSpend({
                votes: SafeCast.toUint184(halfLifeValue + amount),
                spendTimestamp: SafeCast.toUint64(block.timestamp)
            });
        }

        _proposalIntents[intentId].votes += SafeCast.toUint184(amount);
        emit IGovernance.VotesAddedToIntent(intentId, msg.sender, amount);
    }

    function withdrawVotesFromNonexecutedIntent(uint256 proposalIntentId) external {
        IGovernance.ProposalIntent memory intent = _proposalIntents[proposalIntentId];
        if (intent.proposalType == IGovernance.ProposalType.NONE) {
            _revert(IGovernance.NonexistentIntent.selector);
        }
        if (intent.executed) {
            _revert(IGovernance.IntentAlreadyExecuted.selector);
        }
        IGovernance.ProposalIntentSpend memory spend = _proposalIntentSpends[msg.sender][proposalIntentId];
        if (spend.spendTimestamp == 0) {
            _revert(IGovernance.NoVotesToClaim.selector);
        }
        uint256 halfLifeValue = HalfLife.calculateHalfLifeValue(spend.votes, block.timestamp - spend.spendTimestamp);
        delete _proposalIntentSpends[msg.sender][proposalIntentId];
        _grantNominations(msg.sender, halfLifeValue);
        _proposalIntents[proposalIntentId].votes -= spend.votes;
        emit IGovernance.VotesWithdrawnFromIntent(proposalIntentId, msg.sender, spend.votes);
    }

    /**
     * @notice Creates a proposal intent to send a grant to a recipient
     * @param grantsRecipient the recipient of the grant
     * @param amount the amount of the grant
     * @param hash the hash of the proposal
     *             - the pre-image should be made public off-chain
     * @param maxNominations the maximum amount of nominations to spend on this proposal
     */
    function createGrantsProposalIntent(address grantsRecipient, uint256 amount, bytes32 hash, uint256 maxNominations)
        external
    {
        uint256 proposalIdIntentId = _createProposalIntent(
            msg.sender,
            maxNominations,
            IGovernance.ProposalType.GRANTS_PROPOSAL,
            abi.encode(grantsRecipient, amount, hash)
        );

        emit IGovernance.GrantsProposalIntentCreation({
            proposalIntentId: proposalIdIntentId,
            proposer: msg.sender,
            recipient: grantsRecipient,
            amount: amount,
            hash: hash,
            nominationsUsedFromIntent: maxNominations
        });
    }

    /**
     * @notice Creates a proposal intent to change the GCA requirements
     * @param newRequirementsHash the new requirements hash
     *             - the pre-image should be made public off-chain
     * @param maxNominations the maximum amount of nominations to spend on this proposal
     */
    function createChangeGCARequirementsProposalIntent(bytes32 newRequirementsHash, uint256 maxNominations) external {
        uint256 proposalIdIntentId = _createProposalIntent(
            msg.sender,
            maxNominations,
            IGovernance.ProposalType.CHANGE_GCA_REQUIREMENTS,
            abi.encode(newRequirementsHash)
        );

        emit IGovernance.ChangeGCARequirementsProposalIntentCreation({
            proposalIntentId: proposalIdIntentId,
            proposer: msg.sender,
            requirementsHash: newRequirementsHash,
            nominationsUsedFromIntent: maxNominations
        });
    }

    /**
     * @notice Creates a proposal intent to create an RFC
     *     - the pre-image should be made public off-chain
     *     - if accepted, veto council members must read the RFC (up to 10k Words) and provide a written statement on their thoughts
     *
     * @param hash the hash of the proposal
     * @param maxNominations the maximum amount of nominations to spend on this proposal
     */
    function createRFCProposalIntent(bytes32 hash, uint256 maxNominations) external {
        uint256 proposalIntentId = _createProposalIntent(
            msg.sender, maxNominations, IGovernance.ProposalType.REQUEST_FOR_COMMENT, abi.encode(hash)
        );
        emit IGovernance.RFCProposalIntentCreation({
            proposalIntentId: proposalIntentId,
            proposer: msg.sender,
            rfcHash: hash,
            nominationsUsedFromIntent: maxNominations
        });
    }

    /**
     * @notice Creates a proposal intent to add, replace, or slash GCA council members
     * @param agentsToSlash an array of all gca's that are to be slashed
     *         - could be empty
     *         - could be a subset of the current GCAs
     *         - could be any address [in order to account for previous GCA's]
     * @param newGCAs the new GCAs
     *     -   can be empty if all GCA's are bad actors
     * @param maxNominations the maximum amount of nominations to spend on this proposal
     */
    function createGCACouncilElectionOrSlashIntent(
        address[] calldata agentsToSlash,
        address[] calldata newGCAs,
        uint256 maxNominations
    ) external {
        if (newGCAs.length > MAX_GCAS_AT_ONE_POINT_IN_TIME) {
            _revert(IGovernance.MaximumNumberOfGCAS.selector);
        }
        if (agentsToSlash.length > MAX_SLASHES_IN_ONE_GCA_ELECTION) {
            _revert(IGovernance.MaxSlashesInGCAElection.selector);
        }
        //[agentsToSlash,newGCAs,proposalCreationTimestamp]
        bytes32 hash = keccak256(abi.encode(agentsToSlash, newGCAs, block.timestamp));
        bool incrementSlashNonce = agentsToSlash.length > 0;

        uint256 proposalIntentId = _createProposalIntent(
            msg.sender,
            maxNominations,
            IGovernance.ProposalType.GCA_COUNCIL_ELECTION_OR_SLASH,
            abi.encode(hash, incrementSlashNonce)
        );

        emit IGovernance.GCACouncilElectionOrSlashIntentCreation({
            proposalIntentId: proposalIntentId,
            proposer: msg.sender,
            agentsToSlash: agentsToSlash,
            newGCAs: newGCAs,
            nominationsUsedFromIntent: maxNominations
        });
    }

    /**
     * @notice Creates a proposal intent to add, replace, or slash Veto a single veto council member
     * @param oldMember the old agent to be replaced
     *         -   If the agent is address(0), it means we are simply adding a new agent
     * @param newMember the new agent to replace the old agent
     *         -   If the agent is address(0), it means we are simply removing an agent
     * @param slashOldMember whether or not to slash the old agent
     * @param maxNominations the maximum amount of nominations to spend on this proposal
     */
    function createVetoCouncilElectionOrSlashIntent(
        address oldMember,
        address newMember,
        bool slashOldMember,
        uint256 maxNominations
    ) external {
        if (oldMember == newMember) {
            _revert(IGovernance.VetoCouncilProposalCreationOldMemberCannotEqualNewMember.selector);
        }

        if (oldMember == NULL_ADDRESS) {
            _revert(IGovernance.VetoMemberCannotBeNullAddress.selector);
        }
        if (newMember == NULL_ADDRESS) {
            _revert(IGovernance.VetoMemberCannotBeNullAddress.selector);
        }

        uint256 proposalIntentId = _createProposalIntent(
            msg.sender,
            maxNominations,
            IGovernance.ProposalType.VETO_COUNCIL_ELECTION_OR_SLASH,
            abi.encode(oldMember, newMember, slashOldMember, block.timestamp)
        );
        emit IGovernance.VetoCouncilElectionOrSlashIntentCreation({
            proposalIntentId: proposalIntentId,
            proposer: msg.sender,
            oldAgent: oldMember,
            newAgent: newMember,
            slashOldAgent: slashOldMember,
            nominationsUsedFromIntent: maxNominations
        });
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

    /* -------------------------------------------------------------------------- */
    /*                                 view functions                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice returns {true} if a gca has endorsed the proposal at {weekId}
     * @param gca - the address of the gca to check
     * @param weekId - the week to check
     * @return hasEndorsedProposal - true if the specified gca endorsed the proposal at the specified week
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
        return (block.timestamp - GENESIS_TIMESTAMP) / bucketDuration();
    }

    /**
     * @notice Gets the status of the most popular proposal of a given week
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

    /* -------------------------------------------------------------------------- */
    /*                                 internal                                 */
    /* -------------------------------------------------------------------------- */

    function _createProposal(
        address creator,
        uint256 maxNominations,
        IGovernance.ProposalType proposalType,
        bytes memory data,
        bool spendNominations
    ) internal returns (uint256 proposalId) {
        proposalId = _proposalCount;
        uint256 nominationCost = costForNewProposalAndUpdateLastExpiredProposalId();
        if (maxNominations < nominationCost) {
            _revert(IGovernance.NominationCostGreaterThanAllowance.selector);
        }

        if (spendNominations) {
            _spendNominations(creator, maxNominations);
        }

        _proposals[proposalId] = IGovernance.Proposal(
            proposalType,
            SafeCast.toUint64(block.timestamp + MAX_PROPOSAL_DURATION),
            SafeCast.toUint184(maxNominations),
            data
        );

        uint256 _currentWeek = currentWeek();
        uint256 _mostPopularProposalOfWeek = mostPopularProposalOfWeek[_currentWeek];
        if (maxNominations > _proposals[_mostPopularProposalOfWeek].votes) {
            mostPopularProposalOfWeek[_currentWeek] = proposalId;
            emit IGovernance.MostPopularProposalSet(_currentWeek, proposalId);
        }

        _proposalCount = proposalId + 1;
    }

    function _createProposalIntent(
        address user,
        uint256 nominationsToUse,
        IGovernance.ProposalType proposalType,
        bytes memory data
    ) internal returns (uint256 proposalIntentId) {
        proposalIntentId = _proposalIntentCount;
        _spendNominations(user, nominationsToUse);
        _proposalIntents[proposalIntentId] = IGovernance.ProposalIntent({
            proposalType: proposalType,
            executed: false,
            votes: SafeCast.toUint184(nominationsToUse),
            data: data
        });
        _proposalIntentSpends[user][proposalIntentId] = IGovernance.ProposalIntentSpend({
            votes: SafeCast.toUint184(nominationsToUse),
            spendTimestamp: SafeCast.toUint64(block.timestamp)
        });

        _proposalIntentCount = proposalIntentId + 1;
    }

    /**
     * @dev vetoes the most popular proposal of a given week
     * @param weekId - the id of the week to veto the most popular proposal in
     * @param proposalId - the id of the proposal to veto
     */
    function _vetoProposal(uint256 weekId, uint256 proposalId) internal {
        if (mostPopularProposalOfWeek[weekId] != proposalId) {
            _revert(IGovernance.ProposalIdDoesNotMatchMostPopularProposal.selector);
        }

        uint256 _currentWeek = currentWeek();
        if (weekId >= _currentWeek) {
            _revert(IGovernance.WeekNotStarted.selector);
        }
        //Also make sure it's not already finalized
        uint256 _weekEndTime = _weekEndTime(weekId + _NUM_WEEKS_TO_VOTE_ON_MOST_POPULAR_PROPOSAL);
        if (block.timestamp > _weekEndTime) {
            _revert(IGovernance.RatifyOrRejectPeriodEnded.selector);
        }

        IGovernance.ProposalType proposalType = _proposals[proposalId].proposalType;
        //Elections can't be vetoed
        if (proposalType == IGovernance.ProposalType.VETO_COUNCIL_ELECTION_OR_SLASH) {
            _revert(IGovernance.VetoCouncilElectionsCannotBeVetoed.selector);
        }

        if (proposalType == IGovernance.ProposalType.GCA_COUNCIL_ELECTION_OR_SLASH) {
            _revert(IGovernance.GCACouncilElectionsCannotBeVetoed.selector);
        }

        _setProposalStatus(proposalId, IGovernance.ProposalStatus.VETOED);
        emit IGovernance.ProposalVetoed(weekId, msg.sender, proposalId);
    }

    /**
     * @dev internal function to execute a proposal
     * @param week the week where the proposal was most popular
     * @param proposalId the id of the proposal
     * @param proposalType the type of the proposal
     * @param data the data of the proposal
     */
    function handleProposalExecution(
        uint256 week,
        uint256 proposalId,
        IGovernance.ProposalType proposalType,
        bytes memory data
    ) internal {
        bool success;
        if (proposalType == IGovernance.ProposalType.VETO_COUNCIL_ELECTION_OR_SLASH) {
            (address oldMember, address newMember, bool slashOldMember) = abi.decode(data, (address, address, bool));
            success = IVetoCouncil(VETO_COUNCIL).addAndRemoveCouncilMember(oldMember, newMember, slashOldMember);
        }

        if (proposalType == IGovernance.ProposalType.GCA_COUNCIL_ELECTION_OR_SLASH) {
            (bytes32 hash, bool incrementSlashNonce) = abi.decode(data, (bytes32, bool));
            //push hash should never revert;
            IGCA(GCA).pushHash(hash, incrementSlashNonce);
            success = true;
        }

        if (proposalType == IGovernance.ProposalType.GRANTS_PROPOSAL) {
            (address grantsRecipient, uint256 amount,) = abi.decode(data, (address, uint256, bytes32));
            success = IGrantsTreasury(GRANTS_TREASURY).allocateGrantFunds(grantsRecipient, amount);
        }

        if (proposalType == IGovernance.ProposalType.CHANGE_GCA_REQUIREMENTS) {
            (bytes32 newRequirementsHash) = abi.decode(data, (bytes32));
            //setRequirementsHash should never revert
            IGCA(GCA).setRequirementsHash(newRequirementsHash);
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

        emit IGovernance.ProposalExecution(week, proposalId, proposalType, success);
    }

    /**
     * @dev internal function to get the cost for a new proposal that also updates the
     *         -  last expired proposal id if need be
     */
    function costForNewProposalAndUpdateLastExpiredProposalId() internal returns (uint256) {
        (uint256 numActiveProposals,) = _numActiveProposalsAndLastExpiredProposalIdAndUpdateState();
        return _getNominationCostForProposalCreation(numActiveProposals);
    }

    /**
     * @dev helper func to spend nominations from an account
     *         -   should never be public
     * @param account the account to spend nominations from
     * @param amount the amount of nominations to spend
     */
    function _spendNominations(address account, uint256 amount) internal {
        if (amount == 0) _revert(IGovernance.CannotSpendZeroNominations.selector);
        uint256 currentBalance = nominationsOf(account);
        if (currentBalance < amount) {
            _revert(IGovernance.InsufficientNominations.selector);
        }
        _nominations[account] =
            Nominations(SafeCast.toUint192(currentBalance - amount), SafeCast.toUint64(block.timestamp));
    }

    /**
     * @dev sets the proposal status for the most popular proposal of a given week
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
     * @notice Gets the nomination cost for proposal creation based on {numActiveProposals}
     * @param numActiveProposals the number of active proposals
     * @return res the nomination cost for proposal creation
     * @dev calculates cost as 1 * 1.1^numActiveProposals
     * @dev we only use 4 decimals of precision
     */
    function _getNominationCostForProposalCreation(uint256 numActiveProposals) internal pure returns (uint256) {
        uint256 res = ONE_64x64.mul(ABDKMath64x64.pow(ONE_POINT_ONE_128, numActiveProposals)).mulu(1e4);
        //Multiply by 1e8 to get it in 12 decimals
        //nominations are in 12 decimals of precision
        // as the formula for calculating nominations is sqrt(amount gcc added to lp * amount usdc added in lp)
        //from a 'commit' event
        //multiplying gcc (18 decimals) and usdc (6 decimals) gives us an output in 24 decimals.
        // since we are sqrt'ing this, we factor our 12 decimals of precision since sqrt(1e24) = 1e12
        // and end up in 12 decimals of precision
        return res * 1e8;
    }

    /**
     * @dev Grants nominations to a user
     * @param to the address to grant nominations to
     * @param amount the amount of nominations to grant
     */
    function _grantNominations(address to, uint256 amount) internal {
        //Step 1: check their current balance
        Nominations memory n = _nominations[to];
        uint256 currentBalance = HalfLife.calculateHalfLifeValue(n.amount, block.timestamp - n.lastUpdate);
        //Step 2: update their balance
        _nominations[to] = Nominations(SafeCast.toUint192(currentBalance + amount), SafeCast.toUint64(block.timestamp));
        return;
    }

    /**
     * @notice returns the bucket duration
     * @return bucketDuration - the bucket duration
     */
    function bucketDuration() internal pure virtual returns (uint256) {
        return _BUCKET_DURATION;
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
        _lastExpiredProposalId = _lastExpiredProposalId == 0 ? 1 : _lastExpiredProposalId;
        uint256 cachedProposalCount = _proposalCount;
        unchecked {
            for (uint256 i = _lastExpiredProposalId; i < cachedProposalCount; ++i) {
                if (_proposals[i].expirationTimestamp < block.timestamp) {
                    _lastExpiredProposalId = i;
                } else {
                    break;
                }
            }
        }
        numActiveProposals = cachedProposalCount - _lastExpiredProposalId;
        updateState = _lastExpiredProposalId != cachedLastExpiredProposalId;
    }

    /**
     * @dev returns true if the proposal is eligible for execution
     * returns false otherwise
     * @param proposalId - the proposal id to check
     */
    function isProposalEligibleForExecution(uint256 proposalId) internal view returns (bool) {
        IGovernance.ProposalStatus status = getProposalStatus(proposalId);
        //If the proposal is vetoed, we can skip the execution
        if (status == IGovernance.ProposalStatus.VETOED) {
            return false;
        }
        //We also skip execution if the proposal somehow gets elected twice for execution
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

    function _revertIfProposalExecutedOrVetoed(uint256 proposalId) internal view {
        IGovernance.ProposalStatus status = getProposalStatus(proposalId);
        if (status == IGovernance.ProposalStatus.EXECUTED_SUCCESSFULLY) {
            _revert(IGovernance.ProposalAlreadyExecuted.selector);
        }

        if (status == IGovernance.ProposalStatus.EXECUTED_WITH_ERROR) {
            _revert(IGovernance.ProposalAlreadyExecuted.selector);
        }
        if (status == IGovernance.ProposalStatus.VETOED) _revert(IGovernance.ProposalIsVetoed.selector);
    }
    /**
     * @notice finds the time at which the week ends
     * @dev for example, {weekNumber = 1} would give the timestamp at which week 1 would be over
     * @param weekNumber - the week number to find the end timestamp for
     * @return endTimestamp - the end timestamp of the week number
     */

    function _weekEndTime(uint256 weekNumber) internal view returns (uint256) {
        return GENESIS_TIMESTAMP + ((weekNumber + 1) * bucketDuration());
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
        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            isZero := iszero(a)
        }
    }

    /**
     * @notice More efficiently reverts with a bytes4 selector
     * @param selector The selector to revert with
     */
    function _revert(bytes4 selector) private pure {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(0x0, selector)
            revert(0x0, 0x04)
        }
    }
}

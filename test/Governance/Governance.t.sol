// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "@/testing/TestGCC.sol";
import "forge-std/console.sol";
import {IGCA} from "@/interfaces/IGCA.sol";
import {MockGCA} from "@/MinerPoolAndGCA/mock/MockGCA.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CarbonCreditAuction} from "@/CarbonCreditAuction.sol";
import "forge-std/StdUtils.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {TestGLOW} from "@/testing/TestGLOW.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MerkleProofLib} from "@solady/utils/MerkleProofLib.sol";
import {MockMinerPoolAndGCA} from "@/MinerPoolAndGCA/mock/MockMinerPoolAndGCA.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";
import {IMinerPool} from "@/interfaces/IMinerPool.sol";
import {BucketSubmission} from "@/MinerPoolAndGCA/BucketSubmission.sol";
import {VetoCouncil} from "@/VetoCouncil.sol";
import {Governance} from "@/Governance.sol";
import {IGovernance} from "@/interfaces/IGovernance.sol";
import {TestGCC} from "@/testing/TestGCC.sol";
import {HalfLife} from "@/libraries/HalfLife.sol";
import {DivergenceHandler} from "./Handlers/DivergenceHandler.sol";
/*
TODO:
1. Add tests for also claiming GRC tokens
2. Add tests for claiming multiple GRC tokens.
3. Add test for claiming glw and grc at same time
*/

contract GovernanceTest is Test {
    //--------  CONTRACTS ---------//
    MockMinerPoolAndGCA minerPoolAndGCA;
    TestGLOW glow;
    MockUSDC usdc;
    MockUSDC grc2;
    Governance governance;
    TestGCC gcc;
    DivergenceHandler divergenceHandler;

    //--------  ADDRESSES ---------//
    address earlyLiquidity = address(0x2);
    address vestingContract = address(0x3);
    address vetoCouncilAddress;
    VetoCouncil vetoCouncil;
    address grantsTreasuryAddress = address(0x5);
    address SIMON;
    uint256 SIMON_PRIVATE_KEY;

    address OTHER_GCA = address(0x7);
    address OTHER_GCA_2 = address(0x8);
    address OTHER_GCA_3 = address(0x9);
    address OTHER_GCA_4 = address(0x10);
    address carbonCreditAuction = address(0x11);
    address defaultAddressInWithdraw = address(0x555);
    address bidder1 = address(0x12);
    address bidder2 = address(0x13);

    //--------  CONSTANTS ---------//
    uint256 constant ONE_WEEK = 7 * uint256(1 days);
    uint256 ONE_YEAR = 365 * uint256(1 days);

    function setUp() public {
        //Make sure we don't start at 0
        governance = new Governance();
        (SIMON, SIMON_PRIVATE_KEY) = _createAccount(9999, type(uint256).max);
        vm.warp(10);
        usdc = new MockUSDC();
        glow = new TestGLOW(earlyLiquidity,vestingContract);
        address[] memory temp = new address[](0);
        address[] memory startingAgents = new address[](1);
        startingAgents[0] = address(SIMON);
        vetoCouncil = new VetoCouncil(address(governance), address(glow),startingAgents);
        vetoCouncilAddress = address(vetoCouncil);
        minerPoolAndGCA =
        new MockMinerPoolAndGCA(temp,address(glow),address(governance),keccak256("requirementsHash"),earlyLiquidity,address(usdc),carbonCreditAuction,vetoCouncilAddress);
        glow.setContractAddresses(address(minerPoolAndGCA), vetoCouncilAddress, grantsTreasuryAddress);
        grc2 = new MockUSDC();
        gcc = new TestGCC(carbonCreditAuction, address(minerPoolAndGCA), address(governance));
        // governance.setContractAddresses(gcc, gca, vetoCouncil, grantsTreasury, glw);
        governance.setContractAddresses(
            address(gcc), address(minerPoolAndGCA), vetoCouncilAddress, grantsTreasuryAddress, address(glow)
        );

        divergenceHandler = new DivergenceHandler();

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = DivergenceHandler.runSims.selector;
        FuzzSelector memory fs = FuzzSelector({selectors: selectors, addr: address(divergenceHandler)});
        targetContract(address(divergenceHandler));
    }

    /**
     * forge-config: default.invariant.runs = 100
     * forge-config: default.invariant.depth = 10
     * @dev cannot divert more than .001%'
     */
    function invariant_halfLifeCalculations_shouldNotDivergeGreatly() public {
        uint256 iters = divergenceHandler.iterations();
        for (uint256 i; i < iters; i++) {
            uint128 solidityRes = divergenceHandler.amountFromSolidity(i);
            uint128 rustRes = divergenceHandler.amountFromRust(i);
            bool diverged = divergenceCheck(solidityRes, rustRes);
            // if (diverged) {
            //     string memory inputsForDivergenceCheck = string(
            //         abi.encodePacked(
            //             "solidity res = ", Strings.toString(solidityRes), "rust res = ", Strings.toString(rustRes)
            //         )
            //     );
            //     vm.writeLine("temp.txt", inputsForDivergenceCheck);
            // }
            assert(!diverged);
        }
    }

    /**
     * forge-config: default.invariant.runs = 100
     * forge-config: default.invariant.depth = 10
     * @dev cannot divert more than .001%'
     */
    function invariant_halfLifeCalculations_divergeOnPurposeToFail() public {
        uint256 iters = divergenceHandler.iterations();
        for (uint256 i; i < iters; ++i) {
            uint128 solidityRes = divergenceHandler.amountFromSolidity(i);
            uint128 badRes;
            unchecked {
                //Should overflow
                badRes = solidityRes + (type(uint128).max / 2);
            }
            bool diverged = divergenceCheck(solidityRes, badRes);

            assertTrue(diverged);
        }
    }

    /**
     * forge-config: default.fuzz.runs = 1000
     * @dev we should never have more than 300 active proposals
     *         - that would be a cost of 1 * 1.1^300 = 2.6e+12 GCC (2.6e30 with decimals) - trillions of trillions of dollars
     */
    function testFuzz_proposalCost_shouldNotDivergeGreatly(uint256 numActiveProposals) public {
        vm.assume(numActiveProposals < 300);
        uint256 expectedCost = expectedProposalCost(numActiveProposals);
        uint256 actualCost = governance._getNominationCostForProposalCreation(numActiveProposals);
        bool diverged = divergenceCheck(uint128(expectedCost), uint128(actualCost));
        assert(!diverged);
    }

    function test_grantNomination_halfLifeShouldCorrectlyCalculate() public {
        test_grantNominations_fromGCC_shouldWork();
        vm.warp(block.timestamp + ONE_YEAR);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
    }

    function test_grantNomination_shouldRevertCallerNotGCC() public {
        vm.startPrank(SIMON);
        vm.expectRevert(IGovernance.CallerNotGCC.selector);
        governance.grantNominations(SIMON, 100);
        vm.stopPrank();
    }

    function test_grantNominations_fromGCC_shouldWork() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.retireGCC(100 ether, SIMON);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        assertEq(nominationsOfSimon, 100 ether);
        vm.stopPrank();
    }

    //----------------------------------------------------//
    //----------------  CREATE PROPOSALS -----------------//
    //----------------------------------------------------//

    function test_createGrantsProposal() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.retireGCC(100 ether, SIMON);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);

        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("test info");

        uint256 creationTimestamp = block.timestamp;

        uint256 nominationsToUse = governance.costForNewProposal();
        governance.createGrantsProposal(grantsRecipient, amount, hash, nominationsToUse);
        IGovernance.Proposal memory proposal = governance.proposals(1);
        (address recipient, uint256 amount_, bytes32 hash_) = abi.decode(proposal.data, (address, uint256, bytes32));
        assertEq(recipient, grantsRecipient);
        assertEq(amount_, amount);
        assertEq(hash_, hash);
        assertEq(governance.proposalCount(), 1);
        assertTrue(proposal.proposalType == IGovernance.ProposalType.GRANTS_PROPOSAL);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);
        vm.stopPrank();
    }

    function test_createGrantsProposal_secondOneShouldBecomeMostPopularProposal() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.retireGCC(100 ether, SIMON);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);

        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("test info");

        uint256 creationTimestamp = block.timestamp;

        uint256 nominationsToUse = governance.costForNewProposal();
        governance.createGrantsProposal(grantsRecipient, amount, hash, nominationsToUse);
        IGovernance.Proposal memory proposal = governance.proposals(1);
        (address recipient, uint256 amount_, bytes32 hash_) = abi.decode(proposal.data, (address, uint256, bytes32));
        assertEq(recipient, grantsRecipient);
        assertEq(amount_, amount);
        assertEq(hash_, hash);
        assertEq(governance.proposalCount(), 1);
        assertTrue(proposal.proposalType == IGovernance.ProposalType.GRANTS_PROPOSAL);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);

        //Create another one and make sure it becomes the most popular
        nominationsToUse = governance.costForNewProposal();
        governance.createGrantsProposal(grantsRecipient, amount, hash, nominationsToUse);
        proposal = governance.proposals(2);
        (recipient, amount_, hash_) = abi.decode(proposal.data, (address, uint256, bytes32));
        assertEq(recipient, grantsRecipient);
        assertEq(amount_, amount);
        assertEq(hash_, hash);
        assertEq(governance.proposalCount(), 2);
        assertTrue(proposal.proposalType == IGovernance.ProposalType.GRANTS_PROPOSAL);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);

        assertEq(governance.mostPopularProposal(governance.currentWeek()), 2);
        vm.stopPrank();
    }

    function test_createGrantsProposal_notEnoughNominationsShouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 0.5 ether);
        gcc.retireGCC(0.5 ether, SIMON);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);

        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("test info");

        uint256 creationTimestamp = block.timestamp;

        uint256 nominationsToUse = governance.costForNewProposal();
        vm.expectRevert(IGovernance.InsufficientNominations.selector);
        governance.createGrantsProposal(grantsRecipient, amount, hash, nominationsToUse);
    }

    function test_createGrantsProposal_nominationsGreaterThanAllowance_shouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.retireGCC(100 ether, SIMON);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);

        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("test info");

        uint256 creationTimestamp = block.timestamp;

        uint256 nominationsToUse = governance.costForNewProposal() - 1;
        vm.expectRevert(IGovernance.NominationCostGreaterThanAllowance.selector);
        governance.createGrantsProposal(grantsRecipient, amount, hash, nominationsToUse);
    }

    function test_createChangeGCARequirementsProposal() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.retireGCC(100 ether, SIMON);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);

        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("new requirements hash");

        uint256 creationTimestamp = block.timestamp;

        uint256 nominationsToUse = governance.costForNewProposal();
        governance.createChangeGCARequirementsProposal(hash, nominationsToUse);
        IGovernance.Proposal memory proposal = governance.proposals(1);
        (bytes32 hash_) = abi.decode(proposal.data, (bytes32));
        assertEq(hash_, hash);
        assertEq(governance.proposalCount(), 1);
        assertTrue(proposal.proposalType == IGovernance.ProposalType.CHANGE_GCA_REQUIREMENTS);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);
        vm.stopPrank();
    }

    function test_createChangeGCARequirementsProposal_secondOneShouldBecomeMostPopularProposal() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.retireGCC(100 ether, SIMON);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);

        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("new requirements hash");

        uint256 creationTimestamp = block.timestamp;

        uint256 nominationsToUse = governance.costForNewProposal();
        governance.createChangeGCARequirementsProposal(hash, nominationsToUse);
        IGovernance.Proposal memory proposal = governance.proposals(1);
        (bytes32 hash_) = abi.decode(proposal.data, (bytes32));
        assertEq(hash_, hash);
        assertEq(governance.proposalCount(), 1);
        assertTrue(proposal.proposalType == IGovernance.ProposalType.CHANGE_GCA_REQUIREMENTS);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);

        //Create another one and make sure it becomes the most popular
        nominationsToUse = governance.costForNewProposal();
        governance.createChangeGCARequirementsProposal(hash, nominationsToUse);
        proposal = governance.proposals(2);
        (hash_) = abi.decode(proposal.data, (bytes32));
        assertEq(hash_, hash);
        assertEq(governance.proposalCount(), 2);
        assertTrue(proposal.proposalType == IGovernance.ProposalType.CHANGE_GCA_REQUIREMENTS);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);

        assertEq(governance.mostPopularProposal(governance.currentWeek()), 2);

        vm.stopPrank();
    }

    function test_createChangeGCARequirementsProposal_notEnoughNominationsShouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 0.5 ether);
        gcc.retireGCC(0.5 ether, SIMON);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);

        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("new requirements hash");

        uint256 creationTimestamp = block.timestamp;

        uint256 nominationsToUse = governance.costForNewProposal();
        vm.expectRevert(IGovernance.InsufficientNominations.selector);
        governance.createChangeGCARequirementsProposal(hash, nominationsToUse);
    }

    function test_createChangeGCARequirementsProposal_nominationsGreaterThanAllowance_shouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.retireGCC(100 ether, SIMON);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);

        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("new requirements hash");

        uint256 creationTimestamp = block.timestamp;

        uint256 nominationsToUse = governance.costForNewProposal() - 1;
        vm.expectRevert(IGovernance.NominationCostGreaterThanAllowance.selector);
        governance.createChangeGCARequirementsProposal(hash, nominationsToUse);
    }

    function test_createRFCProposal() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.retireGCC(100 ether, SIMON);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("rfc hash");
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal();
        governance.createRFCProposal(hash, nominationsToUse);
        IGovernance.Proposal memory proposal = governance.proposals(1);
        (bytes32 hash_) = abi.decode(proposal.data, (bytes32));
        assertEq(hash_, hash);
        assertEq(governance.proposalCount(), 1);
        assertTrue(proposal.proposalType == IGovernance.ProposalType.REQUEST_FOR_COMMENT);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);
        vm.stopPrank();
    }

    function test_createRFCProposal_secondOneShouldBecomeMostPopular() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.retireGCC(100 ether, SIMON);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("rfc hash");
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal();
        governance.createRFCProposal(hash, nominationsToUse);
        IGovernance.Proposal memory proposal = governance.proposals(1);
        (bytes32 hash_) = abi.decode(proposal.data, (bytes32));
        assertEq(hash_, hash);
        assertEq(governance.proposalCount(), 1);
        assertTrue(proposal.proposalType == IGovernance.ProposalType.REQUEST_FOR_COMMENT);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);

        //Create another one and make sure it becomes the most popular
        nominationsToUse = governance.costForNewProposal();
        governance.createRFCProposal(hash, nominationsToUse);
        proposal = governance.proposals(2);
        (hash_) = abi.decode(proposal.data, (bytes32));
        assertEq(hash_, hash);
        assertEq(governance.proposalCount(), 2);
        assertTrue(proposal.proposalType == IGovernance.ProposalType.REQUEST_FOR_COMMENT);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);

        assertEq(governance.mostPopularProposal(governance.currentWeek()), 2);

        vm.stopPrank();
    }

    function test_createRFCProposal_notEnoughNominationsShouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 0.5 ether);
        gcc.retireGCC(0.5 ether, SIMON);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("rc hash");
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal();
        vm.expectRevert(IGovernance.InsufficientNominations.selector);
        governance.createRFCProposal(hash, nominationsToUse);
    }

    function test_createRFCProposal_nominationsGreaterThanAllowance_shouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.retireGCC(100 ether, SIMON);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("rfc hash");
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal() - 1;
        vm.expectRevert(IGovernance.NominationCostGreaterThanAllowance.selector);
        governance.createRFCProposal(hash, nominationsToUse);
    }

    /*
        function createGCACouncilElectionOrSlashProposal(
        address[] calldata agentsToSlash,
        address[] calldata newGCAs,
        uint256 maxNominations
    ) external
    */

    function test_createGCAElectionOrSlashProposal() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.retireGCC(100 ether, SIMON);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address[] memory agentsToSlash = new address[](1);
        agentsToSlash[0] = address(0x1);
        address[] memory newGCAs = new address[](1);
        newGCAs[0] = address(0x2);
        uint256 maxNominations = nominationsOfSimon;
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal();
        governance.createGCACouncilElectionOrSlashProposal(agentsToSlash, newGCAs, nominationsToUse);
        IGovernance.Proposal memory proposal = governance.proposals(1);
        bytes32 expectedHash = keccak256(abi.encode(agentsToSlash, newGCAs, creationTimestamp));
        bytes32 actualHash = abi.decode(proposal.data, (bytes32));
        assertEq(actualHash, expectedHash);
        assertEq(governance.proposalCount(), 1);
        assertTrue(proposal.proposalType == IGovernance.ProposalType.GCA_COUNCIL_ELECTION_OR_SLASH);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);
        vm.stopPrank();
    }

    function test_createGCAElectionOrSlashProposal_secondOneShouldBecomeMostPopular() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.retireGCC(100 ether, SIMON);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address[] memory agentsToSlash = new address[](1);
        agentsToSlash[0] = address(0x1);
        address[] memory newGCAs = new address[](1);
        newGCAs[0] = address(0x2);
        uint256 maxNominations = nominationsOfSimon;
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal();
        governance.createGCACouncilElectionOrSlashProposal(agentsToSlash, newGCAs, nominationsToUse);
        IGovernance.Proposal memory proposal = governance.proposals(1);
        bytes32 expectedHash = keccak256(abi.encode(agentsToSlash, newGCAs, creationTimestamp));
        bytes32 actualHash = abi.decode(proposal.data, (bytes32));
        assertEq(actualHash, expectedHash);
        assertEq(governance.proposalCount(), 1);
        assertTrue(proposal.proposalType == IGovernance.ProposalType.GCA_COUNCIL_ELECTION_OR_SLASH);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);

        //Create another one and make sure it becomes the most popular
        nominationsToUse = governance.costForNewProposal();
        governance.createGCACouncilElectionOrSlashProposal(agentsToSlash, newGCAs, nominationsToUse);
        proposal = governance.proposals(2);
        expectedHash = keccak256(abi.encode(agentsToSlash, newGCAs, creationTimestamp));
        actualHash = abi.decode(proposal.data, (bytes32));
        assertEq(actualHash, expectedHash);
        assertEq(governance.proposalCount(), 2);
        assertTrue(proposal.proposalType == IGovernance.ProposalType.GCA_COUNCIL_ELECTION_OR_SLASH);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);

        assertEq(governance.mostPopularProposal(governance.currentWeek()), 2);
        vm.stopPrank();
    }

    function test_createGCAElectionOrSlashProposal_notEnoughNominationsShouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 0.5 ether);
        gcc.retireGCC(0.5 ether, SIMON);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address[] memory agentsToSlash = new address[](1);
        agentsToSlash[0] = address(0x1);
        address[] memory newGCAs = new address[](1);
        newGCAs[0] = address(0x2);
        uint256 maxNominations = nominationsOfSimon;
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal();
        vm.expectRevert(IGovernance.InsufficientNominations.selector);
        governance.createGCACouncilElectionOrSlashProposal(agentsToSlash, newGCAs, nominationsToUse);
    }

    function test_createGCAElectionOrSlashProposal_nominationsGreaterThanAllowance_shouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.retireGCC(100 ether, SIMON);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address[] memory agentsToSlash = new address[](1);
        agentsToSlash[0] = address(0x1);
        address[] memory newGCAs = new address[](1);
        newGCAs[0] = address(0x2);
        uint256 maxNominations = nominationsOfSimon;
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal() - 1;
        vm.expectRevert(IGovernance.NominationCostGreaterThanAllowance.selector);
        governance.createGCACouncilElectionOrSlashProposal(agentsToSlash, newGCAs, nominationsToUse);
    }

    /*
        function createVetoCouncilElectionOrSlash(
        address oldAgent,
        address newAgent,
        bool slashOldAgent,
        uint256 maxNominations
    ) external
    */

    function test_createVetoCouncilElectionOrSlash() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.retireGCC(100 ether, SIMON);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address oldAgent = address(0x1);
        address newAgent = address(0x2);
        bool slashOldAgent = true;
        uint256 maxNominations = nominationsOfSimon;
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal();
        governance.createVetoCouncilElectionOrSlash(oldAgent, newAgent, slashOldAgent, nominationsToUse);
        IGovernance.Proposal memory proposal = governance.proposals(1);
        (address oldAgent_, address newAgent_, bool slashOldAgent_, uint256 creationTimestamp_) =
            abi.decode(proposal.data, (address, address, bool, uint256));
        assertEq(governance.proposalCount(), 1);
        assertTrue(proposal.proposalType == IGovernance.ProposalType.VETO_COUNCIL_ELECTION_OR_SLASH);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);
        assertEq(oldAgent_, oldAgent);
        assertEq(newAgent_, newAgent);
        assertEq(slashOldAgent_, slashOldAgent);
        assertEq(creationTimestamp_, creationTimestamp);
        vm.stopPrank();
    }

    function test_createVetoCouncilElectionOrSlash_secondOneShouldBecomeMostPopular() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.retireGCC(100 ether, SIMON);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address oldAgent = address(0x1);
        address newAgent = address(0x2);
        bool slashOldAgent = true;
        uint256 maxNominations = nominationsOfSimon;
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal();
        governance.createVetoCouncilElectionOrSlash(oldAgent, newAgent, slashOldAgent, nominationsToUse);
        IGovernance.Proposal memory proposal = governance.proposals(1);
        (address oldAgent_, address newAgent_, bool slashOldAgent_, uint256 creationTimestamp_) =
            abi.decode(proposal.data, (address, address, bool, uint256));
        assertEq(governance.proposalCount(), 1);
        assertTrue(proposal.proposalType == IGovernance.ProposalType.VETO_COUNCIL_ELECTION_OR_SLASH);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);
        assertEq(oldAgent_, oldAgent);
        assertEq(newAgent_, newAgent);
        assertEq(slashOldAgent_, slashOldAgent);
        assertEq(creationTimestamp_, creationTimestamp);

        //Create another one and make sure it becomes the most popular
        nominationsToUse = governance.costForNewProposal();
        governance.createVetoCouncilElectionOrSlash(oldAgent, newAgent, slashOldAgent, nominationsToUse);
        proposal = governance.proposals(2);
        (oldAgent_, newAgent_, slashOldAgent_, creationTimestamp_) =
            abi.decode(proposal.data, (address, address, bool, uint256));
        assertEq(governance.proposalCount(), 2);
        assertTrue(proposal.proposalType == IGovernance.ProposalType.VETO_COUNCIL_ELECTION_OR_SLASH);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);
        assertEq(oldAgent_, oldAgent);
        assertEq(newAgent_, newAgent);
        assertEq(slashOldAgent_, slashOldAgent);
        assertEq(creationTimestamp_, creationTimestamp);

        assertEq(governance.mostPopularProposal(governance.currentWeek()), 2);

        vm.stopPrank();
    }

    function test_createVetoCouncilElectionOrSlash_notEnoughNominationsShouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 0.5 ether);
        gcc.retireGCC(0.5 ether, SIMON);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address oldAgent = address(0x1);
        address newAgent = address(0x2);
        bool slashOldAgent = true;
        uint256 maxNominations = nominationsOfSimon;
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal();
        vm.expectRevert(IGovernance.InsufficientNominations.selector);
        governance.createVetoCouncilElectionOrSlash(oldAgent, newAgent, slashOldAgent, nominationsToUse);
    }

    function test_createVetoCouncilElectionOrSlash_nominationsGreaterThanAllowance_shouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.retireGCC(100 ether, SIMON);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address oldAgent = address(0x1);
        address newAgent = address(0x2);
        bool slashOldAgent = true;
        uint256 maxNominations = nominationsOfSimon;
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal() - 1;
        vm.expectRevert(IGovernance.NominationCostGreaterThanAllowance.selector);
        governance.createVetoCouncilElectionOrSlash(oldAgent, newAgent, slashOldAgent, nominationsToUse);

        vm.stopPrank();
    }

    /*
     function createChangeReserveCurrencyProposal(
        address currencyToRemove,
        address newReserveCurrency,
        uint256 maxNominations
    ) 
    */

    function test_createChangeReserveCurrencyProposal_secondOneShouldBecomeMostPopular() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.retireGCC(100 ether, SIMON);

        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address currencyToRemove = address(0x1);
        address newReserveCurrency = address(0x2);
        uint256 maxNominations = nominationsOfSimon;
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal();
        governance.createChangeReserveCurrencyProposal(currencyToRemove, newReserveCurrency, nominationsToUse);
        IGovernance.Proposal memory proposal = governance.proposals(1);
        (address currencyToRemove_, address newReserveCurrency_) = abi.decode(proposal.data, (address, address));
        assertEq(governance.proposalCount(), 1);
        assertTrue(proposal.proposalType == IGovernance.ProposalType.CHANGE_RESERVE_CURRENCIES);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);
        assertEq(currencyToRemove_, currencyToRemove);
        assertEq(newReserveCurrency_, newReserveCurrency);

        //Create another one and make sure it becomes the most popular
        nominationsToUse = governance.costForNewProposal();
        governance.createChangeReserveCurrencyProposal(currencyToRemove, newReserveCurrency, nominationsToUse);
        proposal = governance.proposals(2);
        (currencyToRemove_, newReserveCurrency_) = abi.decode(proposal.data, (address, address));
        assertEq(governance.proposalCount(), 2);
        assertTrue(proposal.proposalType == IGovernance.ProposalType.CHANGE_RESERVE_CURRENCIES);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);
        assertEq(currencyToRemove_, currencyToRemove);
        assertEq(newReserveCurrency_, newReserveCurrency);

        assertEq(governance.mostPopularProposal(governance.currentWeek()), 2);

        vm.stopPrank();
    }

    function test_createChangeReserveCurrencyProposal() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.retireGCC(100 ether, SIMON);

        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address currencyToRemove = address(0x1);
        address newReserveCurrency = address(0x2);
        uint256 maxNominations = nominationsOfSimon;
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal();
        governance.createChangeReserveCurrencyProposal(currencyToRemove, newReserveCurrency, nominationsToUse);
        IGovernance.Proposal memory proposal = governance.proposals(1);
        (address currencyToRemove_, address newReserveCurrency_) = abi.decode(proposal.data, (address, address));
        assertEq(governance.proposalCount(), 1);
        assertTrue(proposal.proposalType == IGovernance.ProposalType.CHANGE_RESERVE_CURRENCIES);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);
        assertEq(currencyToRemove_, currencyToRemove);
        assertEq(newReserveCurrency_, newReserveCurrency);
    }

    function test_createChangeReserveCurrencyProposal_notEnoughNominationsShouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 0.5 ether);
        gcc.retireGCC(0.5 ether, SIMON);

        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address currencyToRemove = address(0x1);
        address newReserveCurrency = address(0x2);
        uint256 maxNominations = nominationsOfSimon;
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal();
        vm.expectRevert(IGovernance.InsufficientNominations.selector);
        governance.createChangeReserveCurrencyProposal(currencyToRemove, newReserveCurrency, nominationsToUse);
    }

    function test_createChangeReserveCurrencyProposal_nominationsGreaterThanAllowance_shouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.retireGCC(100 ether, SIMON);

        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address currencyToRemove = address(0x1);
        address newReserveCurrency = address(0x2);
        uint256 maxNominations = nominationsOfSimon;
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal() - 1;
        vm.expectRevert(IGovernance.NominationCostGreaterThanAllowance.selector);
        governance.createChangeReserveCurrencyProposal(currencyToRemove, newReserveCurrency, nominationsToUse);
    }

    //----------------------------------------------------//
    //----------------  USING NOMINATIONS -----------------//
    //----------------------------------------------------//

    function test_useNominationsOnProposal() public {
        test_createChangeGCARequirementsProposal();
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.retireGCC(100 ether, SIMON);

        //I should be able to use my nominations on the proposal
        uint256 nominationsToUse = 10 ether;
        uint256 simonNominationsBefore = governance.nominationsOf(SIMON);
        uint256 numVotesBefore = governance.proposals(1).votes;
        governance.useNominationsOnProposal(1, nominationsToUse);
        uint256 simonNominationsAfter = governance.nominationsOf(SIMON);
        uint256 numVotesAfter = governance.proposals(1).votes;

        assertEq(simonNominationsBefore - nominationsToUse, simonNominationsAfter);
        assertEq(numVotesBefore + nominationsToUse, numVotesAfter);

        vm.stopPrank();
    }

    function test_useNominationsOnProposal_shouldRevertIfProposalDoesNotExist() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.retireGCC(100 ether, SIMON);

        //I should be able to use my nominations on the proposal
        uint256 nominationsToUse = 10 ether;
        vm.expectRevert(IGovernance.ProposalDoesNotExist.selector);
        governance.useNominationsOnProposal(1, nominationsToUse);
    }

    function test_useNominationsOnProposal_proposalExpiredShouldRevert() public {
        test_createChangeGCARequirementsProposal();
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.retireGCC(100 ether, SIMON);

        //I should be able to use my nominations on the proposal
        uint256 nominationsToUse = 10 ether;
        uint256 expirationTime = governance.proposals(1).expirationTimestamp;
        vm.warp(expirationTime + 1);
        vm.expectRevert(IGovernance.ProposalExpired.selector);
        governance.useNominationsOnProposal(1, nominationsToUse);
    }

    function test_useNominationsOnProposal_notEnoughNominations_shouldRevert() public {
        test_createChangeGCARequirementsProposal();
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.retireGCC(100 ether, SIMON);

        //I should be able to use my nominations on the proposal
        uint256 nominationsToUse = 1000 ether;
        vm.expectRevert(IGovernance.InsufficientNominations.selector);
        governance.useNominationsOnProposal(1, nominationsToUse);
    }

    function test_useNominationsOnProposal_shouldUpdateMostPopularProposal() public {
        /// @dev should now have 2 proposals
        test_createChangeGCARequirementsProposal_secondOneShouldBecomeMostPopularProposal();

        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.retireGCC(100 ether, SIMON);

        //I should be able to use my nominations on the proposal
        uint256 nominationsToUse = 10 ether;
        uint256 simonNominationsBefore = governance.nominationsOf(SIMON);
        uint256 numVotesBefore = governance.proposals(1).votes;
        assertTrue(numVotesBefore < governance.proposals(2).votes);
        governance.useNominationsOnProposal(1, nominationsToUse);

        uint256 simonNominationsAfter = governance.nominationsOf(SIMON);
        uint256 numVotesAfter = governance.proposals(1).votes;

        assertEq(simonNominationsBefore - nominationsToUse, simonNominationsAfter);
        assertEq(numVotesBefore + nominationsToUse, numVotesAfter);
        assertTrue(numVotesAfter > governance.proposals(2).votes);
        assertEq(governance.mostPopularProposal(governance.currentWeek()), 1);
    }

    //----------------------------------------------------//
    //----------------  RATIFY/REJECT VOTING -----------------//
    //----------------------------------------------------//

    function test_ratifyProposal() public {
        //Create one proposal
        test_createChangeGCARequirementsProposal();

        //Should be the most popular proposal now
        // and the week should be finalized
        vm.warp(block.timestamp + ONE_WEEK + 1);

        vm.startPrank(SIMON);
        glow.mint(SIMON, 100 ether);
        glow.stake(100 ether);

        governance.ratifyOrReject({weekOfMostPopularProposal: 0, trueForRatify: true, numVotes: 100 ether});

        assertEq(uint256(governance.proposalLongStakerVotes(1).ratifyVotes), 100 ether);
        assertEq(uint256(governance.proposalLongStakerVotes(1).rejectionVotes), 0);
        assertEq(governance.longStakerVotesForProposal(SIMON, 1), 100 ether);

        vm.stopPrank();
    }

    function test_rejectProposal() public {
        //Create one proposal
        test_createChangeGCARequirementsProposal();

        //Should be the most popular proposal now
        // and the week should be finalized
        vm.warp(block.timestamp + ONE_WEEK + 1);

        vm.startPrank(SIMON);
        glow.mint(SIMON, 100 ether);
        glow.stake(100 ether);

        governance.ratifyOrReject({weekOfMostPopularProposal: 0, trueForRatify: false, numVotes: 100 ether});

        assertEq(uint256(governance.proposalLongStakerVotes(1).ratifyVotes), 0);
        assertEq(uint256(governance.proposalLongStakerVotes(1).rejectionVotes), 100 ether);
        assertEq(governance.longStakerVotesForProposal(SIMON, 1), 100 ether);

        vm.stopPrank();
    }

    function test_ratifyOrReject_ratifyCurrentWeek_shouldRevert() public {
        //Create one proposal
        test_createChangeGCARequirementsProposal();

        //Should be the most popular proposal now
        // and the week should be finalized

        vm.startPrank(SIMON);
        glow.mint(SIMON, 100 ether);
        glow.stake(100 ether);

        vm.expectRevert(IGovernance.WeekNotFinalized.selector);
        governance.ratifyOrReject({weekOfMostPopularProposal: 0, trueForRatify: false, numVotes: 100 ether});

        vm.stopPrank();
    }

    function test_ratifyOrReject_ratifyFutureWeek_shouldRevert() public {
        //Create one proposal
        test_createChangeGCARequirementsProposal();

        //Should be the most popular proposal now
        // and the week should be finalized

        vm.startPrank(SIMON);
        glow.mint(SIMON, 100 ether);
        glow.stake(100 ether);

        vm.expectRevert(IGovernance.WeekNotFinalized.selector);
        governance.ratifyOrReject({weekOfMostPopularProposal: 1, trueForRatify: false, numVotes: 100 ether});

        vm.stopPrank();
    }

    function test_ratifyOrReject_mostPopularProposalNotSet_shouldRevert() public {
        //Create one proposal

        //Should be the most popular proposal now
        // and the week should be finalized
        vm.startPrank(SIMON);
        glow.mint(SIMON, 100 ether);
        glow.stake(100 ether);
        vm.warp(block.timestamp + ONE_WEEK + 1);

        vm.expectRevert(IGovernance.MostPopularProposalNotSelected.selector);
        governance.ratifyOrReject({weekOfMostPopularProposal: 0, trueForRatify: false, numVotes: 101 ether});

        vm.stopPrank();
    }

    function test_ratifyOrReject_notEnoughStakedGlow_shouldRevert() public {
        //Create one proposal
        test_createChangeGCARequirementsProposal();

        //Should be the most popular proposal now
        // and the week should be finalized
        vm.startPrank(SIMON);
        glow.mint(SIMON, 100 ether);
        glow.stake(100 ether);
        vm.warp(block.timestamp + ONE_WEEK + 1);

        vm.expectRevert(IGovernance.InsufficientRatifyOrRejectVotes.selector);
        governance.ratifyOrReject({weekOfMostPopularProposal: 0, trueForRatify: false, numVotes: 101 ether});

        vm.stopPrank();
    }

    function test_ratifyOrReject_twoStakeActions_shouldWork() public {
        //Create one proposal
        test_createChangeGCARequirementsProposal();

        //Should be the most popular proposal now
        // and the week should be finalized
        vm.startPrank(SIMON);
        glow.mint(SIMON, 100 ether);
        glow.stake(100 ether);
        vm.warp(block.timestamp + ONE_WEEK + 1);

        governance.ratifyOrReject({weekOfMostPopularProposal: 0, trueForRatify: false, numVotes: 40 ether});
        governance.ratifyOrReject({weekOfMostPopularProposal: 0, trueForRatify: false, numVotes: 60 ether});

        assertEq(uint256(governance.proposalLongStakerVotes(1).ratifyVotes), 0);
        assertEq(uint256(governance.proposalLongStakerVotes(1).rejectionVotes), 100 ether);
        assertEq(governance.longStakerVotesForProposal(SIMON, 1), 100 ether);

        vm.stopPrank();
    }

    function test_ratifyOrReject_twoStakeActions_moreThanAmountStaked_shouldRevert() public {
        //Create one proposal
        test_createChangeGCARequirementsProposal();

        //Should be the most popular proposal now
        // and the week should be finalized
        vm.startPrank(SIMON);
        glow.mint(SIMON, 100 ether);
        glow.stake(100 ether);
        vm.warp(block.timestamp + ONE_WEEK + 1);

        governance.ratifyOrReject({weekOfMostPopularProposal: 0, trueForRatify: false, numVotes: 40 ether});
        vm.expectRevert(IGovernance.InsufficientRatifyOrRejectVotes.selector);
        governance.ratifyOrReject({weekOfMostPopularProposal: 0, trueForRatify: false, numVotes: 61 ether});
        vm.stopPrank();
    }

    //-----------------  HELPERS -----------------//
    function divergenceCheck(uint128 a, uint128 b) internal returns (bool) {
        string[] memory inputsForDivergenceCheck = new string[](3);

        inputsForDivergenceCheck[0] = "./test/Governance/ffi/divergence_check";
        inputsForDivergenceCheck[1] = Strings.toString(a);
        inputsForDivergenceCheck[2] = Strings.toString(b);

        bytes memory divergenceFFI = vm.ffi(inputsForDivergenceCheck);
        bool diverged;
        assembly {
            diverged := mload(add(divergenceFFI, 0x20))
        }

        int256 diff = int256(uint256(a)) - int256(uint256(b));
        uint256 absDiff = diff < 0 ? uint256(int256(diff * -1)) : uint256(int256(diff));
        //We need to be able to account for a tiny difference of 10 wei
        //There are some differences in rust and solidity that are unavoidable
        if (absDiff < 10) {
            diverged = false;
        }

        return diverged;
    }

    function _createAccount(uint256 privateKey, uint256 amount)
        internal
        returns (address addr, uint256 signerPrivateKey)
    {
        addr = vm.addr(privateKey);
        vm.deal(addr, amount);
        signerPrivateKey = privateKey;
        return (addr, signerPrivateKey);
    }

    function expectedProposalCost(uint256 numActiveProposals) internal pure returns (uint256) {
        uint256 cost = 1e18;
        for (uint256 i; i < numActiveProposals; ++i) {
            //multiply by 1.1 each time
            cost = cost * 11 / 10;
        }
        return cost;
    }
}

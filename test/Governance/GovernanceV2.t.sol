// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import "@/testing/TestGCC.sol";
import "forge-std/console.sol";
import {IGCA} from "@/interfaces/IGCA.sol";
import {MockGCA} from "@/MinerPoolAndGCA/mock/MockGCA.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CarbonCreditDescendingPriceAuction} from "@/CarbonCreditDescendingPriceAuction.sol";
import "forge-std/StdUtils.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {TestGLOW} from "@/testing/TestGLOW.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MerkleProofLib} from "@solady/utils/MerkleProofLib.sol";
import {MockMinerPoolAndGCA} from "@/MinerPoolAndGCA/mock/MockMinerPoolAndGCA.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";
import {IMinerPool} from "@/interfaces/IMinerPool.sol";
import {BucketSubmission} from "@/MinerPoolAndGCA/BucketSubmission.sol";
import {VetoCouncil} from "@/VetoCouncil/VetoCouncil.sol";
import {MockGovernanceV2 as MockGovernance} from "@/testing/MockGovernanceV2.sol";
import {IGovernanceV2} from "@/interfaces/IGovernanceV2.sol";
import {TestGCC} from "@/testing/TestGCC.sol";
import {HalfLife} from "@/libraries/HalfLife.sol";
import {DivergenceHandler} from "./Handlers/DivergenceHandler.sol";
import {GrantsTreasury} from "@/GrantsTreasury.sol";
import {Holding, ClaimHoldingArgs, ISafetyDelay, SafetyDelay} from "@/SafetyDelay.sol";
import {UnifapV2Factory} from "@unifapv2/UnifapV2Factory.sol";
import {UnifapV2Router} from "@unifapv2/UnifapV2Router.sol";
import {WETH9} from "@/UniswapV2/contracts/test/WETH9.sol";
import {USDGUpgradeable} from "@/USDGUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UnifapV2Library} from "@unifapv2/libraries/UnifapV2Library.sol";
import {UnifapV2Pair} from "@unifapv2/UnifapV2Pair.sol";
import {USDGUpgradeableV2} from "~test/USDG/USDGUpgradeableV2.sol";

struct AccountWithPK {
    uint256 privateKey;
    address account;
}

contract GovernanceV2Test is Test {
    //--------  CONTRACTS ---------//
    UnifapV2Factory public uniswapFactory;
    WETH9 public weth;
    UnifapV2Router public uniswapRouter;
    MockMinerPoolAndGCA minerPoolAndGCA;
    TestGLOW glow;
    MockUSDC usdc;
    USDGUpgradeable usdg;
    MockUSDC grc2;
    MockGovernance governance;
    TestGCC gcc;
    DivergenceHandler divergenceHandler;
    GrantsTreasury grantsTreasury;
    SafetyDelay holdingContract;
    AccountWithPK[10] accounts;

    uint256 constant NOMINATION_DECIMALS = 12;

    //--------  ADDRESSES ---------//
    address earlyLiquidity = address(0x2);
    address vestingContract = address(0x3);
    address vetoCouncilAddress;
    VetoCouncil vetoCouncil;
    address grantsTreasuryAddress = address(0x5);
    address SIMON;
    uint256 SIMON_PRIVATE_KEY;
    address OTHER_VETO_1 = address(0x991);
    address OTHER_VETO_2 = address(0x992);
    address OTHER_VETO_3 = address(0x993);
    address OTHER_VETO_4 = address(0x994);
    address OTHER_VETO_5 = address(0x995);
    address grantsRecipient = address(0x4123141);

    address OTHER_GCA = address(0x7);
    address OTHER_GCA_2 = address(0x8);
    address OTHER_GCA_3 = address(0x9);
    address OTHER_GCA_4 = address(0x10);
    address carbonCreditAuction = address(0x11);
    address defaultAddressInWithdraw = address(0x555);
    address bidder1 = address(0x12);
    address bidder2 = address(0x13);
    address gccAddress;

    address[] startingAgents;

    //--------  CONSTANTS ---------//
    uint256 constant ONE_WEEK = 7 * uint256(1 days);
    uint256 ONE_YEAR = 365 * uint256(1 days);

    address deployer = tx.origin;

    function setUp() public {
        vm.startPrank(deployer);
        uniswapFactory = new UnifapV2Factory();
        weth = new WETH9();
        uniswapRouter = new UnifapV2Router(address(uniswapFactory));

        //Make sure we don't start at 0
        (SIMON, SIMON_PRIVATE_KEY) = _createAccount(9999, type(uint256).max);
        for (uint256 i = 0; i < 10; i++) {
            (address account, uint256 privateKey) = _createAccount(0x44444 + i, type(uint256).max);
            accounts[i] = AccountWithPK(privateKey, account);
        }
        vm.warp(10);
        usdc = new MockUSDC();
        USDGUpgradeable _usdgImplementation = new USDGUpgradeable();
        uint256 deployerNonce = vm.getNonce(deployer);
        address precomputedGovernance = computeCreateAddress(deployer, deployerNonce + 3);
        address precomputedMinerPool = computeCreateAddress(deployer, deployerNonce + 7);
        address precomputedVetoCouncil = computeCreateAddress(deployer, deployerNonce + 5);
        address precomputedTreasury = computeCreateAddress(deployer, deployerNonce + 4);
        address precomputedGCC = computeCreateAddress(deployer, deployerNonce + 2);
        gccAddress = precomputedGCC;
        usdg = USDGUpgradeable(
            address(
                new ERC1967Proxy(
                    address(_usdgImplementation),
                    abi.encodeCall(USDGUpgradeable.initialize, (address(usdc), address(precomputedGovernance)))
                )
            )
        ); //deplpoyer nonce
        glow = new TestGLOW(
            earlyLiquidity, vestingContract, precomputedMinerPool, precomputedVetoCouncil, precomputedTreasury
        ); //deployerNonce + 1

        gcc = new TestGCC(
            address(minerPoolAndGCA),
            address(precomputedGovernance),
            address(glow),
            address(usdg),
            address(uniswapRouter)
        ); //deployerNonce + 2

        governance = new MockGovernance({
            gcc: precomputedGCC,
            gca: precomputedMinerPool,
            vetoCouncil: precomputedVetoCouncil,
            grantsTreasury: precomputedTreasury,
            glw: address(glow)
        }); //deployerNonce + 3
        address[] memory temp = new address[](0);
        startingAgents.push(address(SIMON));
        startingAgents.push(OTHER_VETO_1);
        startingAgents.push(OTHER_VETO_2);
        startingAgents.push(OTHER_VETO_3);
        startingAgents.push(OTHER_VETO_4);
        startingAgents.push(OTHER_VETO_5);
        grantsTreasury = new GrantsTreasury(address(glow), address(governance)); //deployerNonce + 4
        grantsTreasuryAddress = address(grantsTreasury);
        vetoCouncil = new VetoCouncil(address(governance), address(glow), startingAgents); //deployerNonce + 5
        vetoCouncilAddress = address(vetoCouncil);
        holdingContract = new SafetyDelay(vetoCouncilAddress, precomputedMinerPool); //deployerNonce + 6

        minerPoolAndGCA = new MockMinerPoolAndGCA( //deployerNonce + 7
            temp,
            address(glow),
            address(governance),
            keccak256("requirementsHash"),
            earlyLiquidity,
            address(usdg),
            vetoCouncilAddress,
            address(holdingContract),
            precomputedGCC
        );
        assertEq(precomputedMinerPool, address(minerPoolAndGCA));
        assertEq(precomputedVetoCouncil, address(vetoCouncil));
        assertEq(precomputedTreasury, address(grantsTreasury));
        assertEq(precomputedGCC, address(gcc));
        assertEq(precomputedGovernance, address(governance));

        grc2 = new MockUSDC();
        //initialize the proxy

        divergenceHandler = new DivergenceHandler();

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = DivergenceHandler.runSims.selector;
        FuzzSelector memory fs = FuzzSelector({selectors: selectors, addr: address(divergenceHandler)});
        targetContract(address(divergenceHandler));
        vm.stopPrank();

        seedLP(500 ether, 100000000 * 1e6);
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
        uint256 actualCost = governance.getNominationCostForProposalCreation(numActiveProposals);
        bool diverged = divergenceCheck(uint128(expectedCost), uint128(actualCost));
        assert(!diverged);
    }

    function test_v2_syncProposals_shouldNotFailFirst4Weeks() public {
        //Try calling sync proposals 5 times and then loop 1 week
        for (uint256 i; i < 5; i++) {
            governance.syncProposals();
            vm.warp(block.timestamp + ONE_WEEK);
        }
    }

    function test_updateLastExpiredProposalId() public {
        test_createGrantsProposal();
        vm.warp(block.timestamp + ONE_WEEK * 16 + 1);
        governance.updateLastExpiredProposalId();
        assertEq(governance.getLastExpiredProposalId(), 1);
    }

    function test_grantNomination_halfLifeShouldCorrectlyCalculate() public {
        test_grantNominations_fromGCC_shouldWork();
        vm.warp(block.timestamp + ONE_YEAR);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
    }

    function test_grantNomination_shouldRevertCallerNotGCC() public {
        vm.startPrank(SIMON);
        vm.expectRevert(IGovernanceV2.CallerNotGCC.selector);
        governance.grantNominations(SIMON, 100);
        vm.stopPrank();
    }

    function test_grantNominations_fromGCC_shouldWork() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);
        // uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        // assertEq(nominationsOfSimon, 100 ether);
        vm.stopPrank();
    }

    //----------------------------------------------------//
    //----------------  CREATE PROPOSALS -----------------//
    //----------------------------------------------------//

    function test_createGrantsProposal() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);

        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("test info");

        uint256 creationTimestamp = block.timestamp;

        uint256 nominationsToUse = governance.costForNewProposal();
        governance.createGrantsProposal(grantsRecipient, amount, hash, nominationsToUse);
        IGovernanceV2.Proposal memory proposal = governance.proposals(1);
        (address recipient, uint256 amount_, bytes32 hash_) = abi.decode(proposal.data, (address, uint256, bytes32));
        assertEq(recipient, grantsRecipient);
        assertEq(amount_, amount);
        assertEq(hash_, hash);
        assertEq(governance.proposalCount(), 1);
        assertTrue(proposal.proposalType == IGovernanceV2.ProposalType.GRANTS_PROPOSAL);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);
        vm.stopPrank();
    }

    function test_createGrantsProposal_secondOneShouldBecomeMostPopularProposal() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);

        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("test info");

        uint256 creationTimestamp = block.timestamp;

        uint256 nominationsToUse = governance.costForNewProposal();
        governance.createGrantsProposal(grantsRecipient, amount, hash, nominationsToUse);
        IGovernanceV2.Proposal memory proposal = governance.proposals(1);
        (address recipient, uint256 amount_, bytes32 hash_) = abi.decode(proposal.data, (address, uint256, bytes32));
        assertEq(recipient, grantsRecipient);
        assertEq(amount_, amount);
        assertEq(hash_, hash);
        assertEq(governance.proposalCount(), 1);
        assertTrue(proposal.proposalType == IGovernanceV2.ProposalType.GRANTS_PROPOSAL);
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
        assertTrue(proposal.proposalType == IGovernanceV2.ProposalType.GRANTS_PROPOSAL);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);

        assertEq(governance.mostPopularProposalOfWeek(governance.currentWeek()), 2);
        vm.stopPrank();
    }

    function test_createGrantsProposal_notEnoughNominationsShouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 0.01 ether);
        gcc.commitGCC(0.0000001 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);

        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("test info");

        uint256 creationTimestamp = block.timestamp;

        uint256 nominationsToUse = governance.costForNewProposal();
        vm.expectRevert(IGovernanceV2.InsufficientNominations.selector);
        governance.createGrantsProposal(grantsRecipient, amount, hash, nominationsToUse);
    }

    function test_createGrantsProposal_nominationsGreaterThanAllowance_shouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);

        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("test info");

        uint256 creationTimestamp = block.timestamp;

        uint256 nominationsToUse = governance.costForNewProposal() - 1;
        vm.expectRevert(IGovernanceV2.NominationCostGreaterThanAllowance.selector);
        governance.createGrantsProposal(grantsRecipient, amount, hash, nominationsToUse);
    }

    function test_v2_createChangeGCARequirementsProposalSimon() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        console.log("nominationsOfSimon: %s", nominationsOfSimon);

        // address grantsRecipient = address(0x4123141);
        // uint256 amount = 10 ether; //10 gcc
        // bytes32 hash = keccak256("new requirements hash");

        // uint256 creationTimestamp = block.timestamp;

        // uint256 nominationsToUse = governance.costForNewProposal();
        // governance.createChangeGCARequirementsProposal(hash, nominationsToUse);
        // IGovernanceV2.Proposal memory proposal = governance.proposals(1);
        // (bytes32 hash_) = abi.decode(proposal.data, (bytes32));
        // assertEq(hash_, hash);
        // assertEq(governance.proposalCount(), 1);
        // assertTrue(proposal.proposalType == IGovernanceV2.ProposalType.CHANGE_GCA_REQUIREMENTS);
        // assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        // assertEq(proposal.votes, nominationsToUse);
        vm.stopPrank();
    }

    function test_v2_createChangeGCARequirementsProposal() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        console.log("nominationsOfSimon: %s", nominationsOfSimon);

        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("new requirements hash");

        uint256 creationTimestamp = block.timestamp;

        uint256 nominationsToUse = governance.costForNewProposal();
        governance.createChangeGCARequirementsProposal(hash, nominationsToUse);
        IGovernanceV2.Proposal memory proposal = governance.proposals(1);
        (bytes32 hash_) = abi.decode(proposal.data, (bytes32));
        assertEq(hash_, hash);
        assertEq(governance.proposalCount(), 1);
        assertTrue(proposal.proposalType == IGovernanceV2.ProposalType.CHANGE_GCA_REQUIREMENTS);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);
        vm.stopPrank();
    }

    function test_v2_sep_createChangeGCARequirementsProposal_secondOneShouldBecomeMostPopularProposal() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);

        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("new requirements hash");

        uint256 creationTimestamp = block.timestamp;

        uint256 nominationsToUse = governance.costForNewProposal();
        governance.createChangeGCARequirementsProposal(hash, nominationsToUse);
        IGovernanceV2.Proposal memory proposal = governance.proposals(1);
        (bytes32 hash_) = abi.decode(proposal.data, (bytes32));
        assertEq(hash_, hash);
        assertEq(governance.proposalCount(), 1);
        assertTrue(proposal.proposalType == IGovernanceV2.ProposalType.CHANGE_GCA_REQUIREMENTS);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);

        //Create another one and make sure it becomes the most popular
        nominationsToUse = governance.costForNewProposal();
        governance.createChangeGCARequirementsProposal(hash, nominationsToUse);
        proposal = governance.proposals(2);
        (hash_) = abi.decode(proposal.data, (bytes32));
        assertEq(hash_, hash);
        assertEq(governance.proposalCount(), 2);
        assertTrue(proposal.proposalType == IGovernanceV2.ProposalType.CHANGE_GCA_REQUIREMENTS);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);

        assertEq(governance.mostPopularProposalOfWeek(governance.currentWeek()), 2);

        vm.stopPrank();
    }

    function test_v2_createChangeGCARequirementsProposal_notEnoughNominationsShouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 0.001 ether);
        gcc.commitGCC(0.0000001 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        console.log("nominationsOfSimon: %s", nominationsOfSimon);

        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("new requirements hash");

        uint256 creationTimestamp = block.timestamp;

        uint256 nominationsToUse = governance.costForNewProposal();
        console.log("nominations to use = %s", nominationsToUse);
        // string memory errorMessage = string(abi.encodePacked("nominationsToUse: ", Strings.toString(nominationsToUse)));
        assertTrue(nominationsToUse > nominationsOfSimon, "nominationsToUse should be greater than nominationsOfSimon");
        vm.expectRevert(IGovernanceV2.InsufficientNominations.selector);
        governance.createChangeGCARequirementsProposal(hash, nominationsToUse);
    }

    function test_v2_createChangeGCARequirementsProposal_nominationsGreaterThanAllowance_shouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);

        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("new requirements hash");

        uint256 creationTimestamp = block.timestamp;

        uint256 nominationsToUse = governance.costForNewProposal() - 1;
        vm.expectRevert(IGovernanceV2.NominationCostGreaterThanAllowance.selector);
        governance.createChangeGCARequirementsProposal(hash, nominationsToUse);
    }

    function test_createRFCProposal() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("rfc hash");
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal();
        governance.createRFCProposal(hash, nominationsToUse);
        IGovernanceV2.Proposal memory proposal = governance.proposals(1);
        (bytes32 hash_) = abi.decode(proposal.data, (bytes32));
        assertEq(hash_, hash);
        assertEq(governance.proposalCount(), 1);
        assertTrue(proposal.proposalType == IGovernanceV2.ProposalType.REQUEST_FOR_COMMENT);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);
        vm.stopPrank();
    }

    function test_createRFCProposal_secondOneShouldBecomeMostPopular() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("rfc hash");
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal();
        governance.createRFCProposal(hash, nominationsToUse);
        IGovernanceV2.Proposal memory proposal = governance.proposals(1);
        (bytes32 hash_) = abi.decode(proposal.data, (bytes32));
        assertEq(hash_, hash);
        assertEq(governance.proposalCount(), 1);
        assertTrue(proposal.proposalType == IGovernanceV2.ProposalType.REQUEST_FOR_COMMENT);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);

        //Create another one and make sure it becomes the most popular
        nominationsToUse = governance.costForNewProposal();
        governance.createRFCProposal(hash, nominationsToUse);
        proposal = governance.proposals(2);
        (hash_) = abi.decode(proposal.data, (bytes32));
        assertEq(hash_, hash);
        assertEq(governance.proposalCount(), 2);
        assertTrue(proposal.proposalType == IGovernanceV2.ProposalType.REQUEST_FOR_COMMENT);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);

        assertEq(governance.mostPopularProposalOfWeek(governance.currentWeek()), 2);

        vm.stopPrank();
    }

    function test_createRFCProposal_notEnoughNominationsShouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 0.01 ether);
        gcc.commitGCC(0.0000001 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("rc hash");
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal();
        vm.expectRevert(IGovernanceV2.InsufficientNominations.selector);
        governance.createRFCProposal(hash, nominationsToUse);
    }

    function test_createRFCProposal_nominationsGreaterThanAllowance_shouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("rfc hash");
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal() - 1;
        vm.expectRevert(IGovernanceV2.NominationCostGreaterThanAllowance.selector);
        governance.createRFCProposal(hash, nominationsToUse);
    }

    function test_createGCAElectionOrSlashProposal() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address[] memory agentsToSlash = new address[](1);
        agentsToSlash[0] = address(0x1);
        address[] memory newGCAs = new address[](1);
        newGCAs[0] = address(0x2);
        uint256 maxNominations = nominationsOfSimon;
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal();
        governance.createGCACouncilElectionOrSlashProposal(agentsToSlash, newGCAs, nominationsToUse);
        IGovernanceV2.Proposal memory proposal = governance.proposals(1);
        bytes32 expectedHash = keccak256(abi.encode(agentsToSlash, newGCAs, creationTimestamp));
        bytes32 actualHash = abi.decode(proposal.data, (bytes32));
        assertEq(actualHash, expectedHash);
        assertEq(governance.proposalCount(), 1);
        assertTrue(proposal.proposalType == IGovernanceV2.ProposalType.GCA_COUNCIL_ELECTION_OR_SLASH);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);
        vm.stopPrank();
    }

    function test_createGCAElectionOrSlashProposal_tooManySlashes_shouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address[] memory agentsToSlash = new address[](11);
        agentsToSlash[0] = address(0x1);
        address[] memory newGCAs = new address[](1);
        newGCAs[0] = address(0x2);
        uint256 maxNominations = nominationsOfSimon;
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal();
        vm.expectRevert(IGovernanceV2.MaxSlashesInGCAElection.selector);
        governance.createGCACouncilElectionOrSlashProposal(agentsToSlash, newGCAs, nominationsToUse);
        vm.stopPrank();
    }

    function test_createGCAElectionOrSlashProposal_secondOneShouldBecomeMostPopular() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address[] memory agentsToSlash = new address[](1);
        agentsToSlash[0] = address(0x1);
        address[] memory newGCAs = new address[](1);
        newGCAs[0] = address(0x2);
        uint256 maxNominations = nominationsOfSimon;
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal();
        governance.createGCACouncilElectionOrSlashProposal(agentsToSlash, newGCAs, nominationsToUse);
        IGovernanceV2.Proposal memory proposal = governance.proposals(1);
        bytes32 expectedHash = keccak256(abi.encode(agentsToSlash, newGCAs, creationTimestamp));
        bytes32 actualHash = abi.decode(proposal.data, (bytes32));
        assertEq(actualHash, expectedHash);
        assertEq(governance.proposalCount(), 1);
        assertTrue(proposal.proposalType == IGovernanceV2.ProposalType.GCA_COUNCIL_ELECTION_OR_SLASH);
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
        assertTrue(proposal.proposalType == IGovernanceV2.ProposalType.GCA_COUNCIL_ELECTION_OR_SLASH);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);

        assertEq(governance.mostPopularProposalOfWeek(governance.currentWeek()), 2);
        vm.stopPrank();
    }

    function test_createGCAElectionOrSlashProposal_notEnoughNominationsShouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 0.01 ether);
        gcc.commitGCC(0.0000001 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address[] memory agentsToSlash = new address[](1);
        agentsToSlash[0] = address(0x1);
        address[] memory newGCAs = new address[](1);
        newGCAs[0] = address(0x2);
        uint256 maxNominations = nominationsOfSimon;
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal();
        vm.expectRevert(IGovernanceV2.InsufficientNominations.selector);
        governance.createGCACouncilElectionOrSlashProposal(agentsToSlash, newGCAs, nominationsToUse);
    }

    function test_createGCAElectionOrSlashProposal_nominationsGreaterThanAllowance_shouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address[] memory agentsToSlash = new address[](1);
        agentsToSlash[0] = address(0x1);
        address[] memory newGCAs = new address[](1);
        newGCAs[0] = address(0x2);
        uint256 maxNominations = nominationsOfSimon;
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal() - 1;
        vm.expectRevert(IGovernanceV2.NominationCostGreaterThanAllowance.selector);
        governance.createGCACouncilElectionOrSlashProposal(agentsToSlash, newGCAs, nominationsToUse);
    }

    function test_createVetoCouncilElectionOrSlash() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address oldAgent = startingAgents[2];
        address newAgent = address(0x2);
        bool slashOldAgent = true;
        uint256 maxNominations = nominationsOfSimon;
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal();
        governance.createVetoCouncilElectionOrSlash(oldAgent, newAgent, slashOldAgent, nominationsToUse);
        IGovernanceV2.Proposal memory proposal = governance.proposals(1);
        (address oldAgent_, address newAgent_, bool slashOldAgent_, uint256 creationTimestamp_) =
            abi.decode(proposal.data, (address, address, bool, uint256));
        assertEq(governance.proposalCount(), 1);
        assertTrue(proposal.proposalType == IGovernanceV2.ProposalType.VETO_COUNCIL_ELECTION_OR_SLASH);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);
        assertEq(oldAgent_, oldAgent);
        assertEq(newAgent_, newAgent);
        assertEq(slashOldAgent_, slashOldAgent);
        assertEq(creationTimestamp_, creationTimestamp);
        vm.stopPrank();
    }

    function test_createVetoCouncilElectionOrSlash_newAgentEqualsOldAgent_shouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address oldAgent = startingAgents[2];
        address newAgent = oldAgent;
        bool slashOldAgent = true;
        uint256 maxNominations = nominationsOfSimon;
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal();
        vm.expectRevert(IGovernanceV2.VetoCouncilProposalCreationOldMemberCannotEqualNewMember.selector);
        governance.createVetoCouncilElectionOrSlash(oldAgent, newAgent, slashOldAgent, nominationsToUse);
        vm.stopPrank();
    }

    function test_createVetoCouncilElectionOrSlash_secondOneShouldBecomeMostPopular() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address oldAgent = startingAgents[2];
        address newAgent = address(0x2);
        bool slashOldAgent = true;
        uint256 maxNominations = nominationsOfSimon;
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal();
        governance.createVetoCouncilElectionOrSlash(oldAgent, newAgent, slashOldAgent, nominationsToUse);
        IGovernanceV2.Proposal memory proposal = governance.proposals(1);
        (address oldAgent_, address newAgent_, bool slashOldAgent_, uint256 creationTimestamp_) =
            abi.decode(proposal.data, (address, address, bool, uint256));
        assertEq(governance.proposalCount(), 1);
        assertTrue(proposal.proposalType == IGovernanceV2.ProposalType.VETO_COUNCIL_ELECTION_OR_SLASH);
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
        assertTrue(proposal.proposalType == IGovernanceV2.ProposalType.VETO_COUNCIL_ELECTION_OR_SLASH);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);
        assertEq(oldAgent_, oldAgent);
        assertEq(newAgent_, newAgent);
        assertEq(slashOldAgent_, slashOldAgent);
        assertEq(creationTimestamp_, creationTimestamp);

        assertEq(governance.mostPopularProposalOfWeek(governance.currentWeek()), 2);

        vm.stopPrank();
    }

    function test_createVetoCouncilElectionOrSlash_notEnoughNominationsShouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 0.01 ether);
        gcc.commitGCC(0.0000001 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address oldAgent = startingAgents[2];
        address newAgent = address(0x2);
        bool slashOldAgent = true;
        uint256 maxNominations = nominationsOfSimon;
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal();
        vm.expectRevert(IGovernanceV2.InsufficientNominations.selector);
        governance.createVetoCouncilElectionOrSlash(oldAgent, newAgent, slashOldAgent, nominationsToUse);
    }

    function test_createVetoCouncilElectionOrSlash_nominationsGreaterThanAllowance_shouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address oldAgent = startingAgents[2];
        address newAgent = address(0x2);
        bool slashOldAgent = true;
        uint256 maxNominations = nominationsOfSimon;
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal() - 1;
        vm.expectRevert(IGovernanceV2.NominationCostGreaterThanAllowance.selector);
        governance.createVetoCouncilElectionOrSlash(oldAgent, newAgent, slashOldAgent, nominationsToUse);

        vm.stopPrank();
    }

    // function test_createUpgradeUSDGProposal() public {
    //     vm.startPrank(SIMON);
    //     gcc.mint(SIMON, 100 ether);
    //     gcc.commitGCC(100 ether, SIMON, 0);
    //     uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
    //     uint256 maxNominations = nominationsOfSimon;
    //     uint256 creationTimestamp = block.timestamp;
    //     uint256 nominationsToUse = governance.costForNewProposal();
    //     USDGUpgradeableV2 newUSDG = new USDGUpgradeableV2();
    //     governance.createUpgradeUSDGProposal(address(newUSDG), "", maxNominations);
    //     IGovernanceV2.Proposal memory proposal = governance.proposals(1);
    //     (address _impl, bytes memory _data) = abi.decode(proposal.data, (address, bytes));
    //     assertEq(governance.proposalCount(), 1);
    //     assertTrue(proposal.proposalType == IGovernanceV2.ProposalType.UPGRADE_USDG, "Proposal type is not correct");
    //     assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16, "Expiration timestamp is not correct");
    //     assertEq(proposal.votes, nominationsToUse);
    //     assertEq(_impl, address(newUSDG), "Impl address is not correct");
    //     assertEq(_data, "", "Data is not correct");
    //     vm.stopPrank();
    // }

    //----------------------------------------------------//
    //----------------  USING NOMINATIONS -----------------//
    //----------------------------------------------------//

    function test_useNominationsOnProposal() public {
        test_v2_createChangeGCARequirementsProposal();
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);

        //I should be able to use my nominations on the proposal
        uint256 nominationsToUse = 1e6;
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
        gcc.commitGCC(100 ether, SIMON, 0);

        //I should be able to use my nominations on the proposal
        uint256 nominationsToUse = 10 ether;
        vm.expectRevert(IGovernanceV2.ProposalDoesNotExist.selector);
        governance.useNominationsOnProposal(1, nominationsToUse);
    }

    function test_useNominationsOnProposal_proposalExpiredShouldRevert() public {
        test_v2_createChangeGCARequirementsProposal();
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);

        //I should be able to use my nominations on the proposal
        uint256 nominationsToUse = 10 ether;
        uint256 expirationTime = governance.proposals(1).expirationTimestamp;
        vm.warp(expirationTime + 1);
        vm.expectRevert(IGovernanceV2.ProposalExpired.selector);
        governance.useNominationsOnProposal(1, nominationsToUse);
    }

    function test_useNominationsOnProposal_notEnoughNominations_shouldRevert() public {
        test_v2_createChangeGCARequirementsProposal();
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);

        //I should be able to use my nominations on the proposal
        uint256 nominationsToUse = 1000 ether;
        vm.expectRevert(IGovernanceV2.InsufficientNominations.selector);
        governance.useNominationsOnProposal(1, nominationsToUse);
    }

    function test_useNominationsOnProposal_shouldUpdateMostPopularProposal() public {
        /// @dev should now have 2 proposals
        test_v2_sep_createChangeGCARequirementsProposal_secondOneShouldBecomeMostPopularProposal();

        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);

        //I should be able to use my nominations on the proposal
        uint256 nominationsToUse = 10 * (10 ** NOMINATION_DECIMALS); //(nominations in base 12)
        uint256 simonNominationsBefore = governance.nominationsOf(SIMON);
        uint256 numVotesBefore = governance.proposals(1).votes;
        assertTrue(numVotesBefore < governance.proposals(2).votes);
        governance.useNominationsOnProposal(1, nominationsToUse);

        uint256 simonNominationsAfter = governance.nominationsOf(SIMON);
        uint256 numVotesAfter = governance.proposals(1).votes;

        assertEq(simonNominationsBefore - nominationsToUse, simonNominationsAfter);
        assertEq(numVotesBefore + nominationsToUse, numVotesAfter);
        assertTrue(numVotesAfter > governance.proposals(2).votes);
        assertEq(governance.mostPopularProposalOfWeek(governance.currentWeek()), 1);
    }

    //----------------------------------------------------//
    //----------------  RATIFY/REJECT VOTING -----------------//
    //----------------------------------------------------//

    function test_ratifyProposal() public {
        //Create one proposal
        test_v2_createChangeGCARequirementsProposal();

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
        test_v2_createChangeGCARequirementsProposal();

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
        test_v2_createChangeGCARequirementsProposal();

        //Should be the most popular proposal now
        // and the week should be finalized

        vm.startPrank(SIMON);
        glow.mint(SIMON, 100 ether);
        glow.stake(100 ether);

        vm.expectRevert(IGovernanceV2.WeekMustHaveEndedToAcceptRatifyOrRejectVotes.selector);
        governance.ratifyOrReject({weekOfMostPopularProposal: 0, trueForRatify: false, numVotes: 100 ether});

        vm.stopPrank();
    }

    function test_ratifyOrReject_ratifyFutureWeek_shouldRevert() public {
        //Create one proposal
        test_v2_createChangeGCARequirementsProposal();

        //Should be the most popular proposal now
        // and the week should be finalized

        vm.startPrank(SIMON);
        glow.mint(SIMON, 100 ether);
        glow.stake(100 ether);

        vm.expectRevert(IGovernanceV2.WeekMustHaveEndedToAcceptRatifyOrRejectVotes.selector);
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

        vm.expectRevert(IGovernanceV2.MostPopularProposalNotSelected.selector);
        governance.ratifyOrReject({weekOfMostPopularProposal: 0, trueForRatify: false, numVotes: 101 ether});

        vm.stopPrank();
    }

    function test_ratifyOrReject_notEnoughStakedGlow_shouldRevert() public {
        //Create one proposal
        test_v2_createChangeGCARequirementsProposal();

        //Should be the most popular proposal now
        // and the week should be finalized
        vm.startPrank(SIMON);
        glow.mint(SIMON, 100 ether);
        glow.stake(100 ether);
        vm.warp(block.timestamp + ONE_WEEK + 1);

        vm.expectRevert(IGovernanceV2.InsufficientRatifyOrRejectVotes.selector);
        governance.ratifyOrReject({weekOfMostPopularProposal: 0, trueForRatify: false, numVotes: 101 ether});

        vm.stopPrank();
    }

    function test_ratifyOrReject_twoStakeActions_shouldWork() public {
        //Create one proposal
        test_v2_createChangeGCARequirementsProposal();

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
        test_v2_createChangeGCARequirementsProposal();

        //Should be the most popular proposal now
        // and the week should be finalized
        vm.startPrank(SIMON);
        glow.mint(SIMON, 100 ether);
        glow.stake(100 ether);
        vm.warp(block.timestamp + ONE_WEEK + 1);

        governance.ratifyOrReject({weekOfMostPopularProposal: 0, trueForRatify: false, numVotes: 40 ether});
        vm.expectRevert(IGovernanceV2.InsufficientRatifyOrRejectVotes.selector);
        governance.ratifyOrReject({weekOfMostPopularProposal: 0, trueForRatify: false, numVotes: 61 ether});
        vm.stopPrank();
    }

    function test_ratifyOrReject_vetoedProposal_shouldRevert() public {
        //Create one proposal
        test_v2_createChangeGCARequirementsProposal();

        //Should be the most popular proposal now
        // and the week should be finalized
        vm.startPrank(SIMON);
        glow.mint(SIMON, 100 ether);
        glow.stake(100 ether);
        vm.warp(block.timestamp + ONE_WEEK + 1);

        governance.vetoProposal(0, 1);

        IGovernanceV2.ProposalStatus status = governance.getProposalStatus(1);
        assertEq(uint256(status), uint256(IGovernanceV2.ProposalStatus.VETOED));
        vm.expectRevert(IGovernanceV2.ProposalAlreadyVetoed.selector);
        governance.ratifyOrReject({weekOfMostPopularProposal: 0, trueForRatify: true, numVotes: 100 ether});
        vm.stopPrank();
    }

    function test_ratifyProposal_afterVotingPeriodEnded_shouldRevert() public {
        //Create one proposal
        test_v2_createChangeGCARequirementsProposal();

        //Should be the most popular proposal now
        vm.startPrank(SIMON);
        glow.mint(SIMON, 100 ether);
        glow.stake(100 ether);
        vm.warp(block.timestamp + (ONE_WEEK * 5) + 1);

        vm.expectRevert(IGovernanceV2.RatifyOrRejectPeriodEnded.selector);
        governance.ratifyOrReject({weekOfMostPopularProposal: 0, trueForRatify: true, numVotes: 100 ether});
        vm.stopPrank();
    }

    function test_rejectProposal_afterVotingPeriodHasEnded_shouldRevert() public {
        //Create one proposal
        test_v2_createChangeGCARequirementsProposal();

        //Should be the most popular proposal now
        vm.startPrank(SIMON);
        glow.mint(SIMON, 100 ether);
        glow.stake(100 ether);
        vm.warp(block.timestamp + (ONE_WEEK * 5) + 1);

        vm.expectRevert(IGovernanceV2.RatifyOrRejectPeriodEnded.selector);
        governance.ratifyOrReject({weekOfMostPopularProposal: 0, trueForRatify: false, numVotes: 100 ether});
        vm.stopPrank();
    }

    function test_vetoProposal_callerNotVetoCouncilMember() public {
        //Create one proposal
        test_v2_createChangeGCARequirementsProposal();

        //Should be the most popular proposal now
        // and the week should be finalized
        address notSimon = address(0x124214125);
        vm.startPrank(notSimon);
        vm.warp(block.timestamp + ONE_WEEK + 1);

        vm.expectRevert(IGovernanceV2.CallerNotVetoCouncilMember.selector);
        governance.vetoProposal(0, 1);
        vm.stopPrank();
    }

    function test_vetoProposal_sameWeekNotFinalized_shouldRevert() public {
        //Create one proposal
        test_v2_createChangeGCARequirementsProposal();

        //Should be the most popular proposal now
        vm.startPrank(SIMON);
        vm.expectRevert(IGovernanceV2.WeekNotStarted.selector);
        governance.vetoProposal(0, 1);
        vm.stopPrank();
    }

    function test_vetoProposal_futureWeek_shouldRevert() public {
        vm.startPrank(SIMON);
        vm.expectRevert(IGovernanceV2.ProposalIdDoesNotMatchMostPopularProposal.selector);
        governance.vetoProposal(1, 1);
        vm.stopPrank();
    }

    function test_vetoProposal_ratifyOrRejectionPeriodEnded_shouldRevert() public {
        //Create one proposal
        test_v2_createChangeGCARequirementsProposal();

        //Should be the most popular proposal now
        vm.startPrank(SIMON);
        vm.warp(block.timestamp + (ONE_WEEK * 5) + 1);
        vm.expectRevert(IGovernanceV2.RatifyOrRejectPeriodEnded.selector);
        governance.vetoProposal(0, 1);
        vm.stopPrank();
    }

    function test_vetoProposal_VetoCouncilElection_shouldRevert() public {
        test_createVetoCouncilElectionOrSlash();
        //Should be the most popular proposal now
        vm.startPrank(SIMON);
        vm.warp(block.timestamp + ONE_WEEK);
        vm.expectRevert(IGovernanceV2.VetoCouncilElectionsCannotBeVetoed.selector);
        governance.vetoProposal(0, 1);
        vm.stopPrank();
    }

    function test_vetoProposal_GCAElection_shouldRevert() public {
        test_createGCAElectionOrSlashProposal();
        //Should be the most popular proposal now
        vm.startPrank(SIMON);
        vm.warp(block.timestamp + ONE_WEEK);
        vm.expectRevert(IGovernanceV2.GCACouncilElectionsCannotBeVetoed.selector);
        governance.vetoProposal(0, 1);
        vm.stopPrank();
    }

    function test_endorseGCAProposal() public {
        test_createGCAElectionOrSlashProposal();
        vm.startPrank(SIMON);
        vm.warp(block.timestamp + ONE_WEEK);
        governance.endorseGCAProposal(0);

        uint256 numEndorsements = governance.numEndorsementsOnWeek(0);
        assertEq(numEndorsements, 1);
        assertTrue(governance.hasEndorsedProposal(SIMON, 0));
        vm.stopPrank();
    }

    function test_endorseGCAProposal_callerNotVetoCouncilMember_shouldRevert() public {
        test_createGCAElectionOrSlashProposal();
        address notSimon;
        assembly {
            notSimon := not(sload(SIMON.slot))
            //Clean dirty bits in case
            notSimon := shr(96, shl(notSimon, 96))
        }

        vm.startPrank(notSimon);
        vm.warp(block.timestamp + ONE_WEEK);
        vm.expectRevert(IGovernanceV2.CallerNotVetoCouncilMember.selector);
        governance.endorseGCAProposal(0);
        vm.stopPrank();
    }

    function test_endorseGCAProposal_currentWeek_shouldRevert() public {
        test_createGCAElectionOrSlashProposal();
        vm.startPrank(SIMON);
        vm.warp(block.timestamp + ONE_WEEK - 1);
        vm.expectRevert(IGovernanceV2.WeekNotStarted.selector);
        governance.endorseGCAProposal(0);
    }

    function test_endorseGCAProposal_futureWeek_shouldRevert() public {
        test_createGCAElectionOrSlashProposal();
        vm.startPrank(SIMON);
        vm.expectRevert(IGovernanceV2.WeekNotStarted.selector);
        governance.endorseGCAProposal(1);
    }

    function test_endorseGCAProposal_ratifyOrRejectPeriodEnded_shouldRevert() public {
        test_createGCAElectionOrSlashProposal();
        vm.startPrank(SIMON);
        vm.warp(block.timestamp + (ONE_WEEK * 5) + 1);
        vm.expectRevert(IGovernanceV2.RatifyOrRejectPeriodEnded.selector);
        governance.endorseGCAProposal(0);
    }

    function test_endorseGCAProposal_proposalNotGCAElection_shouldRevert() public {
        test_v2_createChangeGCARequirementsProposal();
        vm.startPrank(SIMON);
        vm.warp(block.timestamp + ONE_WEEK);
        vm.expectRevert(IGovernanceV2.OnlyGCAElectionsCanBeEndorsed.selector);
        governance.endorseGCAProposal(0);
        vm.stopPrank();
    }

    function test_endorseGCAProposal_cannotEndorseSameWeekTwice() public {
        test_createGCAElectionOrSlashProposal();
        vm.startPrank(SIMON);
        vm.warp(block.timestamp + ONE_WEEK);
        governance.endorseGCAProposal(0);

        uint256 numEndorsements = governance.numEndorsementsOnWeek(0);
        assertEq(numEndorsements, 1);
        assertTrue(governance.hasEndorsedProposal(SIMON, 0));

        vm.expectRevert(IGovernanceV2.AlreadyEndorsedWeek.selector);
        governance.endorseGCAProposal(0);

        vm.stopPrank();
    }

    function test_endorseGCAProposal_cannotEndorseMoreThanMaxEndorsements_shouldRevert() public {
        test_createGCAElectionOrSlashProposal();
        vm.startPrank(SIMON);
        vm.warp(block.timestamp + ONE_WEEK);
        governance.endorseGCAProposal(0);
        vm.stopPrank();

        uint256 numEndorsements = governance.numEndorsementsOnWeek(0);
        assertEq(numEndorsements, 1);
        assertTrue(governance.hasEndorsedProposal(SIMON, 0));

        vm.startPrank(OTHER_VETO_1);
        governance.endorseGCAProposal(0);
        assertEq(governance.numEndorsementsOnWeek(0), 2);
        assertTrue(governance.hasEndorsedProposal(OTHER_VETO_1, 0));
        vm.stopPrank();

        vm.startPrank(OTHER_VETO_2);
        governance.endorseGCAProposal(0);
        assertEq(governance.numEndorsementsOnWeek(0), 3);
        assertTrue(governance.hasEndorsedProposal(OTHER_VETO_2, 0));
        vm.stopPrank();

        vm.startPrank(OTHER_VETO_3);
        governance.endorseGCAProposal(0);
        vm.stopPrank();

        assertEq(governance.numEndorsementsOnWeek(0), 4);
        assertTrue(governance.hasEndorsedProposal(OTHER_VETO_3, 0));

        vm.startPrank(OTHER_VETO_4);
        governance.endorseGCAProposal(0);
        vm.stopPrank();

        assertEq(governance.numEndorsementsOnWeek(0), 5);
        assertTrue(governance.hasEndorsedProposal(OTHER_VETO_4, 0));

        vm.startPrank(OTHER_VETO_5);
        vm.expectRevert(IGovernanceV2.MaxGCAEndorsementsReached.selector);
        governance.endorseGCAProposal(0);
        vm.stopPrank();
    }

    //----------------------------------------------------//
    //----------------  EXECUTING PROPOSALS -----------------//
    //----------------------------------------------------//

    function castLongStakedVotes(address voter, uint256 weekOfMostPopularProposal, bool trueForRatify, uint256 numVotes)
        internal
    {
        vm.startPrank(voter);
        glow.mint(voter, numVotes);
        glow.stake(numVotes);
        governance.ratifyOrReject({
            weekOfMostPopularProposal: weekOfMostPopularProposal,
            trueForRatify: trueForRatify,
            numVotes: numVotes
        });
        vm.stopPrank();
    }

    function test_executeGrantsProposal() public {
        test_createGrantsProposal();
        vm.warp(block.timestamp + ONE_WEEK + 1);
        castLongStakedVotes(SIMON, 0, true, 1);
        vm.warp(block.timestamp + ONE_WEEK * 4);
        governance.executeProposalAtWeek(0);
        uint256 balance = grantsTreasury.recipientBalance(grantsRecipient);
        assert(balance > 0);
        vm.startPrank(grantsRecipient);
        grantsTreasury.claimGrantReward();
        vm.stopPrank();
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        assertEq(lastExecutedWeek, 0);
    }

    //TODO: long stakers shouldnt be able to vote on grants proposals.
    //TODO: check all end timestamps on grants proposals
    function test_syncGrantsProposal() public {
        test_createGrantsProposal();
        vm.warp(block.timestamp + ONE_WEEK + 1);
        castLongStakedVotes(SIMON, 0, true, 1);
        vm.warp(block.timestamp + ONE_WEEK * 4);
        governance.syncProposals();
        uint256 balance = grantsTreasury.recipientBalance(grantsRecipient);
        assert(balance > 0);
        // vm.startPrank(grantsRecipient);
        // grantsTreasury.claimGrantReward();
        // vm.stopPrank();
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        console.log("last executed week = ", lastExecutedWeek);
        /**
         * [week 0] - create proposal
         *         [week 1] - ratify proposal (also no most popular proposal set since we havent created a new one)
         *         [week 2] - (also no most popular proposal set since we havent created a new one)
         *         [week 3] - (also no most popular proposal set since we havent created a new one)
         *         [week 4] - (also no most popular proposal set since we havent created a new one)
         *         Since we fast forwarded 1 week + 4 weeks, and week 1-4 are NONE proposal types,
         *         the last executed week should be 4
         */
        assertEq(lastExecutedWeek, 0);
    }

    //Grants proposals dont need to be ratified, so we can just execute them right away
    function test_syncGrantsProposal_rejection_ShouldUpdateRecipientBalance() public {
        test_createGrantsProposal();
        vm.warp(block.timestamp + ONE_WEEK + 1);
        castLongStakedVotes(SIMON, 0, false, 1);
        vm.warp(block.timestamp + ONE_WEEK * 4);
        governance.syncProposals();
        uint256 balance = grantsTreasury.recipientBalance(grantsRecipient);
        assert(balance > 0);
        // vm.startPrank(grantsRecipient);
        // grantsTreasury.claimGrantReward();
        // vm.stopPrank();
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        console.log("last executed week = ", lastExecutedWeek);
        /**
         * [week 0] - create proposal
         *         [week 1] - ratify proposal (also no most popular proposal set since we havent created a new one)
         *         [week 2] - (also no most popular proposal set since we havent created a new one)
         *         [week 3] - (also no most popular proposal set since we havent created a new one)
         *         [week 4] - (also no most popular proposal set since we havent created a new one)
         *         Since we fast forwarded 1 week + 4 weeks, and week 1-4 are NONE proposal types,
         *         the last executed week should be 4
         */
        assertEq(lastExecutedWeek, 0);
    }

    function test_syncGrantsProposal_vetoCouncilSecondProposal_ratifyPeriodNotEnded_shouldNotUpdateFutureState()
        public
    {
        test_createGrantsProposal();
        vm.warp(block.timestamp + ONE_WEEK + 1);

        createVetoCouncilElectionOrSlashProposal(SIMON, startingAgents[0], address(0x10), true);
        // console.log("last executed week = ", lastExecutedWeek);
        // castLongStakedVotes(SIMON, 0, true, 1);
        vm.warp(block.timestamp + ONE_WEEK * 4);
        governance.syncProposals();
        uint256 balance = grantsTreasury.recipientBalance(grantsRecipient);
        // console.log("balance = ", balance);
        assert(balance > 0);
        vm.startPrank(grantsRecipient);
        grantsTreasury.claimGrantReward();
        vm.stopPrank();
        /**
         * [week 0] - create proposal
         *         [week 1] - create veto council election proposal
         */
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        assertEq(lastExecutedWeek, 0);
    }

    function test_syncRFCProposal() public {
        test_createRFCProposal();
        vm.warp(block.timestamp + ONE_WEEK + 1);
        castLongStakedVotes(SIMON, 0, true, 1);
        vm.warp(block.timestamp + ONE_WEEK * 4);
        governance.syncProposals();
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        assertEq(lastExecutedWeek, 0);
    }

    function test_syncRFCProposal_vetoCouncilSecondProposal_ratifyPeriodNotEnded_shouldNotUpdateFutureState() public {
        test_createRFCProposal();
        vm.warp(block.timestamp + ONE_WEEK * 5);
        createVetoCouncilElectionOrSlashProposal(SIMON, startingAgents[0], address(0x10), true);
        //We actually don't need this syncProposals call since
        //{createVetoCouncilElectionOrSlashProposal} alreadys calls it in the {commitGCC} method
        governance.syncProposals();
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        console.log("last executed week = ", lastExecutedWeek);
        assertEq(lastExecutedWeek, 0);
    }

    function test_syncGCAElectionOrSlashProposal() public {
        test_createGCAElectionOrSlashProposal();
        vm.warp(block.timestamp + ONE_WEEK + 1);
        castLongStakedVotes(SIMON, 0, true, 1);
        vm.warp(block.timestamp + ONE_WEEK * 4);
        bytes memory data = governance.proposals(1).data;
        (bytes32 hash, bool incrementSlashNonce) = abi.decode(data, (bytes32, bool));
        governance.syncProposals();
        assertEq(minerPoolAndGCA.proposalHashes(0), hash);
        assertEq(minerPoolAndGCA.slashNonce(), incrementSlashNonce ? 1 : 0);
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        assertEq(lastExecutedWeek, 0);
    }

    function test_syncGCAElectionOrSlashProposal_rejection_ShouldNotUpdateHashOrNonce() public {
        test_createGCAElectionOrSlashProposal();
        vm.warp(block.timestamp + ONE_WEEK + 1);
        castLongStakedVotes(SIMON, 0, false, 1);
        vm.warp(block.timestamp + ONE_WEEK * 4);
        bytes memory data = governance.proposals(1).data;
        (bytes32 hash, bool incrementSlashNonce) = abi.decode(data, (bytes32, bool));
        governance.syncProposals();
        //should revert since it was not pushed
        vm.expectRevert();
        bytes32 hashInArray = minerPoolAndGCA.proposalHashes(0);
        assertEq(minerPoolAndGCA.slashNonce(), 0);
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        assertEq(lastExecutedWeek, 0);
    }

    function test_syncGCAElectionOrSlashProposal_vetoCouncilSecondProposal_ratifyPeriodNotEnded_shouldNotUpdateFutureState(
    ) public {
        test_createGCAElectionOrSlashProposal();
        vm.warp(block.timestamp + ONE_WEEK + 1);
        castLongStakedVotes(SIMON, 0, true, 1);
        createVetoCouncilElectionOrSlashProposal(SIMON, startingAgents[0], address(0x10), true);
        vm.warp(block.timestamp + ONE_WEEK * 4);
        bytes memory data = governance.proposals(1).data;
        (bytes32 hash, bool incrementSlashNonce) = abi.decode(data, (bytes32, bool));
        governance.syncProposals();
        assertEq(minerPoolAndGCA.proposalHashes(0), hash);
        assertEq(minerPoolAndGCA.slashNonce(), incrementSlashNonce ? 1 : 0);
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        assertEq(lastExecutedWeek, 0);
    }

    function test_syncVetoCouncilElectionOrSlash() public {
        test_createVetoCouncilElectionOrSlash();
        bool slashOldAgent = true;
        vm.warp(block.timestamp + ONE_WEEK + 1);
        castLongStakedVotes(SIMON, 0, true, 1);
        vm.warp(block.timestamp + ONE_WEEK * 4);
        bytes memory data = governance.proposals(1).data;
        (address oldAgent_, address newAgent_, bool slashOldAgent_) = abi.decode(data, (address, address, bool));
        governance.syncProposals();
        assert(vetoCouncil.isCouncilMember(newAgent_));
        assert(!vetoCouncil.isCouncilMember(oldAgent_));
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        assertEq(lastExecutedWeek, 0);
    }

    function test_syncVetoCouncilElectionOrSlash_rejection_shouldNotChangeVetoCouncilState() public {
        test_createVetoCouncilElectionOrSlash();
        bool slashOldAgent = true;
        vm.warp(block.timestamp + ONE_WEEK + 1);
        castLongStakedVotes(SIMON, 0, false, 1);
        vm.warp(block.timestamp + ONE_WEEK * 4);
        bytes memory data = governance.proposals(1).data;
        (address oldAgent_, address newAgent_, bool slashOldAgent_) = abi.decode(data, (address, address, bool));
        governance.syncProposals();
        assert(!vetoCouncil.isCouncilMember(newAgent_));
        assert(vetoCouncil.isCouncilMember(oldAgent_));
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        assertEq(lastExecutedWeek, 0);
    }

    function test_syncVetoCouncilElectionOrSlash_vetoCouncilSecondProposal_ratifyPeriodNotEnded_shouldNotUpdateFutureState(
    ) public {
        test_createVetoCouncilElectionOrSlash();
        bool slashOldAgent = true;
        vm.warp(block.timestamp + ONE_WEEK + 1);
        createVetoCouncilElectionOrSlashProposal(SIMON, startingAgents[0], address(0x10), true);
        castLongStakedVotes(SIMON, 0, true, 1);
        vm.warp(block.timestamp + ONE_WEEK * 4);
        bytes memory data = governance.proposals(1).data;
        (address oldAgent_, address newAgent_, bool slashOldAgent_) = abi.decode(data, (address, address, bool));
        governance.syncProposals();
        assert(vetoCouncil.isCouncilMember(newAgent_));
        assert(!vetoCouncil.isCouncilMember(oldAgent_));
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        assertEq(lastExecutedWeek, 0);
    }

    function test_v2_syncChangeGCARequirements_aaa() public {
        test_v2_createChangeGCARequirementsProposal();
        bytes32 expectedHash = keccak256("new requirements hash");
        vm.warp(block.timestamp + ONE_WEEK + 1);
        castLongStakedVotes(SIMON, 0, true, 1);
        vm.warp(block.timestamp + ONE_WEEK * 4);
        governance.syncProposals();
        assertEq(minerPoolAndGCA.requirementsHash(), expectedHash);
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        assertEq(lastExecutedWeek, 0);
        /**
         * [week 0] - create proposal
         *         [week 1] - ratify proposal (also no most popular proposal set since we havent created a new one)
         *         [week 2] - (also no most popular proposal set since we havent created a new one)
         *         [week 3] - (also no most popular proposal set since we havent created a new one)
         *         [week 4] - (also no most popular proposal set since we havent created a new one)
         *         Since we fast forwarded 1 week + 4 weeks, and week 1-4 are NONE proposal types,
         *         the last executed week should be 4
         */
    }

    function test_syncChangeGCARequirements_rejection_ShouldNotChangRequirements() public {
        test_v2_createChangeGCARequirementsProposal();
        bytes32 expectedHash = keccak256("new requirements hash");
        vm.warp(block.timestamp + ONE_WEEK + 1);
        castLongStakedVotes(SIMON, 0, false, 1);
        vm.warp(block.timestamp + ONE_WEEK * 4);
        governance.syncProposals();
        assert(minerPoolAndGCA.requirementsHash() != expectedHash);
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        assertEq(lastExecutedWeek, 0);
        /**
         * [week 0] - create proposal
         *         [week 1] - ratify proposal (also no most popular proposal set since we havent created a new one)
         *         [week 2] - (also no most popular proposal set since we havent created a new one)
         *         [week 3] - (also no most popular proposal set since we havent created a new one)
         *         [week 4] - (also no most popular proposal set since we havent created a new one)
         *         Since we fast forwarded 1 week + 4 weeks, and week 1-4 are NONE proposal types,
         *         the last executed week should be 4
         */
    }

    function test_syncChangeGCARequirements_vetoCouncilSecondProposal_ratifyPeriodNotEnded_shouldNotUpdateFutureState()
        public
    {
        test_v2_createChangeGCARequirementsProposal();
        bytes32 expectedHash = keccak256("new requirements hash");
        vm.warp(block.timestamp + ONE_WEEK + 1);
        createVetoCouncilElectionOrSlashProposal(SIMON, startingAgents[0], address(0x10), true);
        castLongStakedVotes(SIMON, 0, true, 1);
        vm.warp(block.timestamp + ONE_WEEK * 4);
        governance.syncProposals();
        assertEq(minerPoolAndGCA.requirementsHash(), expectedHash);
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        console.log("last executed week = ", lastExecutedWeek);
        assertEq(lastExecutedWeek, 0);
    }

    function createVetoCouncilElectionOrSlashProposal(
        address proposer,
        address oldAgent,
        address newAgent,
        bool slashOldAgent
    ) internal {
        vm.startPrank(proposer);
        uint256 nominationsToUse = governance.costForNewProposal();
        gcc.mint(proposer, nominationsToUse * 10);
        gcc.commitGCC(nominationsToUse * 10, proposer, 0);
        // governance.createVetoCouncilElectionOrSlash(oldAgent, newAgent, slashOldAgent, nominationsToUse);
        vm.stopPrank();
    }

    function test_executeChangeGCARequirements() public {
        test_v2_createChangeGCARequirementsProposal();
        bytes32 expectedHash = keccak256("new requirements hash");
        vm.warp(block.timestamp + ONE_WEEK + 1);
        castLongStakedVotes(SIMON, 0, true, 1);
        vm.warp(block.timestamp + ONE_WEEK * 4);
        governance.executeProposalAtWeek(0);
        assertEq(minerPoolAndGCA.requirementsHash(), expectedHash);
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        assertEq(lastExecutedWeek, 0);
    }

    function test_executeRFCProposal() public {
        test_createRFCProposal();
        vm.warp(block.timestamp + ONE_WEEK + 1);
        castLongStakedVotes(SIMON, 0, true, 1);
        vm.warp(block.timestamp + (ONE_WEEK * 4));
        governance.executeProposalAtWeek(0);
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        assertEq(lastExecutedWeek, 0);
    }

    function test_executeGCAElectionOrSlashProposal() public {
        test_createGCAElectionOrSlashProposal();
        vm.warp(block.timestamp + ONE_WEEK + 1);
        castLongStakedVotes(SIMON, 0, true, 1);
        vm.warp(block.timestamp + ONE_WEEK * 4);
        bytes memory data = governance.proposals(1).data;
        (bytes32 hash, bool incrementSlashNonce) = abi.decode(data, (bytes32, bool));
        governance.executeProposalAtWeek(0);
        assertEq(minerPoolAndGCA.proposalHashes(0), hash);
        assertEq(minerPoolAndGCA.slashNonce(), incrementSlashNonce ? 1 : 0);
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        assertEq(lastExecutedWeek, 0);
    }

    function test_executeVetoCouncilElectionOrSlash() public {
        test_createVetoCouncilElectionOrSlash();
        bool slashOldAgent = true;
        vm.warp(block.timestamp + ONE_WEEK + 1);
        castLongStakedVotes(SIMON, 0, true, 1);
        vm.warp(block.timestamp + ONE_WEEK * 4);
        bytes memory data = governance.proposals(1).data;
        (address oldAgent_, address newAgent_, bool slashOldAgent_) = abi.decode(data, (address, address, bool));
        governance.executeProposalAtWeek(0);
        assert(vetoCouncil.isCouncilMember(newAgent_));
        assert(!vetoCouncil.isCouncilMember(oldAgent_));
        // uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        // assertEq(lastExecutedWeek, 0);
    }

    // function test_executeUSDGUpgrade() public {
    //     test_createUpgradeUSDGProposal();
    //     vm.warp(block.timestamp + ONE_WEEK + 1);
    //     castLongStakedVotes(SIMON, 0, true, 1);
    //     vm.warp(block.timestamp + ONE_WEEK * 4);
    //     bytes memory data = governance.proposals(1).data;
    //     governance.executeProposalAtWeek(0);
    //     USDGUpgradeableV2 _usdgV2 = USDGUpgradeableV2(address(usdg));
    //     _usdgV2.newSetter(1212312);
    //     assertEq(_usdgV2.newVar(), 1212312);
    //     IGovernanceV2.ProposalStatus status = governance.getProposalStatus(1);
    //     assertEq(
    //         uint256(status),
    //         uint256(IGovernanceV2.ProposalStatus.EXECUTED_SUCCESSFULLY),
    //         "A good upgrade should have been successful"
    //     );
    // }

    // function test_createUpgradeUSDGProposal_withBadData_upgradeShouldFail_butNotRevert() public {
    //     vm.startPrank(SIMON);
    //     gcc.mint(SIMON, 100 ether);
    //     gcc.commitGCC(100 ether, SIMON, 0);
    //     uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
    //     uint256 maxNominations = nominationsOfSimon;
    //     uint256 creationTimestamp = block.timestamp;
    //     uint256 nominationsToUse = governance.costForNewProposal();
    //     USDGUpgradeableV2 newUSDG = new USDGUpgradeableV2();
    //     bytes memory badData = abi.encodeWithSignature("badFunction()");
    //     governance.createUpgradeUSDGProposal(address(newUSDG), badData, maxNominations);
    //     IGovernanceV2.Proposal memory proposal = governance.proposals(1);
    //     (address _impl, bytes memory _data) = abi.decode(proposal.data, (address, bytes));
    //     assertEq(governance.proposalCount(), 1);
    //     assertTrue(proposal.proposalType == IGovernanceV2.ProposalType.UPGRADE_USDG, "Proposal type is not correct");
    //     assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16, "Expiration timestamp is not correct");
    //     assertEq(proposal.votes, nominationsToUse);
    //     assertEq(_impl, address(newUSDG), "Impl address is not correct");
    //     assertEq(_data, badData, "Data is not correct");

    //     vm.warp(block.timestamp + ONE_WEEK + 1);
    //     castLongStakedVotes(SIMON, 0, true, 1);
    //     vm.warp(block.timestamp + ONE_WEEK * 4);
    //     bytes memory data = governance.proposals(1).data;
    //     governance.executeProposalAtWeek(0);

    //     IGovernanceV2.ProposalStatus status = governance.getProposalStatus(1);
    //     assertEq(
    //         uint256(status),
    //         uint256(IGovernanceV2.ProposalStatus.EXECUTED_WITH_ERROR),
    //         "The bad data should have prevented the upgrade"
    //     );
    //     vm.stopPrank();
    // }

    function test_executeGrantsProposal_rejectionShouldUpdateStateInTarget() public {
        //Grants proposals dont need to be ratified to be executed
        test_createGrantsProposal();
        vm.warp(block.timestamp + ONE_WEEK + 1);
        castLongStakedVotes(SIMON, 0, false, 1);
        vm.warp(block.timestamp + ONE_WEEK * 4);
        governance.executeProposalAtWeek(0);
        uint256 balance = grantsTreasury.recipientBalance(grantsRecipient);
        assert(balance > 0);
        vm.startPrank(grantsRecipient);
        grantsTreasury.claimGrantReward();
        vm.stopPrank();
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        assertEq(lastExecutedWeek, 0);
    }

    function test_executeChangeGCARequirements_rejectionShouldNotUpdateStateInTarget() public {
        test_v2_createChangeGCARequirementsProposal();
        bytes32 expectedHash = keccak256("new requirements hash");
        vm.warp(block.timestamp + ONE_WEEK + 1);
        castLongStakedVotes(SIMON, 0, false, 1);
        vm.warp(block.timestamp + ONE_WEEK * 4);
        governance.executeProposalAtWeek(0);
        assert(minerPoolAndGCA.requirementsHash() != expectedHash);
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        assertEq(lastExecutedWeek, 0);
    }

    /// @dev The hash is emitted so we can't check state
    function test_executeRFCProposal_shouldNotRevert() public {
        test_createRFCProposal();
        vm.warp(block.timestamp + ONE_WEEK + 1);
        castLongStakedVotes(SIMON, 0, false, 1);
        vm.warp(block.timestamp + (ONE_WEEK * 4));
        governance.executeProposalAtWeek(0);
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        assertEq(lastExecutedWeek, 0);
    }

    function test_executeGCAElectionOrSlashProposal_rejectionShouldNotUpdateStateInTarget() public {
        test_createGCAElectionOrSlashProposal();
        vm.warp(block.timestamp + ONE_WEEK + 1);
        castLongStakedVotes(SIMON, 0, false, 1);
        vm.warp(block.timestamp + ONE_WEEK * 4);
        bytes memory data = governance.proposals(1).data;
        (bytes32 hash, bool incrementSlashNonce) = abi.decode(data, (bytes32, bool));
        governance.executeProposalAtWeek(0);

        //reverts since array should be empty
        vm.expectRevert();
        bytes32 hash2 = minerPoolAndGCA.proposalHashes(0);

        assertEq(minerPoolAndGCA.slashNonce(), 0);
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        assertEq(lastExecutedWeek, 0);
    }

    function test_executeVetoCouncilElectionOrSlash_rejectionShouldNotUpdateStateInTarget() public {
        test_createVetoCouncilElectionOrSlash();
        bool slashOldAgent = true;
        vm.warp(block.timestamp + ONE_WEEK + 1);
        castLongStakedVotes(SIMON, 0, false, 1);
        vm.warp(block.timestamp + ONE_WEEK * 4);
        bytes memory data = governance.proposals(1).data;
        (address oldAgent_, address newAgent_, bool slashOldAgent_) = abi.decode(data, (address, address, bool));
        governance.executeProposalAtWeek(0);
        assert(!vetoCouncil.isCouncilMember(newAgent_));
        assert(vetoCouncil.isCouncilMember(oldAgent_));
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        assertEq(lastExecutedWeek, 0);
    }

    function test_executingSameProposalTwice_shouldNotCreateStateChanges() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);
        vm.stopPrank();
        uint256 cost = governance.costForNewProposal();
        bytes32 newRequirementsHash = keccak256("new hash");
        vm.startPrank(SIMON);
        governance.createChangeGCARequirementsProposal(newRequirementsHash, cost);
        vm.warp(block.timestamp + ONE_WEEK + 1);
        vm.stopPrank();

        castLongStakedVotes(SIMON, 0, true, 1);

        vm.startPrank(SIMON);
        //Create a new proposal that will also become the most popular and will eventually get executed
        cost = governance.costForNewProposal();
        bytes32 secondNewRequirementsHash = keccak256("second new hash");
        governance.createChangeGCARequirementsProposal(secondNewRequirementsHash, cost);
        assertEq(governance.mostPopularProposalOfWeek(governance.currentWeek()), 2);
        vm.warp(block.timestamp + ONE_WEEK + 1);
        vm.stopPrank();

        castLongStakedVotes(SIMON, 1, true, 1);

        vm.startPrank(SIMON);
        governance.useNominationsOnProposal(1, 100);
        assertEq(governance.mostPopularProposalOfWeek(governance.currentWeek()), 1);
        governance.useNominationsOnProposal(1, 100);
        // Warp forward to make sure we can execute all proposals in one go
        vm.warp(block.timestamp + ONE_WEEK + 1);
        vm.stopPrank();

        castLongStakedVotes(SIMON, 2, true, 1);
        assert(minerPoolAndGCA.requirementsHash() != newRequirementsHash);
        assert(minerPoolAndGCA.requirementsHash() != secondNewRequirementsHash);

        vm.warp(block.timestamp + ONE_WEEK * 4 + 1);
        governance.syncProposals();

        bytes32 actualRequirementsHash = minerPoolAndGCA.requirementsHash();

        //The second proposal should have been executed
        //and the third week should not have changed the requirements hash
        //since the proposal was already executed
        assert(minerPoolAndGCA.requirementsHash() == secondNewRequirementsHash);
    }

    function testFuzz_executeChangeGCARequirements_withEndorsement(uint256 numEndorsements) public {
        vm.assume(numEndorsements <= 6);
        test_createGCAElectionOrSlashProposal();
        vm.warp(block.timestamp + ONE_WEEK + 1);

        for (uint256 i; i < numEndorsements; i++) {
            vm.startPrank(startingAgents[i]);
            if (i == 5) {
                vm.expectRevert(IGovernanceV2.MaxGCAEndorsementsReached.selector);
                governance.endorseGCAProposal(0);
            } else {
                governance.endorseGCAProposal(0);
            }
            vm.stopPrank();
        }
        uint256 basePercentageRequired = 60;
        uint256 weightForEachEndorsement = 5;
        uint256 newPercentageRequired = basePercentageRequired - (numEndorsements * weightForEachEndorsement);
        if (newPercentageRequired < 35) {
            newPercentageRequired = 35;
        }

        castLongStakedVotes(SIMON, 0, true, newPercentageRequired);
        castLongStakedVotes(OTHER_VETO_1, 0, false, (100 - newPercentageRequired));
        vm.warp(block.timestamp + ONE_WEEK * 4);
        governance.executeProposalAtWeek(0);

        //Check slash nonce to make sure it went through
        uint256 slashNonce = minerPoolAndGCA.slashNonce();
        assertEq(slashNonce, 1);
    }

    function testFuzz_executeChangeGCARequirements_withEndorsement_notEnoughVotesShouldResultInNoStateChangesForTarget(
        uint256 numEndorsements
    ) public {
        vm.assume(numEndorsements <= 6);
        test_createGCAElectionOrSlashProposal();
        vm.warp(block.timestamp + ONE_WEEK + 1);

        for (uint256 i; i < numEndorsements; i++) {
            vm.startPrank(startingAgents[i]);
            if (i == 5) {
                vm.expectRevert(IGovernanceV2.MaxGCAEndorsementsReached.selector);
                governance.endorseGCAProposal(0);
            } else {
                governance.endorseGCAProposal(0);
            }
            vm.stopPrank();
        }
        uint256 basePercentageRequired = 60;
        uint256 weightForEachEndorsement = 5;
        uint256 newPercentageRequired = basePercentageRequired - (numEndorsements * weightForEachEndorsement);
        if (newPercentageRequired < 35) {
            newPercentageRequired = 35;
        }

        castLongStakedVotes(SIMON, 0, true, newPercentageRequired);
        uint256 complement = 100 - newPercentageRequired;
        castLongStakedVotes(OTHER_VETO_1, 0, false, complement + 1);
        vm.warp(block.timestamp + ONE_WEEK * 4);
        governance.executeProposalAtWeek(0);

        //Check slash nonce to make sure it went through
        uint256 slashNonce = minerPoolAndGCA.slashNonce();
        assertEq(slashNonce, 0);
    }

    function test_executeNoneProposal() public {
        vm.warp(block.timestamp + ONE_WEEK + 1);
        vm.warp(block.timestamp + ONE_WEEK * 4);
        governance.executeProposalAtWeek(0);
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        assertEq(lastExecutedWeek, 0);
    }

    //----------------------------------------------------//
    //----------------  EXECUTION REVERTS -----------------//
    //----------------------------------------------------//

    /**
     * Proposals should only revert if they are not yet ready to be executed,
     *  All proposals except RFC and None should revert if it hasn't been 4 weeks since the proposal was finalized
     *         as the most popular proposal
     */
    function test_executeRFCProposal_shouldRevert_ifNotWeekEnd() public {
        test_createRFCProposal();
        vm.warp(block.timestamp + (ONE_WEEK) - 1);
        vm.expectRevert(IGovernanceV2.RatifyOrRejectPeriodNotEnded.selector);
        governance.executeProposalAtWeek(0);
    }

    //Same rules for timestamping apply to Grants proposals, and to none
    function test_executeGrantsProposal_shouldRevert_ifNotWeekEnd() public {
        test_createGrantsProposal();
        vm.warp(block.timestamp + (ONE_WEEK) - 1);
        vm.expectRevert(IGovernanceV2.RatifyOrRejectPeriodNotEnded.selector);
        governance.executeProposalAtWeek(0);
    }

    function test_executeChangeGCARequirements_shouldRevert_ifNotWeekEnd() public {
        vm.warp(block.timestamp + (ONE_WEEK) - 1);
        vm.expectRevert(IGovernanceV2.RatifyOrRejectPeriodNotEnded.selector);
        governance.executeProposalAtWeek(0);
    }

    //All others need to wait at least 4 weeks until they can be executed
    function test_executeGCAElectionOrSlash_shouldRevert_ifNotRatifyEnd_shouldRevert() public {
        test_createGCAElectionOrSlashProposal();
        vm.warp(block.timestamp + (ONE_WEEK * 4) - 1);
        vm.expectRevert(IGovernanceV2.RatifyOrRejectPeriodNotEnded.selector);
        governance.executeProposalAtWeek(0);
    }

    function test_executeVetoCouncilElectionOrSlash_shouldRevert_ifNotRatifyEnd_shouldRevert() public {
        test_createVetoCouncilElectionOrSlash();
        vm.warp(block.timestamp + (ONE_WEEK * 4) - 1);
        vm.expectRevert(IGovernanceV2.RatifyOrRejectPeriodNotEnded.selector);
        governance.executeProposalAtWeek(0);
    }

    function test_executeGCAElectionOrSlash_shouldRevert_ifNotWeekEnd_shouldRevert() public {
        test_createGCAElectionOrSlashProposal();
        vm.warp(block.timestamp + (ONE_WEEK * 4) - 1);
        vm.expectRevert(IGovernanceV2.RatifyOrRejectPeriodNotEnded.selector);
        governance.executeProposalAtWeek(0);
    }

    function test_executeProposalsOutOfSync_shouldRevert() public {
        // test_v2_createChangeGCARequirementsProposal();
        vm.warp(block.timestamp + ONE_WEEK + 1);
        createVetoCouncilElectionOrSlashProposal(SIMON, startingAgents[0], address(0x10), true);
        // vm.warp(block.timestamp + ONE_WEEK * 4);

        // vm.expectRevert(IGovernanceV2.ProposalsMustBeExecutedSynchonously.selector);
        // governance.executeProposalAtWeek(1);
    }

    function test_executeVetoedProposal_shouldUpdateState() public {
        test_v2_createChangeGCARequirementsProposal();
        vm.warp(block.timestamp + ONE_WEEK + 1);
        createVetoCouncilElectionOrSlashProposal(SIMON, startingAgents[0], address(0x10), true);
        castLongStakedVotes(SIMON, 0, true, 1);
        vm.startPrank(startingAgents[0]);
        governance.vetoProposal(0, 1);
        vm.stopPrank();
        vm.warp(block.timestamp + ONE_WEEK * 4);

        governance.executeProposalAtWeek(0);
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        assertEq(lastExecutedWeek, 0);
    }

    function test_executeProposalWithZeroVotes_shouldUpdateState() public {
        test_createGCAElectionOrSlashProposal();
        vm.warp(block.timestamp + (ONE_WEEK * 5) + 1);
        governance.executeProposalAtWeek(0);
        assertEq(governance.getLastExecutedWeek(), 0);
    }

    /**
     * - RFC proposals
     *     - grants proposals
     *     - and none proposals
     */
    function test_executeProposal_proposalThatCanBeExecutedAfterWeekEndWithZeroVotes_shouldUpdateState() public {
        test_createRFCProposal();
        vm.startPrank(SIMON);
        uint256 nominationsToUse = governance.costForNewProposal();
        gcc.mint(SIMON, 10000 ether);
        //retiring proposals actually calls sync nominations so we need to make all propsals
        //the first week
        //the rfc proposal should be first now
        gcc.commitGCC(10000 ether, SIMON, 0);
        governance.useNominationsOnProposal(1, 1e6);
        governance.createGrantsProposal(grantsRecipient, 10, keccak256("really good use"), nominationsToUse);
        vm.warp(block.timestamp + ONE_WEEK + 1);
        governance.useNominationsOnProposal(2, 1e6);
        vm.stopPrank();
        //Create a grants proposal
        vm.warp(block.timestamp + (ONE_WEEK * 6));
        governance.executeProposalAtWeek(0);
        assertEq(governance.getLastExecutedWeek(), 0);
        governance.executeProposalAtWeek(1);
        assertEq(governance.getLastExecutedWeek(), 1);
    }

    function test_setMostPopularProposalAtWeek() public {
        //Create 2 proposals
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 10000 ether);
        gcc.commitGCC(10000 ether, SIMON, 0);
        uint256 nomCost = governance.costForNewProposal();
        governance.createChangeGCARequirementsProposal(keccak256("new requirements"), nomCost);
        nomCost = governance.costForNewProposal();
        governance.createChangeGCARequirementsProposal(keccak256("new requirements 2"), nomCost);
        nomCost = governance.costForNewProposal();
        governance.createChangeGCARequirementsProposal(keccak256("new requirements 3"), nomCost);

        vm.warp(block.timestamp + ONE_WEEK);

        //1 will be the most popular proposal for week 1,
        //set the most popular proposal to 2 even though it should be 3
        //Then we should be able to update it to 3
        governance.setMostPopularProposalForCurrentWeek(2);
        uint256 mostPopularProposal = governance.mostPopularProposalOfWeek(governance.currentWeek());
        assertEq(mostPopularProposal, 2);
        governance.setMostPopularProposalForCurrentWeek(3);
        mostPopularProposal = governance.mostPopularProposalOfWeek(governance.currentWeek());
        vm.expectRevert(IGovernanceV2.ProposalNotMostPopular.selector);
        governance.setMostPopularProposalForCurrentWeek(2);

        vm.stopPrank();
    }

    function test_setMostPopularProposalAtWeek_proposalNotCreated_shouldRevert() public {
        vm.expectRevert(IGovernanceV2.ProposalExpired.selector);
        governance.setMostPopularProposalForCurrentWeek(3);
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
        uint256 cost = 10 ** (NOMINATION_DECIMALS); //nominations are in base 12
        for (uint256 i; i < numActiveProposals; ++i) {
            //multiply by 1.1 each time
            cost = cost * 11 / 10;
        }
        return cost;
    }

    function seedLP(uint256 amountGCC, uint256 amountUSDC) public {
        address me = address(0xffffaaafffaaa);
        address pair = uniswapFactory.createPair(address(gcc), address(usdg));
        address expectedPairAddress = UnifapV2Library.pairFor(address(uniswapFactory), address(gcc), address(usdg));
        bytes32 codehash = keccak256(type(UnifapV2Pair).creationCode);
        //log the codehash
        console.logBytes32(codehash);
        assertEq(
            pair, expectedPairAddress, "Pair address not as expected copy paste the code hash into the unifap library"
        );
        vm.startPrank(me);
        usdc.mint(me, amountUSDC);
        gcc.mint(me, amountGCC);
        gcc.approve(address(uniswapRouter), amountGCC);
        usdc.approve(address(usdg), amountUSDC);
        usdg.mint(me, amountUSDC);
        usdg.approve(address(uniswapRouter), amountUSDC);
        uniswapRouter.addLiquidity(
            address(gcc), address(usdg), amountGCC, amountUSDC, amountGCC, amountUSDC, me, block.timestamp
        );
        vm.stopPrank();
    }
}

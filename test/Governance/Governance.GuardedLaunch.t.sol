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
import {TestGLOWGuardedLaunch} from "@/testing/GuardedLaunch/TestGLOW.GuardedLaunch.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MerkleProofLib} from "@solady/utils/MerkleProofLib.sol";
import {MockMinerPoolAndGCA} from "@/MinerPoolAndGCA/mock/MockMinerPoolAndGCA.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";
import {IMinerPool} from "@/interfaces/IMinerPool.sol";
import {BucketSubmission} from "@/MinerPoolAndGCA/BucketSubmission.sol";
import {VetoCouncil} from "@/VetoCouncil/VetoCouncil.sol";
import {MockGovernance} from "@/testing/MockGovernance.sol";
import {IGovernance} from "@/interfaces/IGovernance.sol";
import {TestGCCGuardedLaunch} from "@/testing/GuardedLaunch/TestGCC.GuardedLaunch.sol";
import {HalfLife} from "@/libraries/HalfLife.sol";
import {DivergenceHandler} from "./Handlers/DivergenceHandler.sol";
import {GrantsTreasury} from "@/GrantsTreasury.sol";
import {Holding, ClaimHoldingArgs, ISafetyDelay, SafetyDelay} from "@/SafetyDelay.sol";
import {UnifapV2Factory} from "@unifapv2/UnifapV2Factory.sol";
import {UnifapV2Router} from "@unifapv2/UnifapV2Router.sol";
import {WETH9} from "@/UniswapV2/contracts/test/WETH9.sol";
import {TestUSDG} from "@/testing/TestUSDG.sol";

struct AccountWithPK {
    uint256 privateKey;
    address account;
}

contract GovernanceGuardedLaunchTest is Test {
    //--------  CONTRACTS ---------//
    UnifapV2Factory public uniswapFactory;
    WETH9 public weth;
    UnifapV2Router public uniswapRouter;
    MockMinerPoolAndGCA minerPoolAndGCA;
    TestGLOWGuardedLaunch glow;
    MockUSDC usdc;
    MockUSDC grc2;
    TestUSDG usdg;
    MockGovernance governance;
    TestGCCGuardedLaunch gcc;
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
    address usdgOwner = address(0xaaa112);
    address usdcReceiver = address(0xaaa113);
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

        uint256 deployerNonce = vm.getNonce(deployer);

        address precomputeMinerPool = computeCreateAddress(deployer, deployerNonce + 8);
        address precomputeGovernance = computeCreateAddress(deployer, deployerNonce + 2);
        address precomputeGlow = computeCreateAddress(deployer, deployerNonce + 1);
        address precomputeUDSG = computeCreateAddress(deployer, deployerNonce + 4);
        address precomputeVeto = computeCreateAddress(deployer, deployerNonce + 6);
        address precomputedGrants = computeCreateAddress(deployer, deployerNonce + 5);
        address precomputeHolding = computeCreateAddress(deployer, deployerNonce + 7);
        gcc = new TestGCCGuardedLaunch({
            _gcaAndMinerPoolContract: precomputeMinerPool,
            _governance: address(precomputeGovernance),
            _glowToken: address(precomputeGlow),
            _usdg: address(precomputeUDSG),
            _vetoCouncilAddress: precomputeVeto,
            _uniswapRouter: address(uniswapRouter),
            _uniswapFactory: address(uniswapFactory)
        }); //deployerNonce

        glow = new TestGLOWGuardedLaunch(
            earlyLiquidity,
            vestingContract,
            precomputeMinerPool,
            precomputeVeto,
            precomputedGrants,
            SIMON,
            address(precomputeUDSG),
            address(uniswapFactory),
            address(gcc)
        ); //deployerNonce + 1

        governance = new MockGovernance({
            gcc: address(gcc),
            gca: address(precomputeMinerPool),
            vetoCouncil: address(precomputeVeto),
            grantsTreasury: address(precomputedGrants),
            glw: address(precomputeGlow)
        }); //deployerNonce + 2

        (SIMON, SIMON_PRIVATE_KEY) = _createAccount(9999, type(uint256).max);
        for (uint256 i = 0; i < 10; i++) {
            (address account, uint256 privateKey) = _createAccount(0x44444 + i, type(uint256).max);
            accounts[i] = AccountWithPK(privateKey, account);
        }
        vm.warp(10);
        usdc = new MockUSDC(); //deployerNonce + 3
        usdg = new TestUSDG({
            _usdc: address(usdc),
            _usdcReceiver: usdcReceiver,
            _owner: usdgOwner,
            _univ2Factory: address(uniswapFactory),
            _glow: address(glow),
            _gcc: address(gcc),
            _holdingContract: address(precomputeHolding),
            _vetoCouncilContract: precomputeVeto,
            _impactCatalyst: address(gcc.IMPACT_CATALYST())
        }); //deployerNonce + 4

        address[] memory temp = new address[](0);
        startingAgents.push(address(SIMON));
        startingAgents.push(OTHER_VETO_1);
        startingAgents.push(OTHER_VETO_2);
        startingAgents.push(OTHER_VETO_3);
        startingAgents.push(OTHER_VETO_4);
        startingAgents.push(OTHER_VETO_5);
        grantsTreasury = new GrantsTreasury(address(glow), address(governance)); //deployerNonce + 5
        grantsTreasuryAddress = address(grantsTreasury);
        vetoCouncil = new VetoCouncil(address(governance), address(glow), startingAgents); //deployerNonce + 6
        vetoCouncilAddress = address(vetoCouncil);
        holdingContract = new SafetyDelay(vetoCouncilAddress, precomputeMinerPool); //deployerNonce + 7

        minerPoolAndGCA = new MockMinerPoolAndGCA( //deployerNonce + 8
            temp,
            address(glow),
            address(governance),
            keccak256("requirementsHash"),
            earlyLiquidity,
            address(usdc),
            vetoCouncilAddress,
            address(holdingContract),
            address(gcc)
        );

        grc2 = new MockUSDC();

        vm.stopPrank();
        vm.startPrank(SIMON);

        vm.stopPrank();
        gcc.allowlistPostConstructionContracts();

        divergenceHandler = new DivergenceHandler();

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = DivergenceHandler.runSims.selector;
        FuzzSelector memory fs = FuzzSelector({selectors: selectors, addr: address(divergenceHandler)});
        targetContract(address(divergenceHandler));
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

    // function test_guarded_setContractAddresses() public {
    //     //Make sure we don't start at 0
    //     governance = new MockGovernance();
    //     (SIMON, SIMON_PRIVATE_KEY) = _createAccount(9999, type(uint256).max);
    //     vm.warp(10);
    //     usdc = new MockUSDC();
    //     glow = new TestGLOW(earlyLiquidity,vestingContract);
    //     address[] memory temp = new address[](0);
    //     grantsTreasury = new GrantsTreasury(address(glow), address(governance));
    //     grantsTreasuryAddress = address(grantsTreasury);
    //     vetoCouncil = new VetoCouncil(address(governance), address(glow),startingAgents);
    //     vetoCouncilAddress = address(vetoCouncil);
    //     holdingContract = new HoldingContract(vetoCouncilAddress);

    //     minerPoolAndGCA =
    //     new MockMinerPoolAndGCA(temp,address(glow),address(governance),keccak256("requirementsHash"),earlyLiquidity,address(usdc),vetoCouncilAddress,
    //     address(holdingContract));
    //     glow.setContractAddresses(address(minerPoolAndGCA), vetoCouncilAddress, grantsTreasuryAddress);
    //     grc2 = new MockUSDC();
    //     gcc =
    //     new TestGCC( address(minerPoolAndGCA), address(governance),address(glow),address(usdc),address(uniswapRouter));
    //     // governance.setContractAddresses(gcc, gca, vetoCouncil, grantsTreasury, glw);
    //     governance.setContractAddresses(
    //         address(gcc), address(minerPoolAndGCA), vetoCouncilAddress, grantsTreasuryAddress, address(glow)
    //     );

    //     vm.expectRevert(IGovernance.ContractsAlreadySet.selector);
    //     governance.setContractAddresses(
    //         address(gcc), address(minerPoolAndGCA), vetoCouncilAddress, grantsTreasuryAddress, address(glow)
    //     );
    // }

    // function test_guarded_setContractAddresses_noAddressCanBeZero() public {
    //     //Make sure we don't start at 0
    //     governance = new MockGovernance();
    //     (SIMON, SIMON_PRIVATE_KEY) = _createAccount(9999, type(uint256).max);
    //     vm.warp(10);
    //     usdc = new MockUSDC();
    //     glow = new TestGLOW(earlyLiquidity,vestingContract);
    //     address[] memory temp = new address[](0);
    //     grantsTreasury = new GrantsTreasury(address(glow), address(governance));
    //     grantsTreasuryAddress = address(grantsTreasury);
    //     vetoCouncil = new VetoCouncil(address(governance), address(glow),startingAgents);
    //     vetoCouncilAddress = address(vetoCouncil);
    //     holdingContract = new HoldingContract(vetoCouncilAddress);

    //     minerPoolAndGCA =
    //     new MockMinerPoolAndGCA(temp,address(glow),address(governance),keccak256("requirementsHash"),earlyLiquidity,address(usdc),vetoCouncilAddress,
    //     address(holdingContract));
    //     glow.setContractAddresses(address(minerPoolAndGCA), vetoCouncilAddress, grantsTreasuryAddress);
    //     grc2 = new MockUSDC();
    //     uniswapFactory = new UnifapV2Factory();
    //     weth = new WETH9();
    //     uniswapRouter = new UnifapV2Router(address(uniswapFactory));

    //     gcc =
    //     new TestGCC(address(minerPoolAndGCA), address(governance),address(glow),address(grc2),address(uniswapRouter));
    //     // governance.setContractAddresses(gcc, gca, vetoCouncil, grantsTreasury, glw);
    //     address _zero = address(0x0);

    //     vm.expectRevert(IGovernance.ZeroAddressNotAllowed.selector);
    //     governance.setContractAddresses(
    //         _zero, address(minerPoolAndGCA), vetoCouncilAddress, grantsTreasuryAddress, address(glow)
    //     );

    //     vm.expectRevert(IGovernance.ZeroAddressNotAllowed.selector);
    //     governance.setContractAddresses(address(gcc), _zero, vetoCouncilAddress, grantsTreasuryAddress, address(glow));

    //     vm.expectRevert(IGovernance.ZeroAddressNotAllowed.selector);
    //     governance.setContractAddresses(
    //         address(gcc), address(minerPoolAndGCA), _zero, grantsTreasuryAddress, address(glow)
    //     );

    //     vm.expectRevert(IGovernance.ZeroAddressNotAllowed.selector);
    //     governance.setContractAddresses(
    //         address(gcc), address(minerPoolAndGCA), vetoCouncilAddress, _zero, address(glow)
    //     );

    //     vm.expectRevert(IGovernance.ZeroAddressNotAllowed.selector);
    //     governance.setContractAddresses(
    //         address(gcc), address(minerPoolAndGCA), vetoCouncilAddress, grantsTreasuryAddress, _zero
    //     );

    //     vm.expectRevert(IGovernance.ZeroAddressNotAllowed.selector);
    //     governance.setContractAddresses(_zero, _zero, _zero, _zero, _zero);
    // }

    function test_guarded_updateLastExpiredProposalId() public {
        test_guarded_createGrantsProposal();
        vm.warp(block.timestamp + ONE_WEEK * 16 + 1);
        governance.updateLastExpiredProposalId();
        assertEq(governance.getLastExpiredProposalId(), 1);
    }

    function test_guarded_grantNomination_halfLifeShouldCorrectlyCalculate() public {
        test_guarded_grantNominations_fromGCC_shouldWork();
        vm.warp(block.timestamp + ONE_YEAR);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
    }

    function test_guarded_grantNomination_shouldRevertCallerNotGCC() public {
        vm.startPrank(SIMON);
        vm.expectRevert(IGovernance.CallerNotGCC.selector);
        governance.grantNominations(SIMON, 100);
        vm.stopPrank();
    }

    function test_guarded_grantNominations_fromGCC_shouldWork() public {
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

    function test_guarded_signatures_createGrantsProposal() public {
        vm.startPrank(accounts[0].account);
        gcc.mint(accounts[0].account, 100 ether);
        gcc.commitGCC(100 ether, accounts[0].account, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(accounts[0].account);

        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("test info");

        uint256 creationTimestamp = block.timestamp;

        uint256 nominationsToUse = governance.costForNewProposal();
        bytes memory data = abi.encode(grantsRecipient, amount, hash);
        uint256 signingTimestamp = block.timestamp + 10;
        bytes memory signature = signCreateProposalDigest(
            accounts[0].privateKey,
            IGovernance.ProposalType.GRANTS_PROPOSAL,
            nominationsToUse,
            governance.spendNominationsOnProposalNonce(SIMON),
            signingTimestamp,
            data
        );
        {
            uint256[] memory deadlines = new uint256[](1);
            deadlines[0] = signingTimestamp;
            address[] memory signers = new address[](1);
            signers[0] = accounts[0].account;
            bytes[] memory sigs = new bytes[](1);
            sigs[0] = signature;
            uint256[] memory noms = new uint256[](1);
            noms[0] = nominationsToUse;
            governance.createGrantsProposalSigs(grantsRecipient, amount, hash, deadlines, noms, signers, sigs);
        }

        {
            uint256 nominationsAfter = governance.nominationsOf(accounts[0].account);
            assertEq(nominationsAfter, nominationsOfSimon - nominationsToUse);
        }
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

    function test_guarded_signatures_createGrantsProposal_notEnoughNominations_shouldRevert() public {
        vm.startPrank(accounts[0].account);
        gcc.mint(accounts[0].account, 100 ether);
        gcc.commitGCC(100 ether, accounts[0].account, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(accounts[0].account);

        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("test info");

        uint256 creationTimestamp = block.timestamp;

        uint256 nominationsToUse = governance.costForNewProposal() - 1;
        bytes memory data = abi.encode(grantsRecipient, amount, hash);
        uint256 signingTimestamp = block.timestamp + 10;
        bytes memory signature = signCreateProposalDigest(
            accounts[0].privateKey,
            IGovernance.ProposalType.GRANTS_PROPOSAL,
            nominationsToUse,
            governance.spendNominationsOnProposalNonce(SIMON),
            signingTimestamp,
            data
        );
        {
            uint256[] memory deadlines = new uint256[](1);
            deadlines[0] = signingTimestamp;
            address[] memory signers = new address[](1);
            signers[0] = accounts[0].account;
            bytes[] memory sigs = new bytes[](1);
            sigs[0] = signature;
            uint256[] memory noms = new uint256[](1);
            noms[0] = nominationsToUse;
            vm.expectRevert(IGovernance.InsufficientNominations.selector);
            governance.createGrantsProposalSigs(grantsRecipient, amount, hash, deadlines, noms, signers, sigs);
        }
        vm.stopPrank();
    }

    function test_guarded_signatures_createGrantsProposal_badSignature_shouldRevert() public {
        vm.startPrank(accounts[0].account);
        gcc.mint(accounts[0].account, 100 ether);
        gcc.commitGCC(100 ether, accounts[0].account, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(accounts[0].account);

        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("test info");

        uint256 creationTimestamp = block.timestamp;

        uint256 nominationsToUse = governance.costForNewProposal() - 1;
        bytes memory data = abi.encode(grantsRecipient, amount, hash);
        uint256 signingTimestamp = block.timestamp + 10;
        bytes memory signature = signCreateProposalDigest(
            accounts[0].privateKey,
            IGovernance.ProposalType.GRANTS_PROPOSAL,
            nominationsToUse,
            governance.spendNominationsOnProposalNonce(accounts[0].account),
            signingTimestamp,
            data
        );
        {
            uint256[] memory deadlines = new uint256[](1);
            deadlines[0] = signingTimestamp;
            address[] memory signers = new address[](1);
            signers[0] = accounts[0].account;
            bytes[] memory sigs = new bytes[](1);
            sigs[0] = signature;
            uint256[] memory noms = new uint256[](1);
            noms[0] = nominationsToUse + 1;
            vm.expectRevert(IGovernance.InvalidSpendNominationsOnProposalSignature.selector);
            governance.createGrantsProposalSigs(grantsRecipient, amount, hash, deadlines, noms, signers, sigs);
        }
        vm.stopPrank();
    }

    function test_guarded_signatures_createGrantsProposal_signatureExpired_shouldRevert() public {
        vm.startPrank(accounts[0].account);
        gcc.mint(accounts[0].account, 100 ether);
        gcc.commitGCC(100 ether, accounts[0].account, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(accounts[0].account);

        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("test info");

        uint256 creationTimestamp = block.timestamp;

        uint256 nominationsToUse = governance.costForNewProposal() - 1;
        bytes memory data = abi.encode(grantsRecipient, amount, hash);
        uint256 signingTimestamp = block.timestamp - 1;
        bytes memory signature = signCreateProposalDigest(
            accounts[0].privateKey,
            IGovernance.ProposalType.GRANTS_PROPOSAL,
            nominationsToUse,
            governance.spendNominationsOnProposalNonce(SIMON),
            signingTimestamp,
            data
        );
        {
            uint256[] memory deadlines = new uint256[](1);
            deadlines[0] = signingTimestamp;
            address[] memory signers = new address[](1);
            signers[0] = accounts[0].account;
            bytes[] memory sigs = new bytes[](1);
            sigs[0] = signature;
            uint256[] memory noms = new uint256[](1);
            noms[0] = nominationsToUse;
            vm.expectRevert(IGovernance.SpendNominationsOnProposalSignatureExpired.selector);
            governance.createGrantsProposalSigs(grantsRecipient, amount, hash, deadlines, noms, signers, sigs);
        }
        vm.stopPrank();
    }

    // make sure nominations can be split across 2 different accounts
    // to create a proposal
    function test_guarded_signatures_double_createGrantsProposal() public {
        gcc.mint(accounts[0].account, 100 ether);
        gcc.mint(accounts[1].account, 100 ether);
        vm.startPrank(accounts[0].account);
        gcc.commitGCC(100 ether, accounts[0].account, 0);
        vm.stopPrank();
        vm.startPrank(accounts[1].account);
        gcc.commitGCC(100 ether, accounts[1].account, 0);
        vm.stopPrank();

        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("test info");

        uint256 creationTimestamp = block.timestamp;

        uint256 nominationsToUse = governance.costForNewProposal();
        bytes memory data = abi.encode(grantsRecipient, amount, hash);
        uint256 signingTimestamp = block.timestamp + 10;
        bytes memory signature0 = signCreateProposalDigest(
            accounts[0].privateKey,
            IGovernance.ProposalType.GRANTS_PROPOSAL,
            nominationsToUse / 2, //divide by 2 so noms are split across 2 accounts
            governance.spendNominationsOnProposalNonce(accounts[0].account),
            signingTimestamp,
            data
        );
        bytes memory signature1 = signCreateProposalDigest(
            accounts[1].privateKey,
            IGovernance.ProposalType.GRANTS_PROPOSAL,
            nominationsToUse / 2, //divide by 2 so noms are split across 2 accounts
            governance.spendNominationsOnProposalNonce(accounts[1].account),
            signingTimestamp,
            data
        );
        {
            uint256[] memory deadlines = new uint256[](2);
            deadlines[0] = signingTimestamp;
            deadlines[1] = signingTimestamp;
            address[] memory signers = new address[](2);
            signers[0] = accounts[0].account;
            signers[1] = accounts[1].account;
            bytes[] memory sigs = new bytes[](2);
            sigs[0] = signature0;
            sigs[1] = signature1;
            uint256[] memory noms = new uint256[](2);
            noms[0] = nominationsToUse / 2;
            noms[1] = nominationsToUse / 2;
            governance.createGrantsProposalSigs(grantsRecipient, amount, hash, deadlines, noms, signers, sigs);
        }
        IGovernance.Proposal memory proposal = governance.proposals(1);
        (address recipient, uint256 amount_, bytes32 hash_) = abi.decode(proposal.data, (address, uint256, bytes32));
        assertEq(recipient, grantsRecipient);
        assertEq(amount_, amount);
        assertEq(hash_, hash);
        assertEq(governance.proposalCount(), 1);
        assertTrue(proposal.proposalType == IGovernance.ProposalType.GRANTS_PROPOSAL);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);
    }

    function test_guarded_createGrantsProposal() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);

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

    function test_guarded_createGrantsProposal_secondOneShouldBecomeMostPopularProposal() public {
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

        assertEq(governance.mostPopularProposalOfWeek(governance.currentWeek()), 2);
        vm.stopPrank();
    }

    function test_guarded_createGrantsProposal_notEnoughNominationsShouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 0.01 ether);
        gcc.commitGCC(0.0000001 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);

        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("test info");

        uint256 creationTimestamp = block.timestamp;

        uint256 nominationsToUse = governance.costForNewProposal();
        vm.expectRevert(IGovernance.InsufficientNominations.selector);
        governance.createGrantsProposal(grantsRecipient, amount, hash, nominationsToUse);
    }

    function test_guarded_createGrantsProposal_nominationsGreaterThanAllowance_shouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);

        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("test info");

        uint256 creationTimestamp = block.timestamp;

        uint256 nominationsToUse = governance.costForNewProposal() - 1;
        vm.expectRevert(IGovernance.NominationCostGreaterThanAllowance.selector);
        governance.createGrantsProposal(grantsRecipient, amount, hash, nominationsToUse);
    }

    function test_guarded_signatures_createChangeGCARequirementsProposal() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);

        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("new requirements hash");

        uint256 creationTimestamp = block.timestamp;

        bytes memory data = abi.encode(hash);

        uint256 nominationsToUse = governance.costForNewProposal();
        uint256 signingTimestamp = block.timestamp + 10;
        bytes memory signature = signCreateProposalDigest(
            SIMON_PRIVATE_KEY,
            IGovernance.ProposalType.CHANGE_GCA_REQUIREMENTS,
            nominationsToUse,
            governance.spendNominationsOnProposalNonce(SIMON),
            signingTimestamp,
            data
        );
        {
            uint256[] memory deadlines = new uint256[](1);
            deadlines[0] = signingTimestamp;
            address[] memory signers = new address[](1);
            signers[0] = SIMON;
            bytes[] memory sigs = new bytes[](1);
            sigs[0] = signature;
            uint256[] memory noms = new uint256[](1);
            noms[0] = nominationsToUse;
            governance.createChangeGCARequirementsProposalSigs(hash, deadlines, noms, signers, sigs);
        }
        IGovernance.Proposal memory proposal = governance.proposals(1);
        (bytes32 hash_) = abi.decode(proposal.data, (bytes32));
        assertEq(hash_, hash);
        assertEq(governance.proposalCount(), 1);
        assertTrue(proposal.proposalType == IGovernance.ProposalType.CHANGE_GCA_REQUIREMENTS);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);
        vm.stopPrank();
    }

    function test_guarded_createChangeGCARequirementsProposalSimon() public {
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
        // IGovernance.Proposal memory proposal = governance.proposals(1);
        // (bytes32 hash_) = abi.decode(proposal.data, (bytes32));
        // assertEq(hash_, hash);
        // assertEq(governance.proposalCount(), 1);
        // assertTrue(proposal.proposalType == IGovernance.ProposalType.CHANGE_GCA_REQUIREMENTS);
        // assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        // assertEq(proposal.votes, nominationsToUse);
        vm.stopPrank();
    }

    function test_guarded_createChangeGCARequirementsProposal() public {
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
        IGovernance.Proposal memory proposal = governance.proposals(1);
        (bytes32 hash_) = abi.decode(proposal.data, (bytes32));
        assertEq(hash_, hash);
        assertEq(governance.proposalCount(), 1);
        assertTrue(proposal.proposalType == IGovernance.ProposalType.CHANGE_GCA_REQUIREMENTS);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);
        vm.stopPrank();
    }

    function test_guarded_createChangeGCARequirementsProposal_secondOneShouldBecomeMostPopularProposal() public {
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

        assertEq(governance.mostPopularProposalOfWeek(governance.currentWeek()), 2);

        vm.stopPrank();
    }

    function test_guarded_createChangeGCARequirementsProposal_notEnoughNominationsShouldRevert() public {
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
        vm.expectRevert(IGovernance.InsufficientNominations.selector);
        governance.createChangeGCARequirementsProposal(hash, nominationsToUse);
    }

    function test_guarded_createChangeGCARequirementsProposal_nominationsGreaterThanAllowance_shouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);

        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("new requirements hash");

        uint256 creationTimestamp = block.timestamp;

        uint256 nominationsToUse = governance.costForNewProposal() - 1;
        vm.expectRevert(IGovernance.NominationCostGreaterThanAllowance.selector);
        governance.createChangeGCARequirementsProposal(hash, nominationsToUse);
    }

    function test_guarded_signatures_createRFCProposal() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("rfc hash");
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal();
        uint256 signingTimestamp = block.timestamp + 10;
        bytes memory data = abi.encode(hash);

        bytes memory signature = signCreateProposalDigest(
            SIMON_PRIVATE_KEY,
            IGovernance.ProposalType.REQUEST_FOR_COMMENT,
            nominationsToUse,
            governance.spendNominationsOnProposalNonce(SIMON),
            signingTimestamp,
            data
        );

        {
            uint256[] memory deadlines = new uint256[](1);
            deadlines[0] = signingTimestamp;
            address[] memory signers = new address[](1);
            signers[0] = SIMON;
            bytes[] memory sigs = new bytes[](1);
            sigs[0] = signature;
            uint256[] memory noms = new uint256[](1);
            noms[0] = nominationsToUse;
            governance.createRFCProposalSigs(hash, deadlines, noms, signers, sigs);
        }

        IGovernance.Proposal memory proposal = governance.proposals(1);
        (bytes32 hash_) = abi.decode(proposal.data, (bytes32));
        assertEq(hash_, hash);
        assertEq(governance.proposalCount(), 1);
        assertTrue(proposal.proposalType == IGovernance.ProposalType.REQUEST_FOR_COMMENT);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);
        vm.stopPrank();
    }

    function test_guarded_createRFCProposal() public {
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
        IGovernance.Proposal memory proposal = governance.proposals(1);
        (bytes32 hash_) = abi.decode(proposal.data, (bytes32));
        assertEq(hash_, hash);
        assertEq(governance.proposalCount(), 1);
        assertTrue(proposal.proposalType == IGovernance.ProposalType.REQUEST_FOR_COMMENT);
        assertEq(proposal.expirationTimestamp, creationTimestamp + ONE_WEEK * 16);
        assertEq(proposal.votes, nominationsToUse);
        vm.stopPrank();
    }

    function test_guarded_createRFCProposal_secondOneShouldBecomeMostPopular() public {
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

        assertEq(governance.mostPopularProposalOfWeek(governance.currentWeek()), 2);

        vm.stopPrank();
    }

    function test_guarded_createRFCProposal_notEnoughNominationsShouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 0.01 ether);
        gcc.commitGCC(0.0000001 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("rc hash");
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal();
        vm.expectRevert(IGovernance.InsufficientNominations.selector);
        governance.createRFCProposal(hash, nominationsToUse);
    }

    function test_guarded_createRFCProposal_nominationsGreaterThanAllowance_shouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);
        uint256 nominationsOfSimon = governance.nominationsOf(SIMON);
        address grantsRecipient = address(0x4123141);
        uint256 amount = 10 ether; //10 gcc
        bytes32 hash = keccak256("rfc hash");
        uint256 creationTimestamp = block.timestamp;
        uint256 nominationsToUse = governance.costForNewProposal() - 1;
        vm.expectRevert(IGovernance.NominationCostGreaterThanAllowance.selector);
        governance.createRFCProposal(hash, nominationsToUse);
    }

    function test_guarded_signatures_createGCAElectionOrSlashProposal() public {
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
        bytes memory data = abi.encode(agentsToSlash, newGCAs);
        uint256 signingTimestamp = block.timestamp + 10;
        bytes memory signature = signCreateProposalDigest(
            SIMON_PRIVATE_KEY,
            IGovernance.ProposalType.GRANTS_PROPOSAL,
            nominationsToUse,
            governance.spendNominationsOnProposalNonce(SIMON),
            signingTimestamp,
            data
        );
        {
            uint256[] memory deadlines = new uint256[](1);
            deadlines[0] = signingTimestamp;
            address[] memory signers = new address[](1);
            signers[0] = SIMON;
            bytes[] memory sigs = new bytes[](1);
            sigs[0] = signature;
            uint256[] memory noms = new uint256[](1);
            noms[0] = nominationsToUse;
            governance.createGCACouncilElectionOrSlashProposal(agentsToSlash, newGCAs, nominationsToUse);
        }
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

    function test_guarded_createGCAElectionOrSlashProposal() public {
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

    function test_guarded_createGCAElectionOrSlashProposal_tooManySlashes_shouldRevert() public {
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
        vm.expectRevert(IGovernance.MaxSlashesInGCAElection.selector);
        governance.createGCACouncilElectionOrSlashProposal(agentsToSlash, newGCAs, nominationsToUse);
        vm.stopPrank();
    }

    function test_guarded_createGCAElectionOrSlashProposal_secondOneShouldBecomeMostPopular() public {
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

        assertEq(governance.mostPopularProposalOfWeek(governance.currentWeek()), 2);
        vm.stopPrank();
    }

    function test_guarded_createGCAElectionOrSlashProposal_notEnoughNominationsShouldRevert() public {
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
        vm.expectRevert(IGovernance.InsufficientNominations.selector);
        governance.createGCACouncilElectionOrSlashProposal(agentsToSlash, newGCAs, nominationsToUse);
    }

    function test_guarded_createGCAElectionOrSlashProposal_nominationsGreaterThanAllowance_shouldRevert() public {
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

    function test_guarded_signatures_createVetoCouncilElectionOrSlash() public {
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

        bytes memory data = abi.encode(oldAgent, newAgent, slashOldAgent);
        uint256 signingTimestamp = block.timestamp + 10;
        bytes memory signature = signCreateProposalDigest(
            SIMON_PRIVATE_KEY,
            IGovernance.ProposalType.VETO_COUNCIL_ELECTION_OR_SLASH,
            nominationsToUse,
            governance.spendNominationsOnProposalNonce(SIMON),
            signingTimestamp,
            data
        );
        {
            uint256[] memory deadlines = new uint256[](1);
            deadlines[0] = signingTimestamp;
            address[] memory signers = new address[](1);
            signers[0] = SIMON;
            bytes[] memory sigs = new bytes[](1);
            sigs[0] = signature;
            uint256[] memory noms = new uint256[](1);
            noms[0] = nominationsToUse;
            governance.createVetoCouncilElectionOrSlashSigs(
                oldAgent, newAgent, slashOldAgent, deadlines, noms, signers, sigs
            );
        }
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

    function test_guarded_createVetoCouncilElectionOrSlash() public {
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

    function test_guarded_createVetoCouncilElectionOrSlash_newAgentEqualsOldAgent_shouldRevert() public {
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
        vm.expectRevert(IGovernance.VetoCouncilProposalCreationOldMemberCannotEqualNewMember.selector);
        governance.createVetoCouncilElectionOrSlash(oldAgent, newAgent, slashOldAgent, nominationsToUse);
        vm.stopPrank();
    }

    function test_guarded_createVetoCouncilElectionOrSlash_secondOneShouldBecomeMostPopular() public {
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

        assertEq(governance.mostPopularProposalOfWeek(governance.currentWeek()), 2);

        vm.stopPrank();
    }

    function test_guarded_createVetoCouncilElectionOrSlash_notEnoughNominationsShouldRevert() public {
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
        vm.expectRevert(IGovernance.InsufficientNominations.selector);
        governance.createVetoCouncilElectionOrSlash(oldAgent, newAgent, slashOldAgent, nominationsToUse);
    }

    function test_guarded_createVetoCouncilElectionOrSlash_nominationsGreaterThanAllowance_shouldRevert() public {
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
        vm.expectRevert(IGovernance.NominationCostGreaterThanAllowance.selector);
        governance.createVetoCouncilElectionOrSlash(oldAgent, newAgent, slashOldAgent, nominationsToUse);

        vm.stopPrank();
    }

    //----------------------------------------------------//
    //----------------  USING NOMINATIONS -----------------//
    //----------------------------------------------------//

    function test_guarded_useNominationsOnProposal() public {
        test_guarded_createChangeGCARequirementsProposal();
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

    function test_guarded_useNominationsOnProposal_shouldRevertIfProposalDoesNotExist() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);

        //I should be able to use my nominations on the proposal
        uint256 nominationsToUse = 10 ether;
        vm.expectRevert(IGovernance.ProposalDoesNotExist.selector);
        governance.useNominationsOnProposal(1, nominationsToUse);
    }

    function test_guarded_useNominationsOnProposal_proposalExpiredShouldRevert() public {
        test_guarded_createChangeGCARequirementsProposal();
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);

        //I should be able to use my nominations on the proposal
        uint256 nominationsToUse = 10 ether;
        uint256 expirationTime = governance.proposals(1).expirationTimestamp;
        vm.warp(expirationTime + 1);
        vm.expectRevert(IGovernance.ProposalExpired.selector);
        governance.useNominationsOnProposal(1, nominationsToUse);
    }

    function test_guarded_useNominationsOnProposal_notEnoughNominations_shouldRevert() public {
        test_guarded_createChangeGCARequirementsProposal();
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);

        //I should be able to use my nominations on the proposal
        uint256 nominationsToUse = 1000 ether;
        vm.expectRevert(IGovernance.InsufficientNominations.selector);
        governance.useNominationsOnProposal(1, nominationsToUse);
    }

    function test_guarded_useNominationsOnProposal_shouldUpdateMostPopularProposal() public {
        /// @dev should now have 2 proposals
        test_guarded_createChangeGCARequirementsProposal_secondOneShouldBecomeMostPopularProposal();

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

    function test_guarded_ratifyProposal() public {
        //Create one proposal
        test_guarded_createChangeGCARequirementsProposal();

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

    function test_guarded_rejectProposal() public {
        //Create one proposal
        test_guarded_createChangeGCARequirementsProposal();

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

    function test_guarded_ratifyOrReject_ratifyCurrentWeek_shouldRevert() public {
        //Create one proposal
        test_guarded_createChangeGCARequirementsProposal();

        //Should be the most popular proposal now
        // and the week should be finalized

        vm.startPrank(SIMON);
        glow.mint(SIMON, 100 ether);
        glow.stake(100 ether);

        vm.expectRevert(IGovernance.WeekMustHaveEndedToAcceptRatifyOrRejectVotes.selector);
        governance.ratifyOrReject({weekOfMostPopularProposal: 0, trueForRatify: false, numVotes: 100 ether});

        vm.stopPrank();
    }

    function test_guarded_ratifyOrReject_ratifyFutureWeek_shouldRevert() public {
        //Create one proposal
        test_guarded_createChangeGCARequirementsProposal();

        //Should be the most popular proposal now
        // and the week should be finalized

        vm.startPrank(SIMON);
        glow.mint(SIMON, 100 ether);
        glow.stake(100 ether);

        vm.expectRevert(IGovernance.WeekMustHaveEndedToAcceptRatifyOrRejectVotes.selector);
        governance.ratifyOrReject({weekOfMostPopularProposal: 1, trueForRatify: false, numVotes: 100 ether});

        vm.stopPrank();
    }

    function test_guarded_ratifyOrReject_mostPopularProposalNotSet_shouldRevert() public {
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

    function test_guarded_ratifyOrReject_notEnoughStakedGlow_shouldRevert() public {
        //Create one proposal
        test_guarded_createChangeGCARequirementsProposal();

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

    function test_guarded_ratifyOrReject_twoStakeActions_shouldWork() public {
        //Create one proposal
        test_guarded_createChangeGCARequirementsProposal();

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

    function test_guarded_ratifyOrReject_twoStakeActions_moreThanAmountStaked_shouldRevert() public {
        //Create one proposal
        test_guarded_createChangeGCARequirementsProposal();

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

    function test_guarded_ratifyOrReject_vetoedProposal_shouldRevert() public {
        //Create one proposal
        test_guarded_createChangeGCARequirementsProposal();

        //Should be the most popular proposal now
        // and the week should be finalized
        vm.startPrank(SIMON);
        glow.mint(SIMON, 100 ether);
        glow.stake(100 ether);
        vm.warp(block.timestamp + ONE_WEEK + 1);

        governance.vetoProposal(0, 1);

        IGovernance.ProposalStatus status = governance.getProposalStatus(1);
        assertEq(uint256(status), uint256(IGovernance.ProposalStatus.VETOED));
        vm.expectRevert(IGovernance.ProposalAlreadyVetoed.selector);
        governance.ratifyOrReject({weekOfMostPopularProposal: 0, trueForRatify: true, numVotes: 100 ether});
        vm.stopPrank();
    }

    function test_guarded_ratifyProposal_afterVotingPeriodEnded_shouldRevert() public {
        //Create one proposal
        test_guarded_createChangeGCARequirementsProposal();

        //Should be the most popular proposal now
        vm.startPrank(SIMON);
        glow.mint(SIMON, 100 ether);
        glow.stake(100 ether);
        vm.warp(block.timestamp + (ONE_WEEK * 5) + 1);

        vm.expectRevert(IGovernance.RatifyOrRejectPeriodEnded.selector);
        governance.ratifyOrReject({weekOfMostPopularProposal: 0, trueForRatify: true, numVotes: 100 ether});
        vm.stopPrank();
    }

    function test_guarded_rejectProposal_afterVotingPeriodHasEnded_shouldRevert() public {
        //Create one proposal
        test_guarded_createChangeGCARequirementsProposal();

        //Should be the most popular proposal now
        vm.startPrank(SIMON);
        glow.mint(SIMON, 100 ether);
        glow.stake(100 ether);
        vm.warp(block.timestamp + (ONE_WEEK * 5) + 1);

        vm.expectRevert(IGovernance.RatifyOrRejectPeriodEnded.selector);
        governance.ratifyOrReject({weekOfMostPopularProposal: 0, trueForRatify: false, numVotes: 100 ether});
        vm.stopPrank();
    }

    function test_guarded_vetoProposal_callerNotVetoCouncilMember() public {
        //Create one proposal
        test_guarded_createChangeGCARequirementsProposal();

        //Should be the most popular proposal now
        // and the week should be finalized
        address notSimon = address(0x124214125);
        vm.startPrank(notSimon);
        vm.warp(block.timestamp + ONE_WEEK + 1);

        vm.expectRevert(IGovernance.CallerNotVetoCouncilMember.selector);
        governance.vetoProposal(0, 1);
        vm.stopPrank();
    }

    function test_guarded_vetoProposal_sameWeekNotFinalized_shouldRevert() public {
        //Create one proposal
        test_guarded_createChangeGCARequirementsProposal();

        //Should be the most popular proposal now
        vm.startPrank(SIMON);
        vm.expectRevert(IGovernance.WeekNotStarted.selector);
        governance.vetoProposal(0, 1);
        vm.stopPrank();
    }

    function test_guarded_vetoProposal_futureWeek_shouldRevert() public {
        vm.startPrank(SIMON);
        vm.expectRevert(IGovernance.ProposalIdDoesNotMatchMostPopularProposal.selector);
        governance.vetoProposal(1, 1);
        vm.stopPrank();
    }

    function test_guarded_vetoProposal_ratifyOrRejectionPeriodEnded_shouldRevert() public {
        //Create one proposal
        test_guarded_createChangeGCARequirementsProposal();

        //Should be the most popular proposal now
        vm.startPrank(SIMON);
        vm.warp(block.timestamp + (ONE_WEEK * 5) + 1);
        vm.expectRevert(IGovernance.RatifyOrRejectPeriodEnded.selector);
        governance.vetoProposal(0, 1);
        vm.stopPrank();
    }

    function test_guarded_vetoProposal_VetoCouncilElection_shouldRevert() public {
        test_guarded_createVetoCouncilElectionOrSlash();
        //Should be the most popular proposal now
        vm.startPrank(SIMON);
        vm.warp(block.timestamp + ONE_WEEK);
        vm.expectRevert(IGovernance.VetoCouncilElectionsCannotBeVetoed.selector);
        governance.vetoProposal(0, 1);
        vm.stopPrank();
    }

    function test_guarded_vetoProposal_GCAElection_shouldRevert() public {
        test_guarded_createGCAElectionOrSlashProposal();
        //Should be the most popular proposal now
        vm.startPrank(SIMON);
        vm.warp(block.timestamp + ONE_WEEK);
        vm.expectRevert(IGovernance.GCACouncilElectionsCannotBeVetoed.selector);
        governance.vetoProposal(0, 1);
        vm.stopPrank();
    }

    function test_guarded_endorseGCAProposal() public {
        test_guarded_createGCAElectionOrSlashProposal();
        vm.startPrank(SIMON);
        vm.warp(block.timestamp + ONE_WEEK);
        governance.endorseGCAProposal(0);

        uint256 numEndorsements = governance.numEndorsementsOnWeek(0);
        assertEq(numEndorsements, 1);
        assertTrue(governance.hasEndorsedProposal(SIMON, 0));
        vm.stopPrank();
    }

    function test_guarded_endorseGCAProposal_callerNotVetoCouncilMember_shouldRevert() public {
        test_guarded_createGCAElectionOrSlashProposal();
        address notSimon;
        assembly {
            notSimon := not(sload(SIMON.slot))
            //Clean dirty bits in case
            notSimon := shr(96, shl(notSimon, 96))
        }

        vm.startPrank(notSimon);
        vm.warp(block.timestamp + ONE_WEEK);
        vm.expectRevert(IGovernance.CallerNotVetoCouncilMember.selector);
        governance.endorseGCAProposal(0);
        vm.stopPrank();
    }

    function test_guarded_endorseGCAProposal_currentWeek_shouldRevert() public {
        test_guarded_createGCAElectionOrSlashProposal();
        vm.startPrank(SIMON);
        vm.warp(block.timestamp + ONE_WEEK - 100);
        vm.expectRevert(IGovernance.WeekNotStarted.selector);
        governance.endorseGCAProposal(0);
    }

    function test_guarded_endorseGCAProposal_futureWeek_shouldRevert() public {
        test_guarded_createGCAElectionOrSlashProposal();
        vm.startPrank(SIMON);
        vm.expectRevert(IGovernance.WeekNotStarted.selector);
        governance.endorseGCAProposal(1);
    }

    function test_guarded_endorseGCAProposal_ratifyOrRejectPeriodEnded_shouldRevert() public {
        test_guarded_createGCAElectionOrSlashProposal();
        vm.startPrank(SIMON);
        vm.warp(block.timestamp + (ONE_WEEK * 5) + 1);
        vm.expectRevert(IGovernance.RatifyOrRejectPeriodEnded.selector);
        governance.endorseGCAProposal(0);
    }

    function test_guarded_endorseGCAProposal_proposalNotGCAElection_shouldRevert() public {
        test_guarded_createChangeGCARequirementsProposal();
        vm.startPrank(SIMON);
        vm.warp(block.timestamp + ONE_WEEK);
        vm.expectRevert(IGovernance.OnlyGCAElectionsCanBeEndorsed.selector);
        governance.endorseGCAProposal(0);
        vm.stopPrank();
    }

    function test_guarded_endorseGCAProposal_cannotEndorseSameWeekTwice() public {
        test_guarded_createGCAElectionOrSlashProposal();
        vm.startPrank(SIMON);
        vm.warp(block.timestamp + ONE_WEEK);
        governance.endorseGCAProposal(0);

        uint256 numEndorsements = governance.numEndorsementsOnWeek(0);
        assertEq(numEndorsements, 1);
        assertTrue(governance.hasEndorsedProposal(SIMON, 0));

        vm.expectRevert(IGovernance.AlreadyEndorsedWeek.selector);
        governance.endorseGCAProposal(0);

        vm.stopPrank();
    }

    function test_guarded_endorseGCAProposal_cannotEndorseMoreThanMaxEndorsements_shouldRevert() public {
        test_guarded_createGCAElectionOrSlashProposal();
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
        vm.expectRevert(IGovernance.MaxGCAEndorsementsReached.selector);
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

    function test_guarded_executeGrantsProposal() public {
        test_guarded_createGrantsProposal();
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
    function test_guarded_syncGrantsProposal() public {
        test_guarded_createGrantsProposal();
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
    function test_guarded_syncGrantsProposal_rejection_ShouldUpdateRecipientBalance() public {
        test_guarded_createGrantsProposal();
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

    function test_guarded_syncGrantsProposal_vetoCouncilSecondProposal_ratifyPeriodNotEnded_shouldNotUpdateFutureState()
        public
    {
        test_guarded_createGrantsProposal();
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

    function test_guarded_syncRFCProposal() public {
        test_guarded_createRFCProposal();
        vm.warp(block.timestamp + ONE_WEEK + 1);
        castLongStakedVotes(SIMON, 0, true, 1);
        vm.warp(block.timestamp + ONE_WEEK * 4);
        governance.syncProposals();
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        assertEq(lastExecutedWeek, 0);
    }

    function test_guarded_syncRFCProposal_vetoCouncilSecondProposal_ratifyPeriodNotEnded_shouldNotUpdateFutureState()
        public
    {
        test_guarded_createRFCProposal();
        vm.warp(block.timestamp + ONE_WEEK * 5);
        createVetoCouncilElectionOrSlashProposal(SIMON, startingAgents[0], address(0x10), true);
        //We actually don't need this syncProposals call since
        //{createVetoCouncilElectionOrSlashProposal} alreadys calls it in the {commitGCC} method
        governance.syncProposals();
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        console.log("last executed week = ", lastExecutedWeek);
        assertEq(lastExecutedWeek, 0);
    }

    function test_guarded_syncGCAElectionOrSlashProposal() public {
        test_guarded_createGCAElectionOrSlashProposal();
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

    function test_guarded_syncGCAElectionOrSlashProposal_rejection_ShouldNotUpdateHashOrNonce() public {
        test_guarded_createGCAElectionOrSlashProposal();
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

    function test_guarded_syncGCAElectionOrSlashProposal_vetoCouncilSecondProposal_ratifyPeriodNotEnded_shouldNotUpdateFutureState(
    ) public {
        test_guarded_createGCAElectionOrSlashProposal();
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

    function test_guarded_syncVetoCouncilElectionOrSlash() public {
        test_guarded_createVetoCouncilElectionOrSlash();
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

    function test_guarded_syncVetoCouncilElectionOrSlash_rejection_shouldNotChangeVetoCouncilState() public {
        test_guarded_createVetoCouncilElectionOrSlash();
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

    function test_guarded_syncVetoCouncilElectionOrSlash_vetoCouncilSecondProposal_ratifyPeriodNotEnded_shouldNotUpdateFutureState(
    ) public {
        test_guarded_createVetoCouncilElectionOrSlash();
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

    function test_guarded_syncChangeGCARequirements_aaa() public {
        test_guarded_createChangeGCARequirementsProposal();
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

    function test_guarded_syncChangeGCARequirements_rejection_ShouldNotChangRequirements() public {
        test_guarded_createChangeGCARequirementsProposal();
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

    function test_guarded_syncChangeGCARequirements_vetoCouncilSecondProposal_ratifyPeriodNotEnded_shouldNotUpdateFutureState(
    ) public {
        test_guarded_createChangeGCARequirementsProposal();
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

    function test_guarded_executeChangeGCARequirements() public {
        test_guarded_createChangeGCARequirementsProposal();
        bytes32 expectedHash = keccak256("new requirements hash");
        vm.warp(block.timestamp + ONE_WEEK + 1);
        castLongStakedVotes(SIMON, 0, true, 1);
        vm.warp(block.timestamp + ONE_WEEK * 4);
        governance.executeProposalAtWeek(0);
        assertEq(minerPoolAndGCA.requirementsHash(), expectedHash);
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        assertEq(lastExecutedWeek, 0);
    }

    function test_guarded_executeRFCProposal() public {
        test_guarded_createRFCProposal();
        vm.warp(block.timestamp + ONE_WEEK + 1);
        castLongStakedVotes(SIMON, 0, true, 1);
        vm.warp(block.timestamp + (ONE_WEEK * 4));
        governance.executeProposalAtWeek(0);
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        assertEq(lastExecutedWeek, 0);
    }

    function test_guarded_executeGCAElectionOrSlashProposal() public {
        test_guarded_createGCAElectionOrSlashProposal();
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

    function test_guarded_executeVetoCouncilElectionOrSlash() public {
        test_guarded_createVetoCouncilElectionOrSlash();
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

    function test_guarded_executeGrantsProposal_rejectionShouldUpdateStateInTarget() public {
        //Grants proposals dont need to be ratified to be executed
        test_guarded_createGrantsProposal();
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

    function test_guarded_executeChangeGCARequirements_rejectionShouldNotUpdateStateInTarget() public {
        test_guarded_createChangeGCARequirementsProposal();
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
    function test_guarded_executeRFCProposal_shouldNotRevert() public {
        test_guarded_createRFCProposal();
        vm.warp(block.timestamp + ONE_WEEK + 1);
        castLongStakedVotes(SIMON, 0, false, 1);
        vm.warp(block.timestamp + (ONE_WEEK * 4));
        governance.executeProposalAtWeek(0);
        uint256 lastExecutedWeek = governance.getLastExecutedWeek();
        assertEq(lastExecutedWeek, 0);
    }

    function test_guarded_executeGCAElectionOrSlashProposal_rejectionShouldNotUpdateStateInTarget() public {
        test_guarded_createGCAElectionOrSlashProposal();
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

    function test_guarded_executeVetoCouncilElectionOrSlash_rejectionShouldNotUpdateStateInTarget() public {
        test_guarded_createVetoCouncilElectionOrSlash();
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

    function test_guarded_executingSameProposalTwice_shouldNotCreateStateChanges() public {
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
        test_guarded_createGCAElectionOrSlashProposal();
        vm.warp(block.timestamp + ONE_WEEK + 1);

        for (uint256 i; i < numEndorsements; i++) {
            vm.startPrank(startingAgents[i]);
            if (i == 5) {
                vm.expectRevert(IGovernance.MaxGCAEndorsementsReached.selector);
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
        test_guarded_createGCAElectionOrSlashProposal();
        vm.warp(block.timestamp + ONE_WEEK + 1);

        for (uint256 i; i < numEndorsements; i++) {
            vm.startPrank(startingAgents[i]);
            if (i == 5) {
                vm.expectRevert(IGovernance.MaxGCAEndorsementsReached.selector);
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

    function test_guarded_executeNoneProposal() public {
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

    function test_guarded_executeRFCProposal_shouldRevert_ifNotWeekEnd() public {
        test_guarded_createRFCProposal();
        vm.warp(block.timestamp + (ONE_WEEK) - 1);
        vm.expectRevert(IGovernance.RatifyOrRejectPeriodNotEnded.selector);
        governance.executeProposalAtWeek(0);
    }

    //Same rules for timestamping apply to Grants proposals, and to none
    function test_guarded_executeGrantsProposal_shouldRevert_ifNotWeekEnd() public {
        test_guarded_createGrantsProposal();
        vm.warp(block.timestamp + (ONE_WEEK) - 1);
        vm.expectRevert(IGovernance.RatifyOrRejectPeriodNotEnded.selector);
        governance.executeProposalAtWeek(0);
    }

    function test_guarded_executeChangeGCARequirements_shouldRevert_ifNotWeekEnd() public {
        vm.warp(block.timestamp + (ONE_WEEK) - 1);
        vm.expectRevert(IGovernance.RatifyOrRejectPeriodNotEnded.selector);
        governance.executeProposalAtWeek(0);
    }

    //All others need to wait at least 4 weeks until they can be executed
    function test_guarded_executeGCAElectionOrSlash_shouldRevert_ifNotRatifyEnd_shouldRevert() public {
        test_guarded_createGCAElectionOrSlashProposal();
        vm.warp(block.timestamp + (ONE_WEEK * 4) - 1);
        vm.expectRevert(IGovernance.RatifyOrRejectPeriodNotEnded.selector);
        governance.executeProposalAtWeek(0);
    }

    function test_guarded_executeVetoCouncilElectionOrSlash_shouldRevert_ifNotRatifyEnd_shouldRevert() public {
        test_guarded_createVetoCouncilElectionOrSlash();
        vm.warp(block.timestamp + (ONE_WEEK * 4) - 1);
        vm.expectRevert(IGovernance.RatifyOrRejectPeriodNotEnded.selector);
        governance.executeProposalAtWeek(0);
    }

    function test_guarded_executeGCAElectionOrSlash_shouldRevert_ifNotWeekEnd_shouldRevert() public {
        test_guarded_createGCAElectionOrSlashProposal();
        vm.warp(block.timestamp + (ONE_WEEK * 4) - 1);
        vm.expectRevert(IGovernance.RatifyOrRejectPeriodNotEnded.selector);
        governance.executeProposalAtWeek(0);
    }

    function test_guarded_executeProposalsOutOfSync_shouldRevert() public {
        // test_guarded_createChangeGCARequirementsProposal();
        vm.warp(block.timestamp + ONE_WEEK + 1);
        createVetoCouncilElectionOrSlashProposal(SIMON, startingAgents[0], address(0x10), true);
        // vm.warp(block.timestamp + ONE_WEEK * 4);

        // vm.expectRevert(IGovernance.ProposalsMustBeExecutedSynchonously.selector);
        // governance.executeProposalAtWeek(1);
    }

    function test_guarded_executeVetoedProposal_shouldUpdateState() public {
        test_guarded_createChangeGCARequirementsProposal();
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

    function test_guarded_executeProposalWithZeroVotes_shouldUpdateState() public {
        test_guarded_createGCAElectionOrSlashProposal();
        vm.warp(block.timestamp + (ONE_WEEK * 5) + 1);
        governance.executeProposalAtWeek(0);
        assertEq(governance.getLastExecutedWeek(), 0);
    }

    /**
     * - RFC proposals
     *     - grants proposals
     *     - and none proposals
     */
    function test_guarded_executeProposal_proposalThatCanBeExecutedAfterWeekEndWithZeroVotes_shouldUpdateState()
        public
    {
        test_guarded_createRFCProposal();
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

    function test_guarded_setMostPopularProposalAtWeek() public {
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
        vm.expectRevert(IGovernance.ProposalNotMostPopular.selector);
        governance.setMostPopularProposalForCurrentWeek(2);

        vm.stopPrank();
    }

    function test_guarded_setMostPopularProposalAtWeek_proposalNotCreated_shouldRevert() public {
        vm.expectRevert(IGovernance.ProposalExpired.selector);
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

    function signCreateProposalDigestLessParams(
        AccountWithPK memory account,
        IGovernance.ProposalType proposalType,
        uint256 nominationsToSpend,
        bytes memory data
    ) internal view returns (bytes memory signature) {
        uint256 deadline = block.timestamp + ONE_WEEK;
        uint256 nonce = governance.spendNominationsOnProposalNonce(account.account);
        return signCreateProposalDigest(account.privateKey, proposalType, nominationsToSpend, nonce, deadline, data);
    }

    function signCreateProposalDigest(
        uint256 privateKey,
        IGovernance.ProposalType proposalType,
        uint256 nominationsToSpend,
        uint256 nonce,
        uint256 deadline,
        bytes memory data
    ) internal view returns (bytes memory signature) {
        bytes32 digest =
            governance.createSpendNominationsOnProposalDigest(proposalType, nominationsToSpend, nonce, deadline, data);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        signature = abi.encodePacked(r, s, v);
        return signature;
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
        vm.startPrank(me);
        usdc.mint(me, amountUSDC);
        usdc.approve(address(usdg), amountUSDC);
        usdg.swap(me, amountUSDC);
        gcc.mint(me, amountGCC);
        gcc.approve(address(uniswapRouter), amountGCC);
        usdg.approve(address(uniswapRouter), amountUSDC);
        uniswapRouter.addLiquidity(
            address(gcc), address(usdg), amountGCC, amountUSDC, amountGCC, amountUSDC, me, block.timestamp
        );
        vm.stopPrank();
    }
}

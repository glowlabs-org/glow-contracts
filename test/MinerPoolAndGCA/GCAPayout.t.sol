// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@/testing/TestGCC.sol";
import "forge-std/console.sol";
import {IGCA} from "@/interfaces/IGCA.sol";
import {MockGCA} from "@/MinerPoolAndGCA/mock/MockGCA.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Governance} from "@/Governance.sol";
import {CarbonCreditDutchAuction} from "@/CarbonCreditDutchAuction.sol";
import "forge-std/StdUtils.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {TestGLOW} from "@/testing/TestGLOW.sol";
import {Handler} from "./Handlers/Handler.GCA.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MerkleProofLib} from "@solady/utils/MerkleProofLib.sol";
import {GCASalaryHelper} from "@/MinerPoolAndGCA/GCASalaryHelper.sol";
import {MockGovernance} from "@/testing/MockGovernance.sol";
import {MockSalaryHelper} from "@/MinerPoolAndGCA/mock/MockSalaryHelper.sol";

contract GCAPayoutTest is Test {
    //--------  CONTRACTS ---------//
    MockGCA gca;
    TestGLOW glow;
    Handler handler;

    //--------  ADDRESSES ---------//
    address governance = address(0x1);
    address earlyLiquidity = address(0x2);
    address vestingContract = address(0x3);
    address vetoCouncilAddress = address(0x4);
    address grantsTreasuryAddress = address(0x5);
    address SIMON = address(0x6);
    uint256 SIMON_PK;
    address OTHER_GCA = address(0x7);
    address OTHER_GCA_2 = address(0x8);
    address OTHER_GCA_3 = address(0x9);
    address OTHER_GCA_4 = address(0x10);

    //--------  CONSTANTS ---------//
    uint256 constant ONE_WEEK = 7 * uint256(1 days);
    uint256 constant _UINT64_MAX_DIV5 = type(uint64).max / 5;
    uint256 constant _200_BILLION = 200_000_000_000 * 1e18;
    address[] startingGCAs;

    function setUp() public {
        //Make sure we don't start at 0
        vm.warp(10);
        (SIMON, SIMON_PK) = _createAccount(6, 100_000_000_000 * 1e18);
        glow = new TestGLOW(earlyLiquidity,vestingContract);
        startingGCAs = _getAddressArray(5, 50);
        startingGCAs[0] = SIMON;
        gca = new MockGCA(startingGCAs,address(glow),governance);
        address[] memory allGCAs = gca.allGcas();
        glow.setContractAddresses(address(gca), vetoCouncilAddress, grantsTreasuryAddress);
        handler = new Handler(address(gca));
        //warp forward
        vm.warp(block.timestamp + 1);
    }

    function testFuzz_constructorShouldProperlySetUpShares(uint256 numGCAs) public {
        vm.assume(numGCAs <= 5 && numGCAs > 0);
        address[] memory gcaAddresses = _getAddressArray(numGCAs, 25);
        gca = new MockGCA(gcaAddresses,address(glow),governance);
        uint256 genesisTimestampFromGlow = glow.GENESIS_TIMESTAMP();
        uint256 gcaGenesisTimestamp = gca.GENESIS_TIMESTAMP();
        uint256 sharesRequiredPerCompPlan = gca.SHARES_REQUIRED_PER_COMP_PLAN() * gcaAddresses.length;
        uint256 shiftStartTimestamp = gca.paymentNonceToShiftStartTimestamp(0);
        assert(shiftStartTimestamp == genesisTimestampFromGlow);

        uint256 sumOfShares;
        for (uint256 i; i < numGCAs; ++i) {
            uint32[5] memory shares = gca.paymentNonceToCompensationPlan(0, i);
            for (uint256 j; j < numGCAs; ++j) {
                sumOfShares += shares[j];
            }
        }
        assert(sumOfShares == 100_000 * numGCAs);
    }

    function test_integrationSubmittingCompPlans() public {
        vm.startPrank(startingGCAs[0]);
        //for the new comp plan, i want to distribute the shares as follows:
        //  1. 50% to me (the first GCA)
        //  2. 25% to the second GCA
        //  3. 25% to the third GCA
        //  4. 0% to the fourth GCA
        //  5. 0% to the fifth GCA
        uint32[5] memory newCompPlan = [uint32(50_000), 25_000, 25_000, 0, 0];
        gca.submitCompensationPlan(newCompPlan, 0);
        uint256 paymentNonce = gca.paymentNonce();
        bytes32 gcaHash = keccak256(abi.encodePacked(startingGCAs));
        assert(gcaHash == gca.payoutNonceToGCAHash(0));
        //payment nonce should have been incremented
        assert(paymentNonce == 1);

        //All other comp plans should have been imported from the past week.
        uint32[5] memory compPlan = gca.paymentNonceToCompensationPlan({nonce: 1, index: 0});
        assertUint32ArraysMatch(compPlan, newCompPlan);
        for (uint256 i = 1; i < startingGCAs.length; ++i) {
            uint32[5] memory planInStoragePreviousPaymentNonce =
                gca.paymentNonceToCompensationPlan({nonce: 0, index: i});
            uint32[5] memory planInStorageNewPaymentNonce = gca.paymentNonceToCompensationPlan({nonce: 1, index: i});
            assertUint32ArraysMatch(planInStoragePreviousPaymentNonce, planInStorageNewPaymentNonce);
        }
        vm.stopPrank();

        //If we submit a new compensation plan from another GCA,
        //It should end up in nonce 1;
        vm.startPrank(startingGCAs[1]);
        uint32[5] memory newCompPlan2 = [uint32(0), 50_000, 0, 50_000, 0];
        gca.submitCompensationPlan(newCompPlan2, 1);
        //Make sure that the shift start timestamp is now the block.timestamp as well

        assert(gca.paymentNonceToShiftStartTimestamp(1) == block.timestamp + ONE_WEEK);

        uint32[5] memory compPlan2 = gca.paymentNonceToCompensationPlan({nonce: 1, index: 1});
        assertUint32ArraysMatch(compPlan2, newCompPlan2);
        //MAKE sure that the payment nonce is still 1
        assert(gca.paymentNonce() == 1);

        vm.stopPrank();

        vm.startPrank(startingGCAs[2]);
        //If we fast forward one week - 10 seconds, and submit a new comp plan,
        //it should still be in nonce 2, since a week hasn't passed yet.
        vm.warp(block.timestamp + ONE_WEEK - 10);
        uint32[5] memory newCompPlan3 = [uint32(0), 0, 50_000, 0, 50_000];
        gca.submitCompensationPlan(newCompPlan3, 2);
        assert(gca.paymentNonce() == 1);
        uint32[5] memory compPlan3 = gca.paymentNonceToCompensationPlan({nonce: 1, index: 2});
        assertUint32ArraysMatch(compPlan3, newCompPlan3);
        vm.stopPrank();

        //If we fast forward 20 seconds, and submit a new comp plan,
        //It should be in nonce 2 since nonce 1 will have already started

        vm.startPrank(startingGCAs[3]);
        vm.warp(block.timestamp + 20);
        uint32[5] memory newCompPlan4 = [uint32(0), 0, 0, 50_000, 50_000];
        gca.submitCompensationPlan(newCompPlan4, 3);
        assert(gca.paymentNonce() == 2);
        uint32[5] memory compPlan4 = gca.paymentNonceToCompensationPlan({nonce: 2, index: 3});

        assertUint32ArraysMatch(compPlan4, newCompPlan4);
        //Past plans are carried over, but let's make sure
        assertUint32ArraysMatch(
            gca.paymentNonceToCompensationPlan({nonce: 1, index: 0}),
            gca.paymentNonceToCompensationPlan({nonce: 2, index: 0})
        );

        assert(gca.payoutNonceToGCAHash(0) == gca.payoutNonceToGCAHash(1));
        assert(gca.payoutNonceToGCAHash(1) == gca.payoutNonceToGCAHash(2));
        vm.stopPrank();

        //Make sure that the shift start timestamp is now the block.timestamp as well
        //Now, payment nonce is 2, but it's shift hasnt started yet
        /**
         * [0]
         *             [        1        ]
         *                   [we are here]
         *                                 [2]
         *     and payment nonce is 2.
         *     If an election happens, then we need
         *     all the comp plans to reset
         */

        vm.startPrank(governance);
        address[] memory newGCAs = _getAddressArray(3, 4000000);
        address[] memory gcasToSlash = new address[](0);
        uint256 timestamp = block.timestamp;
        bytes32 hash = keccak256(abi.encode(gcasToSlash, newGCAs, timestamp));
        gca.pushHash(hash, false);
        gca.executeAgainstHash(gcasToSlash, newGCAs, timestamp);

        assert(gca.paymentNonce() == 2);
        assert(gca.payoutNonceToGCAHash(2) == keccak256(abi.encodePacked(newGCAs)));
        assert(gca.paymentNonceToShiftStartTimestamp(2) == timestamp);

        //Warp forward and test a new comp plan
        vm.warp(block.timestamp + uint256(10 days));

        //New gcas
        address[] memory newGCAs2 = _getAddressArray(5, 9000000);
        timestamp = block.timestamp;
        hash = keccak256(abi.encode(gcasToSlash, newGCAs2, timestamp));
        gca.pushHash(hash, false);
        gca.executeAgainstHash(gcasToSlash, newGCAs2, timestamp);

        //since the shift has started, the payment nonce should have incremented
        assert(gca.paymentNonce() == 3);
        //Make sure the hash is correct
        assert(gca.payoutNonceToGCAHash(3) == keccak256(abi.encodePacked(newGCAs2)));
        assert(gca.paymentNonceToShiftStartTimestamp(3) == timestamp);

        vm.stopPrank();
        //Let's make sure that the past comp plans still have the correct hashes
        assert(gcaHash == gca.payoutNonceToGCAHash(0));
        assert(gca.payoutNonceToGCAHash(0) == gca.payoutNonceToGCAHash(1));
        assert(gca.payoutNonceToGCAHash(2) == keccak256(abi.encodePacked(newGCAs)));
        assert(gca.payoutNonceToGCAHash(3) == keccak256(abi.encodePacked(newGCAs2)));

        vm.startPrank(startingGCAs[1]);
        gca.claimPayout({
            user: startingGCAs[1],
            paymentNonce: 0,
            activeGCAsAtPaymentNonce: startingGCAs,
            userIndex: 1,
            claimFromInflation: true,
            sig: bytes("")
        });
        vm.warp(block.timestamp + 100 weeks);
        gca.claimPayout({
            user: startingGCAs[1],
            paymentNonce: 0,
            activeGCAsAtPaymentNonce: startingGCAs,
            userIndex: 1,
            claimFromInflation: true,
            sig: bytes("")
        });
        (uint256 withdrawableBalance, uint256 slashableBalance,) =
            gca.getPayoutData(startingGCAs[1], 0, startingGCAs, 1);
        assert(withdrawableBalance == 0);
        assert(slashableBalance == 0);
        // console.log("nonce 0 shift start", gca.paymentNonceToShiftStartTimestamp(0));
        // console.log("nonce 1 shift start", gca.paymentNonceToShiftStartTimestamp(1));
        // console.log("withdrawableBalance: %s", withdrawableBalance);
        // console.log("slashableBalance: %s", slashableBalance);
        vm.stopPrank();
    }

    function test_claimPayout_slashedAgent_claimPayout_shouldRevert() public {
        vm.warp(block.timestamp + 5 weeks);
        //Claiming before should be ok.
        vm.startPrank(startingGCAs[0]);
        gca.claimPayout({
            user: startingGCAs[0],
            paymentNonce: 0,
            activeGCAsAtPaymentNonce: startingGCAs,
            userIndex: 0,
            claimFromInflation: true,
            sig: bytes("")
        });
        vm.stopPrank();
        vm.warp(block.timestamp + 5 weeks);

        address[] memory gcasToSlash = new address[](1);
        gcasToSlash[0] = startingGCAs[0];

        address[] memory newGCAs = _getAddressArray(5, 9000000);
        uint256 timestamp = block.timestamp;
        bytes32 hash = keccak256(abi.encode(gcasToSlash, newGCAs, timestamp));
        gca.pushRequirementsHashMock(hash);
        gca.incrementSlashNonce();
        gca.executeAgainstHash(gcasToSlash, newGCAs, timestamp);

        vm.expectRevert(GCASalaryHelper.SlashedAgentCannotClaimReward.selector);
        gca.claimPayout({
            user: startingGCAs[0],
            paymentNonce: 0,
            activeGCAsAtPaymentNonce: startingGCAs,
            userIndex: 0,
            claimFromInflation: true,
            sig: bytes("")
        });
    }

    function test_claimPayout_activeGCAsAtPaymentNonce_doNotMatch_shouldRevert() public {
        startingGCAs[1] = address(0xdeddd);
        vm.warp(block.timestamp + 5 weeks);
        vm.expectRevert(GCASalaryHelper.InvalidGCAHash.selector);
        vm.startPrank(startingGCAs[0]);
        gca.claimPayout({
            user: startingGCAs[0],
            paymentNonce: 0,
            activeGCAsAtPaymentNonce: startingGCAs,
            userIndex: 0,
            claimFromInflation: true,
            sig: bytes("")
        });
        vm.stopPrank();
    }

    function test_claimPayout_invalidGCAIndex_shouldRevert() public {
        vm.warp(block.timestamp + 5 weeks);
        vm.expectRevert(GCASalaryHelper.InvalidUserIndex.selector);
        vm.startPrank(startingGCAs[0]);
        gca.claimPayout({
            user: startingGCAs[0],
            paymentNonce: 0,
            activeGCAsAtPaymentNonce: startingGCAs,
            userIndex: 1, //user index is 0, not 1, so we should revert
            claimFromInflation: true,
            sig: bytes("")
        });
        vm.stopPrank();
    }

    function test_claimPayout_relaySignature_ShouldWork() public {
        vm.warp(block.timestamp + 5 weeks);
        //Claiming before should be ok.
        //simon is also starting gca at zero
        address relayer = address(0x55555);
        bytes memory sig = signRelayDigest(startingGCAs[0], SIMON_PK, relayer, 0);
        vm.startPrank(relayer);
        gca.claimPayout({
            user: startingGCAs[0],
            paymentNonce: 0,
            activeGCAsAtPaymentNonce: startingGCAs,
            userIndex: 0,
            claimFromInflation: true,
            sig: sig
        });
        vm.stopPrank();
    }

    function test_claimPayout_relaySignature_wrongNonce_shouldRevert() public {
        vm.warp(block.timestamp + 5 weeks);
        //Claiming before should be ok.
        //simon is also starting gca at zero
        address relayer = address(0x55555);
        bytes memory sig = signRelayDigest(startingGCAs[0], SIMON_PK, relayer, 0);
        vm.startPrank(relayer);
        gca.claimPayout({
            user: startingGCAs[0],
            paymentNonce: 0,
            activeGCAsAtPaymentNonce: startingGCAs,
            userIndex: 0,
            claimFromInflation: true,
            sig: sig
        });
        vm.expectRevert(GCASalaryHelper.InvalidRelaySignature.selector);
        gca.claimPayout({
            user: startingGCAs[0],
            paymentNonce: 0,
            activeGCAsAtPaymentNonce: startingGCAs,
            userIndex: 0,
            claimFromInflation: true,
            sig: sig
        });
        vm.stopPrank();
    }

    function test_claimPayout_relaySignature_wrongPaymentNonce_shouldRevert() public {
        vm.warp(block.timestamp + 5 weeks);
        //Claiming before should be ok.
        //simon is also starting gca at zero
        address relayer = address(0x55555);
        bytes memory sig = signRelayDigest(startingGCAs[0], SIMON_PK, relayer, 0);
        vm.startPrank(relayer);
        vm.expectRevert(GCASalaryHelper.InvalidRelaySignature.selector);
        gca.claimPayout({
            user: startingGCAs[0],
            paymentNonce: 1,
            activeGCAsAtPaymentNonce: startingGCAs,
            userIndex: 0,
            claimFromInflation: true,
            sig: sig
        });
        vm.stopPrank();
    }

    function test_sharesDoNotAddUpTo100_000_shouldRevert() public {
        vm.startPrank(startingGCAs[0]);
        //for the new comp plan, i want to distribute the shares as follows:
        //  1. 50% to me (the first GCA)
        //  2. 25% to the second GCA
        //  3. 25% to the third GCA
        //  4. 0% to the fourth GCA
        //  5. 0% to the fifth GCA
        uint32[5] memory newCompPlan = [uint32(50_000), 24_999, 25_000, 0, 0];
        vm.expectRevert(GCASalaryHelper.InvalidShares.selector);
        gca.submitCompensationPlan(newCompPlan, 0);
        vm.stopPrank();
    }

    function assertUint32ArraysMatch(uint32[5] memory arr1, uint32[5] memory arr2) private pure {
        for (uint256 i; i < arr1.length; ++i) {
            assert(arr1[i] == arr2[i]);
        }
    }

    function _defaultCompPlan(uint256 gcaIndex) private view returns (uint32[5] memory shares) {
        shares[gcaIndex] = uint32(gca.SHARES_REQUIRED_PER_COMP_PLAN());
        return shares;
    }

    function _getAddressArray(uint256 numAddresses, uint256 addressOffset) private pure returns (address[] memory) {
        address[] memory addresses = new address[](numAddresses);
        for (uint256 i = 0; i < numAddresses; ++i) {
            addresses[i] = address(uint160(addressOffset + i));
        }
        return addresses;
    }

    function addGCA(address newGCA) public {
        address[] memory allGCAs = gca.allGcas();
        address[] memory temp = new address[](allGCAs.length+1);
        for (uint256 i; i < allGCAs.length; ++i) {
            temp[i] = allGCAs[i];
            if (allGCAs[i] == newGCA) {
                return;
            }
        }
        temp[allGCAs.length] = newGCA;
        gca.setGCAs(temp);
        allGCAs = gca.allGcas();
        assertTrue(_containsElement(allGCAs, newGCA));
    }

    function test_GCASalaryHelper_allBaseFunctions_shouldRevertWhenNotOverriden() public {
        address[] memory startingAgents = _getAddressArray(5, 50);
        MockSalaryHelper helper = new MockSalaryHelper(startingAgents);
        vm.expectRevert();
        uint256 x = helper.genesisTimestampWithin();
        vm.expectRevert();
        bytes32 y = helper.domainSeperatorV4Main();
        vm.expectRevert();
        helper.claimGlowFromInflation();
        vm.expectRevert();
        helper.transferGlow(address(0x1), 100);
    }

    function _containsElement(address[] memory arr, address element) private pure returns (bool) {
        for (uint256 i; i < arr.length; ++i) {
            if (arr[i] == element) {
                return true;
            }
        }
        return false;
    }

    function signRelayDigest(address from, uint256 privateKey, address relayer, uint256 paymentNonce)
        public
        view
        returns (bytes memory)
    {
        uint256 nextNonce = gca.nextRelayNonce(from);
        bytes32 digest = gca.createRelayDigest(relayer, paymentNonce, nextNonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        return sig;
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
}

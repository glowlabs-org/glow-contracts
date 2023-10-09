// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "@/testing/TestGCC.sol";
import "forge-std/console.sol";
import {IGCA} from "@/interfaces/IGCA.sol";
import {MockGCA} from "@/MinerPoolAndGCA/mock/MockGCA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Governance} from "@/Governance.sol";
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
import {Holding, ClaimHoldingArgs, IHoldingContract, HoldingContract} from "@/HoldingContract.sol";

struct ClaimLeaf {
    address payoutWallet;
    uint256 glwWeight;
    uint256 grcWeight;
}

contract HoldingContractTest is Test {
    //--------  CONTRACTS ---------//
    MockMinerPoolAndGCA minerPoolAndGCA;
    TestGLOW glow;
    MockUSDC usdc;
    MockUSDC grc2;
    HoldingContract holdingContract;

    //--------  ADDRESSES ---------//
    address governance = address(0x1);
    address earlyLiquidity = address(0x2);
    address vestingContract = address(0x3);
    address vetoCouncilAddress;
    VetoCouncil vetoCouncil;
    address grantsTreasuryAddress = address(0x5);
    address SIMON;
    uint256 SIMON_PRIVATE_KEY;

    address VETO_COUNCIL_MEMBER = address(0x7);
    address OTHER_GCA_2 = address(0x8);
    address OTHER_GCA_3 = address(0x9);
    address OTHER_GCA_4 = address(0x10);
    address carbonCreditAuction = address(0x11);
    address defaultAddressInWithdraw;
    uint256 defaultAddressPrivateKey;
    address bidder1 = address(0x12);
    address bidder2 = address(0x13);

    uint256 NINETY_DAYS = uint256(90 days);

    //--------  CONSTANTS ---------//
    uint256 constant ONE_WEEK = 7 * uint256(1 days);

    function setUp() public {
        //Make sure we don't start at 0
        (SIMON, SIMON_PRIVATE_KEY) = _createAccount(9999, type(uint256).max);
        vm.warp(10);
        usdc = new MockUSDC();
        (defaultAddressInWithdraw, defaultAddressPrivateKey) = _createAccount(2313141231, type(uint256).max);
        glow = new TestGLOW(earlyLiquidity,vestingContract);
        address[] memory temp = new address[](0);
        address[] memory startingAgents = new address[](2);
        startingAgents[0] = address(SIMON);
        startingAgents[1] = address(VETO_COUNCIL_MEMBER);
        vetoCouncil = new VetoCouncil(governance, address(glow),startingAgents);
        vetoCouncilAddress = address(vetoCouncil);
        holdingContract = new HoldingContract(vetoCouncilAddress);
        minerPoolAndGCA =
        new MockMinerPoolAndGCA(temp,address(glow),governance,keccak256("requirementsHash"),earlyLiquidity,address(usdc),carbonCreditAuction,vetoCouncilAddress,address(holdingContract));
        glow.setContractAddresses(address(minerPoolAndGCA), vetoCouncilAddress, grantsTreasuryAddress);
        grc2 = new MockUSDC();
    }

    //-------- ISSUING REPORTS ---------//
    function addGCA(address newGCA) public {
        address[] memory allGCAs = minerPoolAndGCA.allGcas();
        address[] memory temp = new address[](allGCAs.length+1);
        for (uint256 i; i < allGCAs.length; ++i) {
            temp[i] = allGCAs[i];
            if (allGCAs[i] == newGCA) {
                return;
            }
        }
        temp[allGCAs.length] = newGCA;
        minerPoolAndGCA.setGCAs(temp);
        allGCAs = minerPoolAndGCA.allGcas();
    }

    function mintToHoldingContract(address token, uint256 amount) public {
        MockUSDC(token).mint(address(holdingContract), amount);
    }

    function test_resetMinerPool_shouldRevert() public {
        vm.expectRevert(HoldingContract.MinerPoolAlreadySet.selector);
        holdingContract.setMinerPool(address(0x1));
    }

    function test_addHolding_callerNotMinerPool_shouldRevert() public {
        mintToHoldingContract(address(usdc), 1_000_000_000 ether);
        vm.startPrank(address(0xdaaaaaf));
        vm.expectRevert(HoldingContract.OnlyMinerPoolCanAddHoldings.selector);
        holdingContract.addHolding(SIMON, address(usdc), 10 ether);
        vm.stopPrank();
    }

    function test_claimFromHoldingContract_beforeHoldingExpiration_shouldRevert() public {
        mintToHoldingContract(address(usdc), 1_000_000_000 ether);
        vm.startPrank(address(minerPoolAndGCA));
        holdingContract.addHolding(SIMON, address(usdc), 10 ether);
        vm.stopPrank();

        vm.startPrank(SIMON);
        vm.expectRevert(HoldingContract.WithdrawalNotReady.selector);
        holdingContract.claimHoldingSingleton(SIMON, address(usdc));
        vm.stopPrank();
    }

    function test_claimFromHoldingContract_claimingAfterExpiration_shoudClaim() public {
        mintToHoldingContract(address(usdc), 1_000_000_000 ether);
        vm.startPrank(address(minerPoolAndGCA));
        holdingContract.addHolding(SIMON, address(usdc), 10 ether);
        vm.stopPrank();

        vm.startPrank(SIMON);
        vm.warp(block.timestamp + ONE_WEEK);
        holdingContract.claimHoldingSingleton(SIMON, address(usdc));
        vm.stopPrank();

        assertEq(usdc.balanceOf(SIMON), 10 ether);
    }

    function test_delayNetwork_callerNotVetoCouncilMember_shouldRevert() public {
        vm.startPrank(address(0xaaaaaaaaadfffffff));
        vm.expectRevert(HoldingContract.CallerMustBeVetoCouncilMember.selector);
        holdingContract.delayNetwork();
        vm.stopPrank();
    }

    function test_delayNetwork_callerIsVetoCouncilMember_shouldWork() public {
        uint256 originalTimestamp = block.timestamp;
        vm.startPrank(SIMON);
        holdingContract.delayNetwork();
        vm.stopPrank();
        uint256 newTimestamp = holdingContract.minimumWithdrawTimestamp();
        assert(originalTimestamp + NINETY_DAYS == newTimestamp);
    }

    function test_delayNetworkTwiceBefore80Days_shouldRevert() public {
        uint256 originalTimestamp = block.timestamp;
        vm.startPrank(SIMON);
        holdingContract.delayNetwork();
        uint256 newTimestamp = holdingContract.minimumWithdrawTimestamp();
        assert(originalTimestamp + NINETY_DAYS == newTimestamp);

        vm.expectRevert(HoldingContract.CanOnlyDelayEveryEightyDays.selector);
        holdingContract.delayNetwork();

        //warp forward 79 days
        uint256 seventyNineDays = 79 * uint256(1 days);
        vm.warp(block.timestamp + seventyNineDays);
        vm.expectRevert(HoldingContract.CanOnlyDelayEveryEightyDays.selector);
        holdingContract.delayNetwork();

        vm.stopPrank();
    }

    function test_delayNetworkTwiceAfter80Days_shouldWork() public {
        test_delayNetworkTwiceBefore80Days_shouldRevert();
        //Warping one more day should work

        vm.startPrank(SIMON);
        vm.warp(block.timestamp + uint256(1 days));
        holdingContract.delayNetwork();

        vm.stopPrank();
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
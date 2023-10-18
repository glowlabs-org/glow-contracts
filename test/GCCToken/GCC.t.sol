// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "@/testing/TestGCC.sol";
import "forge-std/console.sol";
import {IGCC} from "@/interfaces/IGCC.sol";
import "forge-std/StdError.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Governance} from "@/Governance.sol";
import {CarbonCreditDutchAuction} from "@/CarbonCreditDutchAuction.sol";
import {Handler} from "./Handler.sol";
import "forge-std/StdUtils.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {TestGLOW} from "@/testing/TestGLOW.sol";

contract GCCTest is Test {
    TestGCC public gcc;
    Governance public gov;
    CarbonCreditDutchAuction public auction;
    address public constant GCA_AND_MINER_POOL_CONTRACT = address(0x2);
    address public SIMON;
    uint256 public SIMON_PK;
    Handler public handler;
    address gca = address(0x155);
    address vetoCouncil = address(0x156);
    address grantsTreasury = address(0x157);
    address glw;
    TestGLOW glwContract;
    address vestingContract = address(0x412412);
    address earlyLiquidity = address(0x412412);
    address other = address(0xdead);

    function setUp() public {
        glwContract = new TestGLOW(earlyLiquidity,vestingContract);
        glw = address(glwContract);
        (SIMON, SIMON_PK) = _createAccount(9999, 1e20 ether);
        gov = new Governance();
        gcc = new TestGCC(GCA_AND_MINER_POOL_CONTRACT, address(gov), glw);
        auction = CarbonCreditDutchAuction(address(gcc.CARBON_CREDIT_AUCTION()));
        handler = new Handler(address(gcc),GCA_AND_MINER_POOL_CONTRACT);
        gov.setContractAddresses(address(gcc), gca, vetoCouncil, grantsTreasury, glw);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = Handler.mintToCarbonCreditAuction.selector;
        FuzzSelector memory fs = FuzzSelector({selectors: selectors, addr: address(handler)});

        targetContract(address(handler));
        // targetSender(GCA_AND_MINER_POOL_CONTRACT);
    }

    /// forge-config: default.invariant.depth = 1000
    // We make sure that the bucketMintedBitmap is set correctly by creating
    /// a stateful fuzz that tracks all used bucketIds
    function invariant_setBucketMintedBitmapLogic() public {
        uint256[] memory allFuzzIds = handler.getAllFuzzIds();
        uint256[] memory allNotFuzzIds = handler.getAllNotFuzzIds();
        // assertEq(allFuzzIds.length > 0,true);
        for (uint256 i = 0; i < allFuzzIds.length; i++) {
            assertEq(handler.isBucketMinted(allFuzzIds[i]), true);
        }
        for (uint256 i = 0; i < allNotFuzzIds.length; i++) {
            assertEq(handler.isBucketMinted(allNotFuzzIds[i]), false);
        }
    }

    modifier mintTo(address user) {
        gcc.mint(user, 1e20 ether);
        assertEq(gcc.balanceOf(user), 1e20 ether);
        _;
    }

    modifier prankAsGCA() {
        vm.startPrank(GCA_AND_MINER_POOL_CONTRACT);
        _;
        vm.stopPrank();
    }

    /**
     * This test ensures that the GCC contract
     * is correctly minting to the carbon credit auction contract.
     */
    function test_sendToCarbonCreditAuction() public {
        vm.startPrank(GCA_AND_MINER_POOL_CONTRACT);
        gcc.mintToCarbonCreditAuction(1, 1e20 ether);
        assertEq(gcc.balanceOf(address(auction)), 1e20 ether);
        assertEq(gcc.isBucketMinted(1), true);
        //Let's have a sanity check and make sure that bucketMinted(2) is false
        assertEq(gcc.isBucketMinted(2), false);
        vm.stopPrank();
    }

    /**
     * This test ensures that only the GCA and
     *     Miner Pool contract can use the ```mintToCarbonCredit``` function.
     */
    function test_sendToCarbonCreditAuction_callerNotGCA_shouldRevert() public {
        vm.startPrank(SIMON);
        vm.expectRevert(IGCC.CallerNotGCAContract.selector);
        gcc.mintToCarbonCreditAuction(1, 1e20 ether);
        vm.stopPrank();
    }

    //This test ensures that we can only mint from a bucket once
    function test_sendToCarbonCreditAuctionSameBucketShouldRevert() public {
        test_sendToCarbonCreditAuction();
        vm.startPrank(GCA_AND_MINER_POOL_CONTRACT);
        vm.expectRevert(IGCC.BucketAlreadyMinted.selector);
        gcc.mintToCarbonCreditAuction(1, 1e20 ether);
    }

    function test_retireGCC() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 1e20 ether);
        gcc.retireGCC(1e20 ether, SIMON);
        assertEq(gcc.balanceOf(SIMON), 0);
        //make sure i get neutrality
        assertEq(gcc.totalCreditsRetired(SIMON), 1e20 ether);
        assertEq(gcc.balanceOf(address(gcc)), 1e20 ether);
    }

    function test_retireGCC_GiveRewardsToOthers() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 1e20 ether);
        gcc.retireGCC(1e20 ether, other);
        assertEq(gcc.balanceOf(SIMON), 0);
        //make sure i get neutrality
        assertEq(gcc.totalCreditsRetired(other), 1e20 ether);
        assertEq(gcc.balanceOf(address(gcc)), 1e20 ether);
    }

    //TODO: Check if we handle downstream case for errro
    function test_retireGCC_ApprovalShouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 1e20 ether);
        vm.stopPrank();

        vm.startPrank(other);
        /// spender,allowance,needed
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                other, //spender
                0, //allowance
                1e20 ether //needed
            )
        );
        gcc.retireGCCFor(SIMON, other, 1e20 ether);
        vm.stopPrank();
    }

    function test_setRetiringAllowance_single() public {
        vm.startPrank(SIMON);
        gcc.increaseRetiringAllowance(other, 500_000);

        assertEq(gcc.retiringAllowance(SIMON, other), 500_000);

        gcc.decreaseRetiringAllowance(other, 250_000);
        assertEq(gcc.retiringAllowance(SIMON, other), 250_000);

        gcc.decreaseRetiringAllowance(other, 250_000);
        assertEq(gcc.retiringAllowance(SIMON, other), 0);

        vm.expectRevert(stdError.arithmeticError);
        gcc.decreaseRetiringAllowance(other, 1);
    }

    function test_setRetiringAllowances_overflowShouldSetToUintMax() public {
        vm.startPrank(SIMON);
        gcc.increaseRetiringAllowance(other, type(uint256).max);
        gcc.increaseRetiringAllowance(other, 5 ether);
        assertEq(gcc.retiringAllowance(SIMON, other), type(uint256).max);
    }

    function test_setAllowances() public {
        uint256 transferApproval = 500_000;
        uint256 retiringApproval = 900_000;
        vm.startPrank(SIMON);
        gcc.setAllowances(other, transferApproval, retiringApproval);
        assertEq(gcc.retiringAllowance(SIMON, other), retiringApproval);
        assertEq(gcc.allowance(SIMON, other), transferApproval);
    }

    function test_setRetiringAllowances_underflowShouldRevert() public {
        vm.startPrank(SIMON);
        vm.expectRevert(stdError.arithmeticError);
        gcc.decreaseRetiringAllowance(other, 1 ether);
    }

    // Sets transfer allowance and retiring allowance in one
    function test_setRetiringAllowance_Double() public {
        vm.startPrank(SIMON);
        gcc.increaseAllowances(other, 500_000);

        assertEq(gcc.retiringAllowance(SIMON, other), 500_000);
        assertEq(gcc.allowance(SIMON, other), 500_000);

        gcc.decreaseAllowances(other, 250_000);
        assertEq(gcc.retiringAllowance(SIMON, other), 250_000);
        assertEq(gcc.allowance(SIMON, other), 250_000);

        gcc.decreaseAllowances(other, 250_000);
        assertEq(gcc.retiringAllowance(SIMON, other), 0);
        assertEq(gcc.allowance(SIMON, other), 0);

        vm.expectRevert();
        gcc.decreaseAllowances(other, 1);
    }

    function test_retireGCC_onlyRetiringApproval_shouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 1e20 ether);
        gcc.increaseRetiringAllowance(other, 1e20 ether);
        vm.stopPrank();

        vm.startPrank(other);
        /// spender,allowance,needed
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                other, //spender
                0, //allowance
                1e20 ether //needed
            )
        );
        gcc.retireGCCFor(SIMON, other, 1e20 ether);
        vm.stopPrank();
    }

    function test_retireGCC_onlyTransferApproval_shouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 1e20 ether);
        gcc.increaseAllowance(other, 1e20 ether);
        vm.stopPrank();

        vm.startPrank(other);
        /// spender,allowance,needed
        vm.expectRevert(stdError.arithmeticError);
        gcc.retireGCCFor(SIMON, other, 1e20 ether);
        vm.stopPrank();
    }

    function test_retireGCC_ApprovalShouldWork() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 1e20 ether);
        gcc.increaseAllowances(other, 1e20 ether);
        assertEq(gcc.retiringAllowance(SIMON, other), 1e20 ether);
        assertEq(gcc.allowance(SIMON, other), 1e20 ether);
        vm.stopPrank();

        vm.startPrank(other);
        gcc.retireGCCFor(SIMON, other, 1e20 ether);
        vm.stopPrank();
    }

    function test_retireGCC_Signature() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 1e20 ether);
        vm.stopPrank();
        bytes memory signature =
            _signPermit(SIMON, other, 1e20 ether, gcc.nextRetiringNonce(SIMON), block.timestamp + 1000, SIMON_PK);

        vm.startPrank(other);
        gcc.retireGCCForAuthorized(SIMON, other, 1e20 ether, block.timestamp + 1000, signature);

        assertEq(gcc.balanceOf(SIMON), 0);
        assertEq(gcc.totalCreditsRetired(other), 1e20 ether);
        assertEq(gcc.balanceOf(address(gcc)), 1e20 ether);
        assertEq(gcc.retiringAllowance(SIMON, other), 0);
    }

    function test_retireGCC_Signature_expirationInPast_shouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 1e20 ether);
        vm.stopPrank();
        uint256 currentTimestamp = block.timestamp;
        uint256 sigTimestamp = block.timestamp + 1000;
        bytes memory signature =
            _signPermit(SIMON, other, 1e20 ether, gcc.nextRetiringNonce(SIMON), block.timestamp + 1000, SIMON_PK);

        vm.startPrank(other);
        vm.warp(sigTimestamp + 1);

        vm.expectRevert(IGCC.RetiringPermitSignatureExpired.selector);
        gcc.retireGCCForAuthorized(SIMON, other, 1e20 ether, sigTimestamp, signature);
    }

    function test_retireGCC_Signature_badSignature_shouldFail() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 1e20 ether);
        vm.stopPrank();
        uint256 currentTimestamp = block.timestamp;
        uint256 sigTimestamp = block.timestamp + 1000;
        bytes memory signature =
            _signPermit(SIMON, other, 1e20 ether, gcc.nextRetiringNonce(SIMON), block.timestamp + 1000, SIMON_PK);

        vm.startPrank(other);
        vm.expectRevert(IGCC.RetiringSignatureInvalid.selector);
        gcc.retireGCCForAuthorized(SIMON, other, 1e20 ether, sigTimestamp + 1, signature);
    }

    function test_retireGCC_badSigner_shouldFail() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 1e20 ether);
        vm.stopPrank();
        uint256 currentTimestamp = block.timestamp;
        uint256 sigTimestamp = block.timestamp + 1000;
        (address badActor, uint256 badActorPk) = _createAccount(9998, 1e20 ether);
        bytes memory signature =
            _signPermit(badActor, other, 1e20 ether, gcc.nextRetiringNonce(SIMON), block.timestamp + 1000, badActorPk);

        vm.startPrank(other);
        vm.expectRevert(IGCC.RetiringSignatureInvalid.selector);
        gcc.retireGCCForAuthorized(SIMON, other, 1e20 ether, sigTimestamp, signature);
    }

    function test_cannotIncreaseRetiringAllowanceByZero() public {
        vm.startPrank(SIMON);
        vm.expectRevert(IGCC.MustIncreaseRetiringAllowanceByAtLeastOne.selector);
        gcc.increaseRetiringAllowance(other, 0);
        vm.stopPrank();
    }

    function test_retireGCC_signatureReplayShouldFail() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 1e20 ether);
        vm.stopPrank();
        uint256 currentTimestamp = block.timestamp;
        uint256 sigTimestamp = block.timestamp + 1000;
        bytes memory signature =
            _signPermit(SIMON, other, 1e20 ether, gcc.nextRetiringNonce(SIMON), block.timestamp + 1000, SIMON_PK);

        vm.startPrank(other);
        gcc.retireGCCForAuthorized(SIMON, other, 1e20 ether, sigTimestamp, signature);
        vm.expectRevert(IGCC.RetiringSignatureInvalid.selector);
        gcc.retireGCCForAuthorized(SIMON, other, 1e20 ether, sigTimestamp, signature);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   helpers                                  */
    /* -------------------------------------------------------------------------- */
    function _createAccount(uint256 privateKey, uint256 amount) internal returns (address addr, uint256 priv) {
        addr = vm.addr(privateKey);
        vm.deal(addr, amount);
        priv = privateKey;

        return (addr, priv);
    }

    function _signPermit(
        address owner,
        address spender,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        uint256 privateKey
    ) internal returns (bytes memory signature) {
        bytes32 structHash =
            keccak256(abi.encode(gcc.RETIRING_PERMIT_TYPEHASH(), owner, spender, amount, nonce, deadline));
        bytes32 messageHash = MessageHashUtils.toTypedDataHash(gcc.domainSeparatorV4(), structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, messageHash);
        signature = abi.encodePacked(r, s, v);
    }
}

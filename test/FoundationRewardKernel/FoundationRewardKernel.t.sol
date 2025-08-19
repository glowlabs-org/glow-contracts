// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {FoundationRewardKernel} from "src/v2/FoundationRewardKernel.sol";
import {CounterfactualHolderFactory} from "src/v2/CounterfactualHolderFactory.sol";
import {CounterfactualHolder} from "src/v2/CounterfactualHolder.sol";
import {Call} from "src/v2/Structs.sol";
import {MockERC20} from "src/testing/MockERC20.sol";
import {MockGuardERC20} from "src/testing/MockGuardERC20.sol";

contract FoundationRewardKernelTest is Test {
    FoundationRewardKernel internal kernel;
    CounterfactualHolderFactory internal factory;
    MockERC20 internal unguarded;
    MockGuardERC20 internal guarded;

    address internal foundation = address(0xF00D);
    address internal rejector = address(0xBAD);
    address internal donor = address(0xD00F);
    address internal claimer = address(0xA11CE);
    address internal recipient = address(0xB0B);

    function setUp() public {
        factory = new CounterfactualHolderFactory();
        kernel = new FoundationRewardKernel(foundation, rejector, factory);
        unguarded = new MockERC20("UNG", "UNG", 18);
        guarded = new MockGuardERC20("GUA", "GUA", 18);

        // Fund donor with both tokens
        unguarded.mint(donor, 1_000_000 ether);
        guarded.mint(donor, 1_000_000 ether);
    }

    // ============ Helpers ============

    function _singleLeaf(bytes32 leaf) internal pure returns (bytes32 root, bytes32[] memory proof) {
        // Single leaf tree: empty proof, root == leaf
        root = leaf;
        proof = new bytes32[](0);
    }

    // Build a 2-leaf tree for future multi-claimer cases; leaves sorted per library expectation
    function _twoLeafTree(bytes32 l1, bytes32 l2)
        internal
        pure
        returns (bytes32 root, bytes32[] memory proofL1, bytes32[] memory proofL2)
    {
        bytes32 a = l1;
        bytes32 b = l2;
        if (a > b) {
            (a, b) = (b, a);
        }
        root = keccak256(abi.encodePacked(a, b));
        proofL1 = new bytes32[](1);
        proofL2 = new bytes32[](1);
        proofL1[0] = l2;
        proofL2[0] = l1;
    }

    function _buildLeaf(address _claimer, FoundationRewardKernel.TokenAndAmount[] memory taa)
        internal
        pure
        returns (bytes32 leaf, bytes32 taaHash)
    {
        taaHash = keccak256(abi.encode(taa));
        leaf = keccak256(abi.encode(_claimer, taaHash));
    }

    function _postRoot(address token, uint256 amount)
        internal
        returns (uint256 nonce, bytes32[] memory proof, FoundationRewardKernel.TokenAndAmount[] memory taa)
    {
        taa = new FoundationRewardKernel.TokenAndAmount[](1);
        taa[0] = FoundationRewardKernel.TokenAndAmount({token: token, amount: amount});

        (bytes32 leaf,) = _buildLeaf(claimer, taa);
        (bytes32 root, bytes32[] memory _proof) = _singleLeaf(leaf);

        vm.prank(foundation);
        kernel.postPayoutRoot(root, taa);
        nonce = kernel.$nextPostNonce() - 1;
        proof = _proof;
    }

    // ============ Tests: posting ============

    function test_postPayoutRoot_onlyFoundation() public {
        FoundationRewardKernel.TokenAndAmount[] memory taa = new FoundationRewardKernel.TokenAndAmount[](1);
        taa[0] = FoundationRewardKernel.TokenAndAmount({token: address(unguarded), amount: 1 ether});
        (bytes32 leaf,) = _buildLeaf(claimer, taa);
        (bytes32 root, bytes32[] memory proof) = _singleLeaf(leaf);

        vm.expectRevert(FoundationRewardKernel.NotFoundationMultisig.selector);
        kernel.postPayoutRoot(root, taa);

        vm.prank(foundation);
        kernel.postPayoutRoot(root, taa);

        // Basic sanity: root posted and nonce advanced
        assertEq(kernel.$nextPostNonce(), 1, "nonce incremented");
        assertEq(proof.length, 0, "proof is empty for single leaf");
    }

    function test_nextPostNonce_increments_multiple_posts() public {
        for (uint256 i = 0; i < 5; ++i) {
            (bytes32 root, bytes32[] memory proof) = _singleLeaf(keccak256(abi.encode(i)));
            FoundationRewardKernel.TokenAndAmount[] memory taa = new FoundationRewardKernel.TokenAndAmount[](1);
            taa[0] = FoundationRewardKernel.TokenAndAmount({token: address(unguarded), amount: i + 1});
            vm.prank(foundation);
            kernel.postPayoutRoot(root, taa);
            assertEq(kernel.$nextPostNonce(), i + 1, "nonce increments each post");
            assertEq(proof.length, 0);
        }
    }

    function test_postPayoutRoot_revert_zero_root() public {
        FoundationRewardKernel.TokenAndAmount[] memory taa = new FoundationRewardKernel.TokenAndAmount[](1);
        taa[0] = FoundationRewardKernel.TokenAndAmount({token: address(unguarded), amount: 1 ether});

        vm.prank(foundation);
        vm.expectRevert(FoundationRewardKernel.CannotPostZeroRoot.selector);
        kernel.postPayoutRoot(bytes32(0), taa);
    }

    function test_postPayoutRoot_revert_duplicate_token() public {
        FoundationRewardKernel.TokenAndAmount[] memory taa = new FoundationRewardKernel.TokenAndAmount[](2);
        taa[0] = FoundationRewardKernel.TokenAndAmount({token: address(unguarded), amount: 1});
        taa[1] = FoundationRewardKernel.TokenAndAmount({token: address(unguarded), amount: 2});
        (bytes32 leaf,) = _buildLeaf(claimer, taa);
        (bytes32 root,) = _singleLeaf(leaf);

        vm.prank(foundation);
        vm.expectRevert(FoundationRewardKernel.DuplicateToken.selector);
        kernel.postPayoutRoot(root, taa);
    }

    // ============ Tests: rejection ============

    function test_rejectNonce_onlyRejector_and_before_finality() public {
        (uint256 nonce,, FoundationRewardKernel.TokenAndAmount[] memory taa) = _postRoot(address(unguarded), 100 ether);

        // Only rejector can reject
        vm.expectRevert(FoundationRewardKernel.NotRejectionMultisig.selector);
        kernel.rejectNonce(nonce);

        // Reject before finality
        vm.prank(rejector);
        kernel.rejectNonce(nonce);

        // Second reject fails
        vm.prank(rejector);
        vm.expectRevert(FoundationRewardKernel.AlreadyRejected.selector);
        kernel.rejectNonce(nonce);

        // New nonce: cannot reject after finality
        vm.prank(foundation);
        (bytes32 leaf,) = _buildLeaf(claimer, taa);
        (bytes32 root,) = _singleLeaf(leaf);
        kernel.postPayoutRoot(root, taa);
        uint256 nonce2 = kernel.$nextPostNonce() - 1;
        vm.warp(block.timestamp + kernel.FINALITY());
        vm.prank(rejector);
        vm.expectRevert(FoundationRewardKernel.AlreadyFinalized.selector);
        kernel.rejectNonce(nonce2);
    }

    function test_rejectNonce_nonexistent_reverts() public {
        vm.prank(rejector);
        vm.expectRevert(FoundationRewardKernel.NonexistentDataAtNonce.selector);
        kernel.rejectNonce(123);
    }

    // ============ Tests: claim (unguarded) ============

    function test_claim_unguarded_happy_path_single_token() public {
        uint256 amount = 250 ether;
        (uint256 nonce, bytes32[] memory proof, FoundationRewardKernel.TokenAndAmount[] memory taa) =
            _postRoot(address(unguarded), amount);

        // Not finalized yet
        vm.expectRevert(FoundationRewardKernel.NotYetFinalized.selector);
        kernel.claimPayout(nonce, proof, taa, donor, recipient, _flags(false, taa.length));

        // Finalize
        vm.warp(block.timestamp + kernel.FINALITY());

        // Approvals and balances
        vm.startPrank(donor);
        unguarded.approve(address(kernel), amount);
        vm.stopPrank();

        vm.prank(claimer);
        kernel.claimPayout(nonce, proof, taa, donor, recipient, _flags(false, taa.length));

        assertEq(unguarded.balanceOf(recipient), amount, "recipient received unguarded");

        // Cannot claim twice
        vm.prank(claimer);
        vm.expectRevert(FoundationRewardKernel.AlreadyClaimedNonce.selector);
        kernel.claimPayout(nonce, proof, taa, donor, recipient, _flags(false, taa.length));

        // Helpers exposure
        assertTrue(kernel.isFinalized(nonce));
        assertTrue(kernel.isClaimed(claimer, nonce));
        assertEq(kernel.getAmountClaimed(nonce, address(unguarded)), amount);
        assertEq(kernel.getMaxReward(nonce, address(unguarded)), amount);
    }

    function test_claim_unguarded_revert_max_exceeded() public {
        uint256 maxAmount = 100 ether;

        // Post with a small global max (postedTAA), but build root for a larger user claim (claimTAA)
        FoundationRewardKernel.TokenAndAmount[] memory postedTAA = new FoundationRewardKernel.TokenAndAmount[](1);
        postedTAA[0] = FoundationRewardKernel.TokenAndAmount({token: address(unguarded), amount: maxAmount});

        FoundationRewardKernel.TokenAndAmount[] memory claimTAA = new FoundationRewardKernel.TokenAndAmount[](1);
        claimTAA[0] = FoundationRewardKernel.TokenAndAmount({token: address(unguarded), amount: maxAmount + 1});

        (bytes32 leaf,) = _buildLeaf(claimer, claimTAA);
        (bytes32 root, bytes32[] memory proof) = _singleLeaf(leaf);

        vm.prank(foundation);
        kernel.postPayoutRoot(root, postedTAA);
        uint256 nonce = kernel.$nextPostNonce() - 1;
        vm.warp(block.timestamp + kernel.FINALITY());

        vm.startPrank(donor);
        unguarded.approve(address(kernel), type(uint256).max);
        vm.stopPrank();

        vm.prank(claimer);
        vm.expectRevert(FoundationRewardKernel.MaxClaimedExceeded.selector);
        kernel.claimPayout(nonce, proof, claimTAA, donor, recipient, _flags(false, claimTAA.length));
    }

    function test_claim_revert_length_mismatch() public {
        (uint256 nonce, bytes32[] memory proof, FoundationRewardKernel.TokenAndAmount[] memory taa) =
            _postRoot(address(unguarded), 1 ether);
        vm.warp(block.timestamp + kernel.FINALITY());

        bool[] memory flags = new bool[](0); // mismatch
        vm.prank(claimer);
        vm.expectRevert(FoundationRewardKernel.LengthsDontMatch.selector);
        kernel.claimPayout(nonce, proof, taa, donor, recipient, flags);
    }

    function test_claim_revert_invalid_proof() public {
        (uint256 nonce,, FoundationRewardKernel.TokenAndAmount[] memory taa) = _postRoot(address(unguarded), 1 ether);
        vm.warp(block.timestamp + kernel.FINALITY());

        // Provide an explicitly wrong non-empty proof so verification fails before any transfer/allowance
        bytes32[] memory badProof = new bytes32[](1);
        badProof[0] = keccak256("bad-proof");

        vm.prank(claimer);
        vm.expectRevert(FoundationRewardKernel.InvalidMerkleProof.selector);
        kernel.claimPayout(nonce, badProof, taa, donor, recipient, _flags(false, taa.length));
    }

    function test_claim_revert_rejected_nonce() public {
        (uint256 nonce, bytes32[] memory proof, FoundationRewardKernel.TokenAndAmount[] memory taa) =
            _postRoot(address(unguarded), 10 ether);
        vm.prank(rejector);
        kernel.rejectNonce(nonce);
        vm.warp(block.timestamp + kernel.FINALITY());
        vm.prank(claimer);
        vm.expectRevert(FoundationRewardKernel.CannotClaimFromRejectedNonce.selector);
        kernel.claimPayout(nonce, proof, taa, donor, recipient, _flags(false, taa.length));
    }

    // ============ Tests: claim (guarded via CFH) ============

    function test_claim_guarded_happy_path_single_token() public {
        uint256 amount = 500 ether;

        // Precompute CFH and allowlist it for guarded token
        address predicted = factory.getCurrentCFH(donor, address(guarded));
        guarded.setAllowlistStatus(predicted, true);

        // Fund donor and move funds to donor's CFH
        vm.startPrank(donor);
        guarded.approve(address(factory), amount);
        factory.transferToCFH(donor, address(guarded), amount);
        vm.stopPrank();

        // Approve kernel as operator to executeFrom
        vm.prank(donor);
        factory.setApprovalStatus(address(kernel), true);

        // Post root for guarded token
        (uint256 nonce, bytes32[] memory proof, FoundationRewardKernel.TokenAndAmount[] memory taa) =
            _postRoot(address(guarded), amount);
        vm.warp(block.timestamp + kernel.FINALITY());

        // Claim as claimer, funds sent to recipient via CFH execute
        vm.prank(claimer);
        kernel.claimPayout(nonce, proof, taa, donor, recipient, _flags(true, taa.length));

        assertEq(guarded.balanceOf(recipient), amount, "recipient received guarded via CFH");

        // CFH should be emptied (no leftover was funded beyond amount)
        assertEq(guarded.balanceOf(predicted), 0, "no leftover at first CFH");

        // Helpers exposure
        assertTrue(kernel.isFinalized(nonce));
        assertTrue(kernel.isClaimed(claimer, nonce));
        assertEq(kernel.getAmountClaimed(nonce, address(guarded)), amount);
        assertEq(kernel.getMaxReward(nonce, address(guarded)), amount);
    }

    function test_claim_guarded_revert_operator_not_approved() public {
        uint256 amount = 1 ether;

        // Pre-fund CFH and allowlist
        address predicted = factory.getCurrentCFH(donor, address(guarded));
        guarded.setAllowlistStatus(predicted, true);
        vm.startPrank(donor);
        guarded.approve(address(factory), amount);
        factory.transferToCFH(donor, address(guarded), amount);
        vm.stopPrank();

        // Post root
        (uint256 nonce, bytes32[] memory proof, FoundationRewardKernel.TokenAndAmount[] memory taa) =
            _postRoot(address(guarded), amount);
        vm.warp(block.timestamp + kernel.FINALITY());

        // Do not approve kernel as operator; should revert from factory
        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(CounterfactualHolderFactory.NotApproved.selector, donor, address(kernel))
        );
        kernel.claimPayout(nonce, proof, taa, donor, recipient, _flags(true, taa.length));
    }

    // ============ Internal utils ============

    function _flags(bool v, uint256 n) internal pure returns (bool[] memory arr) {
        arr = new bool[](n);
        for (uint256 i; i < n; ++i) {
            arr[i] = v;
        }
    }

    // ============ Fuzz / stateful tests ============

    // Multiple claimers over multiple nonces, ensure amountClaimed increments per nonce and total balances flow.
    function testFuzz_multiClaimers_increment_amountClaimed(uint8 count) public {
        // Bound number of claimers
        uint256 n = bound(uint256(count), 2, 8);

        uint256 totalClaimed;

        for (uint256 i = 0; i < n; ++i) {
            address cl = address(uint160(uint256(keccak256(abi.encodePacked("claimer", i)))));
            uint256 amount = (i + 1) * 1 ether;

            FoundationRewardKernel.TokenAndAmount[] memory taa = new FoundationRewardKernel.TokenAndAmount[](1);
            taa[0] = FoundationRewardKernel.TokenAndAmount({token: address(unguarded), amount: amount});

            (bytes32 leaf,) = _buildLeaf(cl, taa);
            (bytes32 root, bytes32[] memory proof) = _singleLeaf(leaf);

            vm.prank(foundation);
            kernel.postPayoutRoot(root, taa);
            uint256 nonce = kernel.$nextPostNonce() - 1;
            vm.warp(block.timestamp + kernel.FINALITY());

            vm.startPrank(donor);
            unguarded.approve(address(kernel), type(uint256).max);
            vm.stopPrank();

            vm.prank(cl);
            kernel.claimPayout(nonce, proof, taa, donor, recipient, _flags(false, 1));

            totalClaimed += amount;

            assertEq(kernel.getAmountClaimed(nonce, address(unguarded)), amount, "per-nonce claimed correct");
            assertTrue(kernel.isClaimed(cl, nonce));
        }

        assertEq(unguarded.balanceOf(recipient), totalClaimed, "recipient total from multi-claims");
    }

    // Mixed guarded/unguarded multi-token in one claim, exercising flags and accounting
    function test_mixed_guarded_unguarded_multi_token() public {
        uint256 amtU = 123 ether;
        uint256 amtG = 321 ether;

        // Allowlist predicted CFH
        address predicted = factory.getCurrentCFH(donor, address(guarded));
        guarded.setAllowlistStatus(predicted, true);

        // Pre-fund CFH for guarded amount
        vm.startPrank(donor);
        guarded.approve(address(factory), amtG);
        factory.transferToCFH(donor, address(guarded), amtG);
        // Approve kernel as operator for guarded and approve ERC20 for unguarded
        factory.setApprovalStatus(address(kernel), true);
        unguarded.approve(address(kernel), amtU);
        vm.stopPrank();

        FoundationRewardKernel.TokenAndAmount[] memory taa = new FoundationRewardKernel.TokenAndAmount[](2);
        taa[0] = FoundationRewardKernel.TokenAndAmount({token: address(unguarded), amount: amtU});
        taa[1] = FoundationRewardKernel.TokenAndAmount({token: address(guarded), amount: amtG});
        bool[] memory flags = new bool[](2);
        flags[0] = false;
        flags[1] = true;

        (bytes32 leaf,) = _buildLeaf(claimer, taa);
        (bytes32 root, bytes32[] memory proof) = _singleLeaf(leaf);
        vm.prank(foundation);
        kernel.postPayoutRoot(root, taa);
        uint256 nonce = kernel.$nextPostNonce() - 1;
        vm.warp(block.timestamp + kernel.FINALITY());

        vm.prank(claimer);
        kernel.claimPayout(nonce, proof, taa, donor, recipient, flags);

        assertEq(unguarded.balanceOf(recipient), amtU);
        assertEq(guarded.balanceOf(recipient), amtG);
        assertEq(kernel.getAmountClaimed(nonce, address(unguarded)), amtU);
        assertEq(kernel.getAmountClaimed(nonce, address(guarded)), amtG);
    }
}

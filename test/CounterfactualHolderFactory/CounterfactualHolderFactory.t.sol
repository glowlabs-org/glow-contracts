// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {CounterfactualHolderFactory} from "src/v2/CounterfactualHolderFactory.sol";
import {CounterfactualHolder} from "src/v2/CounterfactualHolder.sol";
import {Call} from "src/v2/Structs.sol";
import {MockERC20} from "src/testing/MockERC20.sol";

contract CounterfactualHolderFactoryTest is Test {
    CounterfactualHolderFactory internal factory;
    MockERC20 internal token;

    address internal user = address(0xA11CE);
    address internal other = address(0xB0B);

    event TransferToCFH(
        address indexed from, address indexed toUser, address indexed token, address cfh, uint256 amount
    );
    event Execute(address indexed user, address indexed cfh, address indexed token, Call[] calls);

    function setUp() public {
        factory = new CounterfactualHolderFactory();
        token = new MockERC20("Mock", "MOCK", 18);
        token.mint(user, 1_000 ether);
        token.mint(other, 1_000 ether);
    }

    function _currentCFH(address _user) internal view returns (address) {
        return factory.getCurrentCFH(_user, address(token));
    }

    function test_transferToCFH_transfers_and_emits() public {
        uint256 amount = 100 ether;
        address cfh = _currentCFH(user);

        vm.startPrank(user);
        token.approve(address(factory), amount);

        vm.expectEmit(true, true, true, true, address(factory));
        emit TransferToCFH(user, user, address(token), cfh, amount);

        factory.transferToCFH(user, address(token), amount);
        vm.stopPrank();

        assertEq(token.balanceOf(cfh), amount, "CFH should hold transferred amount");
    }

    function testFuzz_transferToCFH_general(address sender, address beneficiary, uint256 amount) public {
        vm.assume(sender != address(0));
        vm.assume(beneficiary != address(0));
        amount = bound(amount, 1, 1_000_000 ether);

        token.mint(sender, amount);

        address cfh = factory.getCurrentCFH(beneficiary, address(token));

        vm.startPrank(sender);
        token.approve(address(factory), amount);
        factory.transferToCFH(beneficiary, address(token), amount);
        vm.stopPrank();

        assertEq(token.balanceOf(cfh), amount, "funds should be at beneficiary's CFH");
    }

    function test_execute_moves_all_funds_to_recipient() public {
        uint256 amount = 250 ether;
        address cfh = _currentCFH(user);

        // Fund the predicted CFH address first
        vm.startPrank(user);
        token.approve(address(factory), amount);
        factory.transferToCFH(user, address(token), amount);
        vm.stopPrank();

        assertEq(token.balanceOf(cfh), amount, "precondition: funds at CFH address");

        // Build calls to transfer entire balance to `other`
        Call[] memory calls = new Call[](1);
        calls[0] =
            Call({target: address(token), data: abi.encodeWithSignature("transfer(address,uint256)", other, amount)});

        vm.expectEmit(true, true, true, false, address(factory));
        emit Execute(user, cfh, address(token), calls);

        vm.prank(user);
        factory.execute(address(token), calls);

        // CFH is now deployed; verify code exists and recipient received funds
        assertGt(address(cfh).code.length, 0, "CFH should have been deployed");
        assertEq(token.balanceOf(other), 1_000 ether + amount, "recipient received funds");
        assertEq(token.balanceOf(cfh), 0, "no leftover at CFH");
    }

    function test_execute_forwards_leftover_to_next_holder() public {
        uint256 amount = 300 ether;
        address firstCFH = _currentCFH(user);

        // Transfer funds to the predicted first CFH
        vm.startPrank(user);
        token.approve(address(factory), amount);
        factory.transferToCFH(user, address(token), amount);
        vm.stopPrank();

        // Prepare a partial transfer so there is leftover
        uint256 sent = 120 ether;
        Call[] memory calls = new Call[](1);
        calls[0] =
            Call({target: address(token), data: abi.encodeWithSignature("transfer(address,uint256)", other, sent)});

        vm.prank(user);
        factory.execute(address(token), calls);

        // After execute, next CFH becomes current
        address nextCFH = _currentCFH(user);

        // Leftover should have been forwarded to the next CFH
        uint256 leftover = amount - sent;
        assertEq(token.balanceOf(nextCFH), leftover, "leftover forwarded to next CFH");

        // Sanity: first CFH deployed and empty
        assertGt(address(firstCFH).code.length, 0, "first CFH deployed");
        assertEq(token.balanceOf(firstCFH), 0, "first CFH emptied");
    }

    function test_getCurrentCFH_matches_create2_formula() public {
        bytes memory initCode = abi.encodePacked(type(CounterfactualHolder).creationCode, abi.encode(token));
        bytes32 salt = keccak256(abi.encodePacked(user, address(token), uint256(0), address(factory)));
        bytes32 initCodeHash = keccak256(initCode);

        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(factory), salt, initCodeHash));
        address predicted = address(uint160(uint256(hash)));

        assertEq(_currentCFH(user), predicted, "create2 prediction should match");
    }

    function predictCFH(address user_, address token_, uint256 nonce) internal view returns (address predicted) {
        bytes memory initCode = abi.encodePacked(type(CounterfactualHolder).creationCode, abi.encode(token_));
        bytes32 salt = keccak256(abi.encodePacked(user_, token_, nonce, address(factory)));
        bytes32 initCodeHash = keccak256(initCode);
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(factory), salt, initCodeHash));
        predicted = address(uint160(uint256(hash)));
    }

    function testFuzz_sequence_no_collisions_smallN(address fuzzUser, address fuzzToken, uint8 steps) public {
        vm.assume(fuzzUser != address(0));
        vm.assume(fuzzToken != address(0));
        uint256 n = bound(uint256(steps), 1, 10);

        address prev = address(0);
        for (uint256 i = 0; i < n; ++i) {
            address p = predictCFH(fuzzUser, fuzzToken, i);
            if (i > 0) {
                assertTrue(p != prev, "collision within short sequence");
            }
            prev = p;
        }
    }

    function testFuzz_predictions_differ_for_user_or_token(address u1, address u2, address t1, address t2) public {
        vm.assume(u1 != address(0) && u2 != address(0));
        vm.assume(t1 != address(0) && t2 != address(0));

        address p_u1_t1 = predictCFH(u1, t1, 0);
        address p_u2_t1 = predictCFH(u2, t1, 0);
        address p_u1_t2 = predictCFH(u1, t2, 0);

        if (u1 != u2) {
            assertTrue(p_u1_t1 != p_u2_t1, "different users should differ");
        }
        if (t1 != t2) {
            assertTrue(p_u1_t1 != p_u1_t2, "different tokens should differ");
        }
    }

    function testFuzz_execute_reverts_on_failed_call_keeps_nonce(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000 ether);

        // Fund initial CFH address
        address cfhBefore = _currentCFH(user);
        vm.startPrank(user);
        token.mint(user, amount);
        token.approve(address(factory), amount);
        factory.transferToCFH(user, address(token), amount);
        vm.stopPrank();

        // Prepare a reverting call
        Reverter rev = new Reverter();
        bytes memory callData = abi.encodeWithSignature("revertAlways()");

        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(rev), data: callData});

        vm.expectRevert(
            abi.encodeWithSelector(CounterfactualHolder.ExecutionFailed.selector, 0, address(rev), callData)
        );
        vm.prank(user);
        factory.execute(address(token), calls);

        // Nonce should not have advanced; current CFH unchanged
        address cfhAfter = _currentCFH(user);
        assertEq(cfhAfter, cfhBefore, "nonce should not advance on failed execute");
        assertEq(token.balanceOf(cfhBefore), amount, "funds remain at CFH on failure");
    }

    function testFuzz_execute_partial_general(uint256 amount, uint256 sent) public {
        amount = bound(amount, 1, 1_000_000 ether);
        sent = bound(sent, 0, amount);

        address firstCFH = _currentCFH(user);
        vm.startPrank(user);
        token.mint(user, amount);
        token.approve(address(factory), amount);
        factory.transferToCFH(user, address(token), amount);
        vm.stopPrank();

        Call[] memory calls = new Call[](1);
        calls[0] =
            Call({target: address(token), data: abi.encodeWithSignature("transfer(address,uint256)", other, sent)});

        vm.prank(user);
        factory.execute(address(token), calls);

        address nextCFH = _currentCFH(user);
        uint256 leftover = amount - sent;
        assertEq(token.balanceOf(nextCFH), leftover, "leftover forwarded to next CFH");
        assertEq(token.balanceOf(firstCFH), 0, "first CFH emptied");
    }
}

// Reverter target used to test CFH revert bubbling
contract Reverter {
    function revertAlways() external pure {
        revert("always");
    }
}

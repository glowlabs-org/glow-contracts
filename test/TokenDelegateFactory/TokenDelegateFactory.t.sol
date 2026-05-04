// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TokenDelegateFactory} from "@/v2/TokenDelegateFactory.sol";
import {TokenDelegateExecutor} from "@/v2/TokenDelegateExecutor.sol";
import {MockERC20} from "@/testing/MockERC20.sol";

/// @dev Beam that, when delegate-called, sweeps a single token's full balance
/// of `address(this)` (the executor) to a sink. Lets us assert tokens reached
/// the executor and the beam ran in its context.
contract SweepBeam {
    function sweep(address token, address to) external {
        IERC20(token).transfer(to, IERC20(token).balanceOf(address(this)));
    }
}

/// @dev Beam that always reverts with a custom error. Used to check the
/// executor bubbles up the original revert payload.
contract RevertBeam {
    error Boom(uint256 x);

    function fail(uint256 x) external pure {
        revert Boom(x);
    }
}

contract TokenDelegateFactoryTest is Test {
    TokenDelegateFactory factory;
    SweepBeam sweepBeam;
    RevertBeam revertBeam;
    MockERC20 tokenA;
    MockERC20 tokenB;

    address user = address(0xA11CE);
    address sink = address(0xBEEF);

    function setUp() public {
        factory = new TokenDelegateFactory();
        sweepBeam = new SweepBeam();
        revertBeam = new RevertBeam();
        tokenA = new MockERC20("MockA", "MA", 18);
        tokenB = new MockERC20("MockB", "MB", 6);
        tokenA.mint(user, 1_000 ether);
        tokenB.mint(user, 1_000 * 1e6);
    }

    function _toks1(address t) internal pure returns (address[] memory a) {
        a = new address[](1);
        a[0] = t;
    }

    function _amts1(uint256 v) internal pure returns (uint256[] memory a) {
        a = new uint256[](1);
        a[0] = v;
    }

    function test_predictAddress_matches_deployed() public {
        uint256 amount = 100 ether;
        uint256 saltBefore = factory.nextSalt();
        address predicted = factory.predictAddress(saltBefore);

        vm.startPrank(user);
        tokenA.approve(address(factory), amount);
        address deployed = factory.exec(
            _toks1(address(tokenA)), _amts1(amount), address(sweepBeam), abi.encodeCall(SweepBeam.sweep, (address(tokenA), sink))
        );
        vm.stopPrank();

        assertEq(deployed, predicted, "deployed address must equal predicted");
        assertEq(factory.nextSalt(), saltBefore + 1, "salt must increment");
    }

    function test_exec_routes_tokens_through_executor_to_sink() public {
        uint256 amount = 250 ether;

        uint256 sinkBefore = tokenA.balanceOf(sink);

        vm.startPrank(user);
        tokenA.approve(address(factory), amount);
        address executor = factory.exec(
            _toks1(address(tokenA)),
            _amts1(amount),
            address(sweepBeam),
            abi.encodeCall(SweepBeam.sweep, (address(tokenA), sink))
        );
        vm.stopPrank();

        assertEq(tokenA.balanceOf(sink) - sinkBefore, amount, "sink should receive full amount");
        assertEq(tokenA.balanceOf(executor), 0, "executor should be empty after sweep");
    }

    function test_exec_with_multiple_tokens() public {
        uint256 amtA = 10 ether;
        uint256 amtB = 5 * 1e6;

        address[] memory toks = new address[](2);
        toks[0] = address(tokenA);
        toks[1] = address(tokenB);
        uint256[] memory amts = new uint256[](2);
        amts[0] = amtA;
        amts[1] = amtB;

        // Sweep only tokenA so we can assert tokenB stayed at the executor.
        vm.startPrank(user);
        tokenA.approve(address(factory), amtA);
        tokenB.approve(address(factory), amtB);
        address executor = factory.exec(
            toks, amts, address(sweepBeam), abi.encodeCall(SweepBeam.sweep, (address(tokenA), sink))
        );
        vm.stopPrank();

        assertEq(tokenA.balanceOf(sink), amtA, "tokenA swept to sink");
        assertEq(tokenB.balanceOf(executor), amtB, "tokenB still at executor (beam didn't sweep it)");
    }

    function test_exec_reverts_on_length_mismatch() public {
        address[] memory toks = new address[](2);
        toks[0] = address(tokenA);
        toks[1] = address(tokenB);
        uint256[] memory amts = new uint256[](1);
        amts[0] = 1;

        vm.prank(user);
        vm.expectRevert(TokenDelegateFactory.LengthMismatch.selector);
        factory.exec(toks, amts, address(sweepBeam), "");
    }

    function test_exec_bubbles_beam_revert() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(RevertBeam.Boom.selector, uint256(42)));
        factory.exec(
            new address[](0), new uint256[](0), address(revertBeam), abi.encodeCall(RevertBeam.fail, (42))
        );
    }

    function test_exec_clears_transient_after_success() public {
        uint256 amount = 1 ether;

        vm.startPrank(user);
        tokenA.approve(address(factory), amount);
        factory.exec(
            _toks1(address(tokenA)),
            _amts1(amount),
            address(sweepBeam),
            abi.encodeCall(SweepBeam.sweep, (address(tokenA), sink))
        );
        vm.stopPrank();

        // Transient storage is cleared at the end of the tx anyway, but
        // `tclear()` should also zero the length within the same tx so a
        // follow-up read returns empty even before tx end.
        // We can only observe this from a separate tx; the post-tx read
        // here verifies the no-leak property via a fresh call frame.
        assertEq(factory.getTransientBeam(), address(0));
        assertEq(factory.getTransientBeamData().length, 0);
    }

    function test_exec_two_consecutive_use_distinct_addresses() public {
        uint256 amount = 1 ether;

        vm.startPrank(user);
        tokenA.approve(address(factory), amount * 2);

        address e1 = factory.exec(
            _toks1(address(tokenA)),
            _amts1(amount),
            address(sweepBeam),
            abi.encodeCall(SweepBeam.sweep, (address(tokenA), sink))
        );
        address e2 = factory.exec(
            _toks1(address(tokenA)),
            _amts1(amount),
            address(sweepBeam),
            abi.encodeCall(SweepBeam.sweep, (address(tokenA), sink))
        );
        vm.stopPrank();

        assertTrue(e1 != e2, "consecutive execs must deploy at different addresses");
    }

    function test_exec_pulls_from_msgSender_not_user() public {
        // A separate party (operator) calls exec, pulling from itself, not `user`.
        address operator = address(0xCAFE);
        uint256 amount = 7 ether;
        tokenA.mint(operator, amount);

        vm.startPrank(operator);
        tokenA.approve(address(factory), amount);
        factory.exec(
            _toks1(address(tokenA)),
            _amts1(amount),
            address(sweepBeam),
            abi.encodeCall(SweepBeam.sweep, (address(tokenA), sink))
        );
        vm.stopPrank();

        assertEq(tokenA.balanceOf(operator), 0, "operator's funds should be drawn");
        assertEq(tokenA.balanceOf(sink), amount, "sink received");
    }
}

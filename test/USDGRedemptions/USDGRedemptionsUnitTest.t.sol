// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "@glow/testing/TestGCC.sol";
import "forge-std/console.sol";
import {IGCA} from "@glow/interfaces/IGCA.sol";
import {MockGCA} from "@glow/MinerPoolAndGCA/mock/MockGCA.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import "forge-std/StdUtils.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {TestGLOW} from "@glow/testing/TestGLOW.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MerkleProofLib} from "@solady/utils/MerkleProofLib.sol";
import {MockMinerPoolAndGCA} from "@glow/MinerPoolAndGCA/mock/MockMinerPoolAndGCA.sol";
import {MockUSDC} from "@glow/testing/MockUSDC.sol";
import {IMinerPool} from "@glow/interfaces/IMinerPool.sol";
import {BucketSubmission} from "@glow/MinerPoolAndGCA/BucketSubmission.sol";
import {VetoCouncil} from "@glow/VetoCouncil/VetoCouncil.sol";
import {MockGovernance} from "@glow/testing/MockGovernance.sol";
import {IGovernance} from "@glow/interfaces/IGovernance.sol";
import {TestGCC} from "@glow/testing/TestGCC.sol";
import {HalfLife} from "@glow/libraries/HalfLife.sol";
import {GrantsTreasury} from "@glow/GrantsTreasury.sol";
import {Holding, ClaimHoldingArgs, ISafetyDelay, SafetyDelay} from "@glow/SafetyDelay.sol";
import {UnifapV2Factory} from "@unifapv2/UnifapV2Factory.sol";
import {UnifapV2Router} from "@unifapv2/UnifapV2Router.sol";
import {WETH9} from "@glow/UniswapV2/contracts/test/WETH9.sol";
import {TestUSDG} from "@glow/testing/TestUSDG.sol";
import {USDG} from "@glow/USDG.sol";
import {USDGRedemption} from "@glow/USDGRedemption.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {USDGRedemptionsBaseTest} from "./USDGRedemptionsBase.t.sol";
import {LiquidityQueueLib} from "@glowswap/core/libraries/LiquidityQueueLib.sol";

contract USDGRedemptionsUnitTest is USDGRedemptionsBaseTest {
    // /* -------------------------------------------------------------------------- */
    // /*                                 Unit Tests                                 */
    // /* -------------------------------------------------------------------------- */

    function testConstructorSetsImmutableRefs() public {
        assertEq(address(redemption.usdgToken()), address(usdg));
        assertEq(address(redemption.usdcToken()), address(usdc));
        assertEq(redemption.withdrawGuardian(), WITHDRAW_GUARDIAN);
    }

    /* -------------------------------------------------------------------------- */
    /*                               exchange() tests                             */
    /* -------------------------------------------------------------------------- */

    function testExchangeRevertsOnZeroAmount() public {
        vm.expectRevert(USDGRedemption.ZeroNotAllowed.selector);
        redemption.exchange(0);
    }

    function testExchangeRevertsIfContractNotFunded() public {
        // Mint USDG to SIMON and approve redemption
        uint256 amount = 1_000 * 1e6;
        _mintUSDG(SIMON, amount);
        vm.startPrank(SIMON);
        usdg.approve(address(redemption), amount);
        vm.expectRevert(); // SafeERC20 revert because balance is 0
        redemption.exchange(amount);
        vm.stopPrank();
    }

    function testExchangeSuccess() public {
        uint256 amount = 2_500 * 1e6;
        // Fund contract with USDC reserves so it can fulfil redemption
        _topUp(address(this), amount);

        // Mint USDG to SIMON and approve redemption
        _mintUSDG(SIMON, amount);
        vm.startPrank(SIMON);
        usdg.approve(address(redemption), amount);

        uint256 usdcBalBefore = usdc.balanceOf(SIMON);
        uint256 usdgBalBefore = usdg.balanceOf(SIMON);

        // vm.expectEmit(true, true, false, true);
        // emit USDGRedemption.Exchanged(SIMON, amount);
        redemption.exchange(amount);

        uint256 usdcBalAfter = usdc.balanceOf(SIMON);
        uint256 usdgBalAfter = usdg.balanceOf(SIMON);

        assertEq(usdcBalAfter - usdcBalBefore, amount, "USDC not received 1:1");
        assertEq(usdgBalBefore - usdgBalAfter, amount, "USDG not burned");
        vm.stopPrank();

        // Contract's USDC balance should now be zero
        assertEq(usdc.balanceOf(address(redemption)), 0);
    }

    /* -------------------------------------------------------------------------- */
    /*                             withdrawUSDC() tests                           */
    /* -------------------------------------------------------------------------- */

    function testWithdrawUSDCOnlyGuardian() public {
        uint256 amount = 5_000 * 1e6;
        _topUp(address(this), amount);

        // Non guardian should revert
        vm.prank(SIMON);
        vm.expectRevert(USDGRedemption.NotWithdrawGuardian.selector);
        redemption.withdrawUSDC(amount);

        // Guardian can withdraw
        vm.startPrank(WITHDRAW_GUARDIAN);
        uint256 balBefore = usdc.balanceOf(WITHDRAW_GUARDIAN);
        // vm.expectEmit(true, true, false, true);
        // emit USDGRedemption.Withdrawn(WITHDRAW_GUARDIAN, amount);
        redemption.withdrawUSDC(amount);
        uint256 balAfter = usdc.balanceOf(WITHDRAW_GUARDIAN);
        vm.stopPrank();

        assertEq(balAfter - balBefore, amount, "Guardian did not receive USDC");
        assertEq(usdc.balanceOf(address(redemption)), 0, "USDC not fully withdrawn");
    }

    function testWithdrawUSDCClampedToBalance() public {
        uint256 initial = 1_000 * 1e6;
        _topUp(address(this), initial);

        // Withdraw amount > balance
        vm.startPrank(WITHDRAW_GUARDIAN);
        // vm.expectEmit(true, true, false, true);
        // emit USDGRedemption.Withdrawn(WITHDRAW_GUARDIAN, initial);
        redemption.withdrawUSDC(initial * 2);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(redemption)), 0, "Remaining balance should be zero");
        assertEq(usdc.balanceOf(WITHDRAW_GUARDIAN), initial, "Guardian should get full balance");
    }

    /* -------------------------------------------------------------------------- */
    /*                    withdrawUSDC_CircuitBreakerOn() tests                   */
    /* -------------------------------------------------------------------------- */

    function testWithdrawUSDC_CircuitBreakerOn_RevertsWhenOff() public {
        uint256 amount = 500 * 1e6;
        _topUp(address(this), amount);
        vm.expectRevert(USDGRedemption.CircuitBreakerNotOn.selector);
        redemption.withdrawUSDC_CircuitBreakerOn();
    }

    function testWithdrawUSDC_CircuitBreakerOn_SucceedsAndAnyoneCanCall() public {
        uint256 amount = 7_777 * 1e6;
        _topUp(address(this), amount);
        // Activate circuit breaker
        _activateCircuitBreaker();

        // Anyone (e.g., bidder1) can call
        vm.prank(bidder1);
        // vm.expectEmit(true, true, false, true);
        // emit USDGRedemption.Withdrawn(WITHDRAW_GUARDIAN, amount);
        redemption.withdrawUSDC_CircuitBreakerOn();

        assertEq(usdc.balanceOf(address(redemption)), 0, "All USDC should be withdrawn");
        assertEq(usdc.balanceOf(WITHDRAW_GUARDIAN), amount, "Guardian did not receive full balance");
    }

    /* -------------------------------------------------------------------------- */
    /*                              Getter Functions                              */
    /* -------------------------------------------------------------------------- */

    function testGetters() public {
        assertEq(address(redemption.usdgToken()), address(usdg));
        assertEq(address(redemption.usdcToken()), address(usdc));
        assertEq(redemption.withdrawGuardian(), WITHDRAW_GUARDIAN);
    }
}

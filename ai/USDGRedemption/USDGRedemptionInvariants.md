# USDGRedemption – Invariants Catalogue

This document enumerates every **safety** and **liveness** property that must *always* hold for `USDGRedemption.sol`.  Each item is phrased as an assertion that should be verified with invariant tests or property–based fuzzing.

> Notation:
> • `s`   – pre-state, `s'` – post-state  
> • `pos` – `LiquidityQueueLib.Position`  
> • `qid` – queue / position identifier  
> • All arithmetic is **uint256**, unless stated otherwise.

## 1. Deployment & Global Constants
1. `i_USDG != address(0)` and `i_USDC != address(0)` and `i_WITHDRAW_GUARDIAN != address(0)`.
2. `WITHDRAW_DELAY == 14 days` ( `2 weeks` ).
3. `BURN_ADDRESS == 0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF`.
4. Liquidity queue state is internally coherent at all times:
   - `totalLiquidityRequested ≥ liquidityProgress ≥ totalClaimed`.
5. `nextWithdrawPositionId` is monotonically increasing by **exactly one** per successful `createWithdrawPosition` call.

## 2. Authorisation & Access Control
1. `createWithdrawPosition` & `withdraw` succeed **iff** `isAuthorized(msg.sender) == true`; otherwise they revert with `NotAuthorized()`.
2. `authorize` & `authorizeBulk` can only be called by `withdrawGuardian()`; all other callers revert with `NotWithdrawGuardian()`.
3. `authorizeBulk` updates each address exactly once and emits exactly one `AuthorizationUpdated` event per address.

## 3. Circuit-Breaker Behaviour
1. Whenever `circuitBreakerActive() == true` (i.e. `USDG.permanentlyFreezeTransfers()` returns `true`):
   - All calls to `createWithdrawPosition` & `withdraw` must revert with `CircuitBreakerActive()`.
2. When `circuitBreakerActive() == false` the functions may proceed (subject to other checks).

## 4. Creating a Withdraw Position
Given `amount > 0` and caller `u`:
1. Exactly `amount` USDG is transferred from `u` to `BURN_ADDRESS` and **burned** (total USDG supply decreases by `amount`).
2. A new position `pos` is created with id `qid = s.nextWithdrawPositionId` *before* the increment.
3. Post-state:
   - `pos.owner == u`.
   - `pos.liquidityRequested == amount`.
   - `pos.amountWithdrawn == 0`.
   - `positionWithdrawTimestamp[qid] == block.timestamp + WITHDRAW_DELAY`.
4. Queue state:
   - `liquidityQueue.totalLiquidityRequested' == totalLiquidityRequested + amount`.
   - `liquidityProgress` & `totalClaimed` **unchanged**.
5. Event `WithdrawPositionCreated` is emitted with the exact arguments above.

## 5. Liquidity Top-Up
Assume caller supplies `maxAmount`:
1. Let `pending = liquidityQueue.getPendingLiquidityInQueue()`.
2. `amountToRequest == min(maxAmount, pending)`.
3. Post-state:
   - If `amountToRequest == 0` the function is a no-op and emits no event.
   - Otherwise:
     - `i_USDC` balance of contract increases by `amountToRequest` and caller decreases equivalently.
     - `liquidityQueue.liquidityProgress' == liquidityProgress + amountToRequest`.
4. Event `RedemptionLiquidityToppedUp` emitted **iff** `amountToRequest > 0` with correct amount.

## 6. Claiming ( withdraw )
Given a valid position `qid` owned by `u`:
1. **Time lock** – require `block.timestamp ≥ positionWithdrawTimestamp[qid]`, otherwise revert `ClaimTooEarly()`.
2. **Available liquidity** – let
   - `left = pos.liquidityRequested - pos.amountWithdrawn`  
   - `available = liquidityQueue.getLiquidityAvailableToClaim()`  
   - `claim = min(left, available)`
   - If `claim == 0` revert `LiquidityQueueLib.InsufficientLiquidityInQueue()`.
3. Post-state:
   - `pos.amountWithdrawn' == pos.amountWithdrawn + claim`.
   - `claim ≤ left` and `pos.amountWithdrawn' ≤ pos.liquidityRequested`.
   - `liquidityQueue.totalClaimed' == totalClaimed + claim`.
   - `i_USDC` balance of contract decreases by `claim` and `u` increases equivalently.
4. **Position closed** when `pos.amountWithdrawn' == pos.liquidityRequested` (indicated by `pos.owner == address(0)` in library).
5. Event `WithdrawPositionClaimed` emitted with exact values.

## 7. ERC-20 & Balance Safety
1. Contract never holds USDG; all incoming USDG is immediately forwarded to `BURN_ADDRESS`.
2. The sum of:
   - Current contract `i_USDC` balance, plus
   - `liquidityQueue.totalClaimed`
   equals the cumulative `RedemptionLiquidityToppedUp` amounts **minus** any dust left in queue (`totalLiquidityRequested - liquidityProgress`).
3. No function (other than constructor) can send ether or tokens to non-deterministic recipients; transfers are strictly controlled.

## 8. Re-entrancy Protection
`createWithdrawPosition`, `withdraw`, and `topUpLiquidity` are all free from re-entrancy due to:
1. `nonReentrant` modifier on state-changing external functions that move assets (`createWithdrawPosition`, `withdraw`).
2. For `topUpLiquidity` the only external call is `i_USDC.safeTransferFrom`, which follows the Checks-Effects-Interactions pattern (state is updated *after* transfer) — no state-changing external call follows user token transfer.

## 9. Position Ownership & Integrity
1. **Sole claimant** – `withdraw(qid)` succeeds **iff** `msg.sender == pos.owner`; any other caller reverts with `LiquidityQueueLib.CallerNotLiquidityPositionOwner()`.
2. **Closed positions are immutable** – Once `pos.owner` is set to `address(0)` (i.e. position fully withdrawn), any further call to `withdraw(qid)` must revert with `LiquidityQueueLib.NonexistentOrClosedPosition()`.
3. **Position id uniqueness** – A `qid` can never be re-used for a different owner; for all `qid < nextWithdrawPositionId` exactly one `WithdrawPositionCreated` event exists.
4. **Monotonic release time** – `positionWithdrawTimestamp[qid]` is assigned exactly once at creation and can never decrease.
5. **Zero-value guard** – `createWithdrawPosition(0)` must revert (burning zero USDG is disallowed).

## 10. Queue Accounting Bounds
1. `liquidityProgress ≤ totalLiquidityRequested` at all times.
2. `totalClaimed ≤ liquidityProgress` at all times.
3. After any state transition, `totalLiquidityRequested`, `liquidityProgress`, and `totalClaimed` each fit within `uint256` without overflow.
4. `topUpLiquidity` can never increase `liquidityProgress` beyond `totalLiquidityRequested` (excess transfers are rejected by `_min`).

## 11. Conservation between USDG burns and USDC payouts
1. Cumulative USDG burned (`Σ amount` in all `WithdrawPositionCreated`) equals `liquidityQueue.totalLiquidityRequested`.
2. The cumulative USDC paid out to users (`Σ amountClaimed` over all `WithdrawPositionClaimed`) equals `liquidityQueue.totalClaimed`.
3. Therefore, over the lifetime of the contract:
   - `Σ USDG burned == Σ USDC ever claimable` (1 USDG → 1 USDC),
   - No net USDC can be withdrawn without a corresponding prior USDG burn.

---
These invariants should be translated into automated tests using a combination of **hardhat-console asserts**, **echidna**, or **foundry**'s invariant testing framework to guarantee that `USDGRedemption` behaves correctly under arbitrary call sequences and hostile actors.

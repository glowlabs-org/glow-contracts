Findings
| ID | Severity* | Title | Location | Description & Impact | Recommendation |
| --- | --- | --- | --- | --- | --- |
| 1 | High | Withdrawal guardian can irreversibly lock user funds | USDGRedemption.sol:`authorize()` / `_checkAuthorized()` | Withdrawals require the caller to remain `authorized`; the guardian can de-authorize users after they burn USDG, causing `withdraw()` to revert and funds to be trapped. | Decouple withdrawal permission from current authorization status or implement irrevocable per-position authorization snapshot at creation. |
| 2 | High | Circuit-breaker permanently freezes redemptions | USDGRedemption.sol:`_checkCircuitBreakerActive()` | If USDG's `permanentlyFreezeTransfers` flag is set after positions are opened, both `createWithdrawPosition()` and `withdraw()` revert forever, locking all queued USDC. | Allow redemptions when circuit-breaker is active or add an admin emergency release path. |
| 3 | Medium | Potential re-entrancy in `topUpLiquidity` | USDGRedemption.sol:`topUpLiquidity()` | Function lacks `nonReentrant`; a malicious ERC20 could callback during `safeTransferFrom`, re-entering before liquidity progress is updated and causing inconsistent state. | Add `nonReentrant` or update state before external calls. |
| 4 | Medium | USDG supply not burned on redemption | USDGRedemption.sol:`createWithdrawPosition()` | Tokens are merely transferred to a burn address; total supply remains inflated, which may break accounting or governance relying on supply metrics. | Call `USDG.burn()` or have USDG implement and expose a true burn function. |
| 5 | Low | Naming deviates from style conventions | USDGRedemption.sol:209,214 | Functions `USDGToken()` / `USDCToken()` violate mixedCase guideline, potentially triggering static-analysis warnings. | Rename to `usdgToken()` / `usdcToken()`. |

Severity Methodology
- Critical – total fund loss or permanent system brick.
- High – significant fund loss or lock feasible under plausible conditions.
- Medium – partial loss, accounting errors, or DoS requiring edge cases.
- Low – minor impact, griefing, or best-practice deviation.
- Informational – style, gas, or clarity suggestions.

Additional Observations
- Gas: Storing `releaseTimestamp` in a separate mapping could be packed into the position struct for cheaper reads.
- Readability: Consider prefix `_liquidityQueue` instead of `$liquidityQueue` to avoid unconventional symbols.

Recommended Next Steps
- Assess authorization model and circuit-breaker interaction to avoid fund lock scenarios.
- Patch re-entrancy vector and implement proper burn mechanics.
- Run comprehensive unit and integration tests covering edge-cases highlighted above.

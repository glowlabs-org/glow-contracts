Findings
| ID | Severity* | Title | Location | Description & Impact | Recommendation |
|----|-----------|-------|----------|----------------------|----------------|
| 01 | Critical | Unrestricted Circuit-Breaker Freeze & USDC Drain | USDGRedemption.sol:46-60 (`withdrawUSDC_CircuitBreakerOn`) | Any address can permanently freeze USDG transfers and route **all** contract USDC to the guardian, bricking the system and blocking redemptions. | Restrict function to the guardian (or governance) and/or separate the freeze and withdrawal actions behind timelock & multi-sig approval. |
| 02 | High | Tokens Not Actually Burned – Supply Inflation Risk | USDGRedemption.sol:31-38 (`exchange`) | Sending USDG to `0xFFF…` does not reduce `totalSupply`; outstanding USDG remain counted while USDC backing leaves, leading to insolvent reserve accounting. | Replace with `i_USDG.burnFrom(msg.sender, amountUSDG)` or implement a true burn mechanism that decrements `totalSupply`. |
| 03 | High | Decimal Mismatch – 1:1 Redemption Incorrect | USDGRedemption.sol:35-37 (`exchange`) | If USDG has 18 decimals and USDC 6, a "1:1" transfer misprices by **1e12**, causing major fund loss or user under-payment. | Normalize amounts by token decimals or ensure both tokens share identical decimals. |
| 04 | Medium | Ignored `transferFrom` Return Value | USDGRedemption.sol:33 (`exchange`) | `ERC20.transferFrom` can return `false` without reverting; ignoring it may leave USDG untouched while still sending USDC. | Use `SafeERC20.safeTransferFrom` or explicitly check the boolean return. |
| 05 | Low | Missing Withdrawal Events | `withdrawUSDC`, `withdrawUSDC_CircuitBreakerOn` | Lack of events hampers off-chain accounting and auditability of treasury movements. | Emit `Withdrawn(address,uint256)` events on each USDC withdrawal. |
| 06 | Informational | Unused Import | USDGRedemption.sol:6 | `import {ERC20} …` is never referenced, increasing byte-code size slightly. | Remove unused import. |

Severity Methodology
- Critical – exploit can steal or lock all funds or permanently brick the system
- High – significant loss/lock of funds or governance seizure under plausible conditions
- Medium – incorrect accounting, partial DoS, or fund loss that needs edge-case/user error
- Low – minor financial impact, griefing, or best-practice violation
- Informational – style, gas optimisations, clarity issues

Additional Observations
- Consider batching multiple redemptions to reduce gas.
- Re-entrancy guards are correctly applied, but internal state changes could be moved before external calls to further harden.

Recommended Next Steps
- Patch Critical/High findings and re-deploy.
- Add comprehensive unit tests covering decimals, burn logic, and circuit-breaker flows.
- Perform a follow-up audit after fixes.

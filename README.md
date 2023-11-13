# Glow Contracts
Full Documentation can be found  
<a href="https://solidity.glowlabs.org">here</a>

| Filename | Code | Comment |
|----------|------|---------|
| BatchRetire | 26 | 41 |
| BucketSubmission | 99 | 156 |
| CarbonCreditDutchAuction | 124 | 93 |
| EarlyLiquidity | 106 | 194 |
| GCA | 440 | 289 |
| GCASalaryHelper | 203 | 161 |
| GCC | 276 | 183 |
| GLOW | 329 | 260 |
| GlowUnlocker | 50 | 14 |
| Governance | 811 | 535 |
| GrantsTreasury | 51 | 55 |
| HalfLife | 14 | 16 |
| HalfLifeCarbonCreditAuction | 17 | 17 |
| HoldingContract | 107 | 136 |
| ICarbonCreditAuction | 9 | 24 |
| IEarlyLiquidity | 14 | 27 |
| IGCA | 77 | 116 |
| IGCC | 78 | 169 |
| IGlow | 49 | 80 |
| IGovernance | 102 | 100 |
| IGrantsTreasury | 13 | 39 |
| IMinerPool | 44 | 59 |
| IVetoCouncil | 14 | 35 |
| ImpactCatalyst | 114 | 62 |
| MinerPoolAndGCA | 255 | 165 |
| VestingMathLib | 32 | 25 |
| VetoCouncil | 79 | 55 |
| VetoCouncilSalaryHelper | 205 | 189 |
| Total | 3738 | 3295 |


## Requirements
* Rust Installed
* NodeJS Installed
* Python3 Installed

## Commands

### Install
```make install```

## Test
```forge test --ffi```




#### Set Your Environment Variables
```env
EARLY_LIQUIDITY_NUM_RUNS = 5 #times to run the custom fuzzer on early liquidity
EARLY_LIQUIDITY_DEPTH_PER_RUN = 100 #depth per run on each fuzz run
SAVE_EARLY_LIQUIDITY_RUNS = true # true if you want to store the output of each run to a csv
```

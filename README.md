# Glow Contracts
Full Documentation can be found  
<a href="https://solidity.glowlabs.org">here</a>

| Filename | Code | Comment |
|----------|------|---------|
| BucketSubmission | 139 | 190 |
| CarbonCreditDutchAuction | 124 | 91 |
| EarlyLiquidity | 106 | 194 |
| GCA | 423 | 213 |
| GCASalaryHelper | 203 | 163 |
| GCC | 172 | 138 |
| GLOW | 329 | 260 |
| Governance | 848 | 541 |
| GrantsTreasury | 51 | 55 |
| HalfLife | 14 | 16 |
| HalfLifeCarbonCreditAuction | 17 | 17 |
| HoldingContract | 111 | 139 |
| ICarbonCreditAuction | 9 | 24 |
| IEarlyLiquidity | 14 | 27 |
| IGCA | 62 | 81 |
| IGCC | 34 | 91 |
| IGlow | 49 | 80 |
| IGovernance | 109 | 99 |
| IGrantsTreasury | 13 | 39 |
| IMinerPool | 38 | 48 |
| IVetoCouncil | 14 | 35 |
| MinerPoolAndGCA | 310 | 192 |
| VestingMathLib | 32 | 25 |
| VetoCouncil | 79 | 55 |
| VetoCouncilSalaryHelper | 205 | 188 |
| Total | 3505 | 3001 |


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

# Glow Contracts
Full Documentation can be found  
<a href="https://solidity.glowlabs.org">here</a>

## Requirements
* Rust Installed
* NodeJS Installed
* Python3 Installed

## Commands

### Install
```make install```

## Test
```forge test --ffi```

### Setup:


#### Set Your Environment Variables
```env
EARLY_LIQUIDITY_NUM_RUNS = 5 #times to run the custom fuzzer on early liquidity
EARLY_LIQUIDITY_DEPTH_PER_RUN = 100 #depth per run on each fuzz run
SAVE_EARLY_LIQUIDITY_RUNS = true # true if you want to store the output of each run to a csv
```

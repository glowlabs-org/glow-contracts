# Glow Contracts


## Commands

### Install
```forge install && npm install```

### Setup:
#### Set Your Environment Variables
```env
EARLY_LIQUIDITY_NUM_RUNS = 5 #times to run the custom fuzzer on early liquidity
EARLY_LIQUIDITY_DEPTH_PER_RUN = 100 #depth per run on each fuzz run
SAVE_EARLY_LIQUIDITY_RUNS = true # true if you want to store the output of each run to a csv
```

### Test:
```make test```

#### Test Early Liquidity:
```make test.earlyLiquidity```
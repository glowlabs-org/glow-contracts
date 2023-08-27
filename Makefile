
# --- [ Solc ] -----------------------------------------------------------------------------------
install-solc :; pip install solc-select
install-solc-0.8.21 :; solc-select install 0.8.21
use-solc-0.8.21 :; solc-select use 0.8.21


# --- [Gen HTML] requires linux or wsl
gen-lcov :; forge coverage --report lcov

gen-html :;  make gen-lcov && genhtml -o report --branch-coverage lcov.info


# --- [ Test ] -----------------------------------------------------------------------------------
run-coverage :; forge coverage;
test.no.ffi :;  forge test --no-match-test "test_MinerPoolFFI"
test.ffi :; forge test --ffi 


# --- [ Specific Tests ] -----------------------------------------------------------------------------------
test.minerpool.math :; forge test --match-path test/temp/MinerDistributionMath.t.sol -vvv --ffi
test.earlyLiquidity :; forge test --match-contract EarlyLiquidityTest -vvv && npx hardhat test
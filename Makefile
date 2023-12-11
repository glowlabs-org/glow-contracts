
-include .env

# --- [ Solc ] -----------------------------------------------------------------------------------
install-solc :; pip install solc-select
install-solc-0.8.21 :; solc-select install 0.8.21
use-solc-0.8.21 :; solc-select use 0.8.21
compile-rust :;  rustc test/Governance/ffi/half_life.rs --out-dir  ./test/Governance/ffi/  && \
				rustc test/Governance/ffi/divergence_check.rs --out-dir  ./test/Governance/ffi/  


install :; forge install --no-commit && npm install
hardhat-test :; make hardhat.test.earlyLiquidity 

# --- [Gen HTML] requires linux or wsl
gen-lcov :; forge coverage --ffi --report lcov

gen-html :;  make gen-lcov && genhtml -o report --branch-coverage lcov.info --ignore-errors category


# --- [ Test ] -----------------------------------------------------------------------------------
run-coverage :; forge coverage;
test.no.ffi :;  forge test --no-match-test "test_MinerPoolFFI"
test.ffi :; forge test --ffi 
test.all :; forge test --ffi -vv && make hardhat-test

# --- [ Specific Tests ] -----------------------------------------------------------------------------------
test.minerpool.math :; forge test --match-path test/temp/MinerDistributionMath.t.sol -vvv --ffi
hardhat.test.earlyLiquidity :; npx hardhat test test/EarlyLiquidity/EarlyLiquidity.test.ts
test.earlyLiquidity :; forge test --match-contract EarlyLiquidityTest -vvv && make hardhat.test.earlyLiquidity
test.minerPoolAndGCA :; forge test --match-contract MinerPoolAndGCATest --ffi -vv

# --- [ Gas Snapshot] -----------------------------------------------------------------------------------
gas.snapshot :; forge snapshot --gas-report --ffi 

#---- [Deployments] -----------------------------------------------------------------------------------
deploy.testnet.gcc :; forge script script/Testnet/DeployGCC.s.sol --rpc-url ${GOERLI_RPC_URL} --broadcast -vvvv --private-key ${PRIVATE_KEY}  \
--etherscan-api-key ${ETHERSCAN_API_KEY} --verify --retries 10 --delay 10

deploy.testnet.batch-retire :; forge script script/Testnet/DeployBatchRetire.s.sol --rpc-url ${GOERLI_RPC_URL} --broadcast -vvvv --private-key ${PRIVATE_KEY}  \
--etherscan-api-key ${ETHERSCAN_API_KEY} --verify --retries 10 --delay 10

deploy.full.testnet :; forge script script/Testnet/DeployFull.s.sol --rpc-url ${GOERLI_RPC_URL} --broadcast -vvvv --private-key ${PRIVATE_KEY}  \
--etherscan-api-key ${ETHERSCAN_API_KEY} --verify --retries 10 --delay 10

deploy.guardedlaunch.full.testnet :; forge script script/Testnet/DeployGuardedLaunch.s.sol --rpc-url ${GOERLI_RPC_URL} --broadcast -vvvv --private-key ${PRIVATE_KEY}  \
--etherscan-api-key ${ETHERSCAN_API_KEY} --verify --retries 10 --delay 10


deploy.full.anvil :; forge script script/Testnet/DeployFull.s.sol --rpc-url  http://127.0.0.1:8545 --broadcast -vvvv --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

#---- [solhint] -----------------------------------------------------------------------------------
solhint :; find ./src -type f \( -name "*.sol"  \
 		! -path "./src/temp/*" \
		! -path "./src/testing/*" \
		! -path "./src/libraries/ABDKMath64x64.sol"  \
		! -path "./src/UnifapV2/*" \
		! -path "./src/libraries/UniswapV2Library.sol" \
		! -path "./src/interfaces/IUniswapV2Pair.sol" \
		! -path "./src/UniswapV2/*" \
		! -path "./src/MinerPoolAndGCA/mock/*" \) \
		 -exec solhint {} +



cloc:
	@FILES=$$(find ./src -type f \( -name "*.sol"  \
	 ! -path "./src/temp/*" ! -path "./src/testing/*" \
	 ! -path "./src/libraries/ABDKMath64x64.sol" \
	 ! -path "./src/MinerPoolAndGCA/mock/*" \
	 ! -path "./src/UnifapV2/*" \
	 ! -path "./src/libraries/UniswapV2Library.sol" \
	 ! -path "./src/interfaces/IUniswapV2Pair.sol" \
	 ! -path "./src/interfaces/IUniswapRouterV2.sol" \
	 ! -path "./src/UniswapV2/*" \)); \
	if [ -n "$$FILES" ]; then \
		for file in $$FILES; do \
			echo "Processing $$file"; \
			BASENAME=$$(basename $$file .sol); \
			cloc --json $$file >> "cloc_outputs/$$BASENAME.json"; \
		done; \
	else \
		echo "No files found."; \
	fi \
	&& python3 repo-utils/cloc/gen-markdown-table.py

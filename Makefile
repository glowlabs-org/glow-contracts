
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

deploy.batch_commit.mainnet :; forge script script/Mainnet/DeployBatchCommit.s.sol --rpc-url ${MAINNET_RPC} --broadcast -vvvv --private-key ${MAINNET_PRIVATE_KEY}  \
--etherscan-api-key ${ETHERSCAN_API_KEY} --verify --retries 10 --delay 10

deploy.full.quickperiod.testnet :; forge script script/Testnet/DeployFullQuickBuckets.s.sol --rpc-url ${GOERLI_RPC_URL} --broadcast -vvvv --private-key ${PRIVATE_KEY}  \
--etherscan-api-key ${ETHERSCAN_API_KEY} --verify --retries 10 --delay 10

deploy.guardedlaunch.full.testnet :; forge script script/Testnet/DeployGuardedLaunch.s.sol --rpc-url ${GOERLI_RPC_URL} --broadcast -vvvv --private-key ${PRIVATE_KEY}  \
--etherscan-api-key ${ETHERSCAN_API_KEY} --verify --retries 10 --delay 10



deploy.guardedlaunch.full.replica :; forge script script/Testnet/DeployMainnetReplica.s.sol --rpc-url ${GOERLI_RPC_URL} --broadcast -vvvv --private-key ${PRIVATE_KEY}  \
--etherscan-api-key ${ETHERSCAN_API_KEY} --verify --retries 10 --delay 10


deploy.guardedlaunch.mainnet :; forge script script/Mainnet/DeployGuardedLaunch.s.sol --rpc-url ${MAINNET_RPC} --broadcast -vvvv --private-key ${MAINNET_PRIVATE_KEY}  \
--etherscan-api-key ${ETHERSCAN_API_KEY} --verify --retries 10 --delay 10

deploy.full.anvil :; forge script script/Testnet/DeployFull.s.sol --rpc-url  http://127.0.0.1:8545 --broadcast -vvvv --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

setlp.goerli :; forge script script/Testnet/SetLP.s.sol --rpc-url ${GOERLI_RPC_URL} --broadcast -vvvv --private-key ${PRIVATE_KEY}  

panic.verify :;  forge verify-contract 0x85fbB04DEBBDEa052a6422E74bFeA57B17e50A80 CarbonCreditDescendingPriceAuction --chain-id 1 --libraries src/libraries/HalfLifeCarbonCreditAuction.sol:HalfLifeCarbonCreditAuction:0xd178525026bafc51d045a2e98b0c79a526d446de \
				--constructor-args 0x000000000000000000000000f4fbc617a5733eaaf9af08e1ab816b103388d8b600000000000000000000000021c46173591f39afc1d2b634b74c98f0576a272b00000000000000000000000000000000000000000000000000000000000186a0 \
				--retries 10 --delay 10 --watch
#---- [Verify] -----------------------------------------------------------------------------------
# verify.guardedlaunch :; verify :; forge verify-contract \
#         --constructor-args $(cast abi-encode "constructor(address,address,address,address,address,address,address,address,address)" "0xea0f0B7497D043c553238E77eDa66C2965a67B43" "0xE414D49268837291fde21c33AD7e30233b7041C2" "0x4c2c9a36eC98eD9a1FfFD9122C1B366A73F20FAd" "0x18B6F81b92a9474d584d4F59A25E993337Aa49F9" "0xdE25F61A8F3BDf006A21b9284c6849c2818aeDb9" "0xD509A9480559337e924C764071009D60aaCA623d" "0x7734720e7Cea67b29f53800C4aD5C40e61aBb645" "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f" "0x71cEB276788c40D59E244087a1FBB185373aAB1A") \
#         --chain 5 \
#         0x895fAce9c838127abD2150474880A7fb175a621E \
#         src/GuardedLaunch/Glow.GuardedLaunch.sol:GlowGuardedLaunch \
#         $${ETHERSCAN_API_KEY} --watch

# cast abi-encode "constructor(address,address,uint256)" "0xf4fbC617A5733EAAF9af08E1Ab816B103388d8B6" "0x21C46173591f39AfC1d2B634b74c98F0576A272B" "100000"
verify.guardedlaunch :;  forge verify-contract \
        --constructor-args 0x000000000000000000000000ea0f0b7497d043c553238e77eda66c2965a67b43000000000000000000000000e414d49268837291fde21c33ad7e30233b7041c20000000000000000000000004c2c9a36ec98ed9a1fffd9122c1b366a73f20fad00000000000000000000000018b6f81b92a9474d584d4f59a25e993337aa49f9000000000000000000000000de25f61a8f3bdf006a21b9284c6849c2818aedb9000000000000000000000000d509a9480559337e924c764071009d60aaca623d0000000000000000000000007734720e7cea67b29f53800c4ad5c40e61abb6450000000000000000000000005c69bee701ef814a2b6a3edd4b1652cb9cc5aa6f00000000000000000000000071ceb276788c40d59e244087a1fbb185373aab1a \
        --chain 5 \
        0x895fAce9c838127abD2150474880A7fb175a621E \
        src/GuardedLaunch/Glow.GuardedLaunch.sol:GlowGuardedLaunch \
        $${ETHERSCAN_API_KEY} --watch

verify.test  :; forge verify-contract 0x895fAce9c838127abD2150474880A7fb175a621E GlowGuardedLaunch --watch --chain-id 5 

# cast abi-encode "constructor(address,address,address,address,address,address,address)" "0x6Fa8C7a89b22bf3212392b778905B12f3dBAF5C4" "0x8d01a258bC1ADB728322499E5D84173EA971d665" "0xf4fbC617A5733EAAF9af08E1Ab816B103388d8B6" "0xe010ec500720bE9EF3F82129E7eD2Ee1FB7955F2" "0xA3A32d3c9a5A593bc35D69BACbe2dF5Ea2C3cF5C" "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D" "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f"
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

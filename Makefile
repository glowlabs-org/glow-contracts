
# --- [ Solc ] -----------------------------------------------------------------------------------
install-solc :; pip install solc-select;
install-solc-0.8.21 :; solc-select install 0.8.21;
use-solc-0.8.21 :; solc-select use 0.8.21;


# --- [Gen HTML] requires linux or wsl
gen-lcov :; forge coverage --report lcov;

gen-html :;  make gen-lcov && genhtml -o report --branch-coverage lcov.info;


# --- [ Test ] -----------------------------------------------------------------------------------
run-coverage :; forge coverage;

# --- [ Solc ] -----------------------------------------------------------------------------------
install-solc :; pip install solc-select;
install-solc-0.8.21 :; solc-select install 0.8.21;
use-solc-0.8.21 :; solc-select use 0.8.21;

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract MockGuardERC20 is ERC20Permit {
    uint8 immutable d;

    error ErrIsContract();

    /**
     * @notice the list of contracts that can receive USDG
     * @dev contracts must be added to this list before they can receive or send USDG
     *             - EOA's can always receive and send USDG
     */
    mapping(address => bool) public allowlistedContracts;

    constructor(string memory name, string memory symbl, uint8 _decimals) ERC20(name, symbl) ERC20Permit(symbl) {
        d = _decimals;
    }

    function decimals() public view virtual override returns (uint8) {
        return d;
    }

    function setAllowlistStatus(address t, bool s) external {
        allowlistedContracts[t] = s;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    /**
     * @dev override transfers to make sure that only EOA's and allowlisted contracts can send or receive USDG
     * @param from the address to send USDG from
     * @param to the address to send USDG to
     * @param value the amount of USDG to send
     */
    function _update(address from, address to, uint256 value) internal override(ERC20) {
        _revertIfNotAllowlistedContract(from);
        _revertIfNotAllowlistedContract(to);
        super._update(from, to, value);
    }
    /**
     * @dev reverts if the address is a contract and not allowlisted
     */

    function _revertIfNotAllowlistedContract(address _address) internal view {
        if (_isContract(_address)) {
            if (!allowlistedContracts[_address]) {
                revert ErrIsContract();
            }
        }
    }

    /**
     * @dev returns true if the address is a contract
     * @param _address the address to check
     * @return isContract - true if the address is a contract
     */
    function _isContract(address _address) internal view returns (bool isContract) {
        assembly {
            isContract := gt(extcodesize(_address), 0)
        }
    }
}

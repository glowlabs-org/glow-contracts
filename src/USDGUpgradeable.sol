// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract USDGUpgradeable is Initializable, ERC20Upgradeable, ERC20PermitUpgradeable, UUPSUpgradeable {
    error ErrCallerNotGovernance();
    error ErrMustMintPositiveAmount();

    ERC20PermitUpgradeable public USDC;
    address public governance;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _usdc, address _governance) public initializer {
        __ERC20_init("USDG", "USDG");
        __ERC20Permit_init("USDG");
        USDC = ERC20PermitUpgradeable(_usdc);
        governance = _governance;
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address newImplementation) internal override {
        if (msg.sender != governance) {
            revert ErrCallerNotGovernance();
        }
    }

    function mint(address to, uint256 amount) public {
        if (amount == 0) revert ErrMustMintPositiveAmount();
        uint256 balBefore = USDC.balanceOf(address(this));
        SafeERC20.safeTransferFrom(USDC, msg.sender, address(this), amount);
        uint256 balAfter = USDC.balanceOf(address(this));
        uint256 amountToMint = balAfter - balBefore;
        if (amountToMint == 0) revert ErrMustMintPositiveAmount();
        _mint(to, balAfter - balBefore);
    }

    function burn(uint256 amount, address to) public {
        uint256 balBefore = USDC.balanceOf(address(this));
        _burn(msg.sender, amount);
        uint256 balAfter = USDC.balanceOf(address(this));
        SafeERC20.safeTransfer(USDC, to, balBefore - balAfter);
    }

    /**
     * @notice the decimals of USDG
     * @dev matches the decimals of USDC
     * @return decimals - the decimals of USDG
     */
    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}
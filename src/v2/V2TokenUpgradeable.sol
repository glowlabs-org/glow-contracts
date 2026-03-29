// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract V2TokenUpgradeable is
    Initializable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    Ownable2StepUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    address public immutable underlyingToken;
    uint8 immutable _DECIMALS;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    constructor(address _underlyingToken) {
        _disableInitializers();
        underlyingToken = _underlyingToken;
        _DECIMALS = IERC20Metadata(_underlyingToken).decimals();
    }

    function initialize(address _owner, string calldata _name, string calldata _symbol) external initializer {
        __ERC20_init(_name, _symbol);
        __ERC20Permit_init(_name);
        __Ownable2Step_init();
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();
    }

    function mint(address to, uint256 amount) external {
        IERC20(underlyingToken).safeTransferFrom(msg.sender, BURN_ADDRESS, amount);
        _mint(to, amount);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function decimals() public view override returns (uint8) {
        return _DECIMALS;
    }
}

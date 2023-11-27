// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UniswapV2Library} from "@/libraries/UniswapV2Library.sol";
import {IVetoCouncil} from "@/interfaces/IVetoCouncil.sol";
/**
 * @title USDG
 * @notice A contract for swapping USDC for USDG
 *         - the contract takes in USDC and mints USDG
 *         - the contract can only be used EOA's and by allowlisted contracts
 *         - Allow listed contracts include Core Glow Contracts and a GCC/USDG Pair
 *         - USDG is part of the Glow Protocol's Guarded Launch program.
 *         - After the Glow Protocol's Guarded Launch program, USDG will be replaced with USDC
 */

contract USDG is ERC20Permit, Ownable {
    error ErrIsContract();
    error ErrPermanentlyFrozen();
    error ErrNotVetoCouncilMember();

    /* -------------------------------------------------------------------------- */
    /*                                  immutables                                */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice the USDC token
     */
    ERC20Permit public immutable USDC;

    /**
     * @notice the address to receive USDC
     */
    address public immutable USDC_RECEIVER;

    /**
     * @notice the uniswap v2 factory
     */
    address public immutable UNISWAP_V2_FACTORY;

    /* -------------------------------------------------------------------------- */
    /*                                 state vars                                */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice the veto council contract
     */
    IVetoCouncil public vetoCouncilContract;

    /**
     * @notice if true, transfers are permanently frozen
     * @dev - only veto council agents can set this to true
     */
    bool public permanentlyFreezeTransfers;

    /* -------------------------------------------------------------------------- */
    /*                                   mappings                                  */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice the list of contracts that can receive USDG
     * @dev contracts must be added to this list before they can receive or send USDG
     *             - EOA's can always receive and send USDG
     */
    mapping(address => bool) public allowlistedContracts;

    /* -------------------------------------------------------------------------- */
    /*                                 constructor                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @param _usdc the USDC token
     * @param _usdcReceiver the address to receive USDC from the `swap` function
     * @param _owner the owner of the contract
     * @param _univ2Factory the uniswap v2 factory
     */
    constructor(address _usdc, address _usdcReceiver, address _owner, address _univ2Factory)
        Ownable(_owner)
        ERC20("USDC", "USDC")
        ERC20Permit("USDC")
    {
        USDC = ERC20Permit(_usdc);
        USDC_RECEIVER = _usdcReceiver;
        UNISWAP_V2_FACTORY = _univ2Factory;
    }

    /* -------------------------------------------------------------------------- */
    /*                                     mint                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Mints USDG {to}
     * @param to address to mint USDG
     * @param amount amount of USDG to mint
     * @dev only allowlisted contracts and EOA's can mint USDG
     * @dev USDG is minted 1:1 with USDC
     */
    function swap(address to, uint256 amount) public {
        USDC.transferFrom(msg.sender, USDC_RECEIVER, amount);
        _mint(to, amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                                  allowlist                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Adds contracts to the allowlist
     * @param _glow the glow token
     * @param _gcc the gcc token
     * @param _holdingContract the holding contract
     * @dev only the owner can add contracts to the allowlist
     * @dev contracts must be added to the allowlist before they can receive or send USDG
     *             - EOA's can always receive and send USDG
     * @dev this is a one time setter, after the first call, the owner is renounced
     */
    function setAllowlistedContracts(
        address _glow,
        address _gcc,
        address _holdingContract,
        address _vetoCouncilContract
    ) external onlyOwner {
        allowlistedContracts[_glow] = true;
        allowlistedContracts[_gcc] = true;
        allowlistedContracts[_holdingContract] = true;
        //Allowlist the glow/usdg and the gcc/usdg pair
        address glowUSDGPair = getPair(UNISWAP_V2_FACTORY, address(this), _glow);
        allowlistedContracts[glowUSDGPair] = true;
        address gccUSDGPair = getPair(UNISWAP_V2_FACTORY, address(this), _gcc);
        allowlistedContracts[gccUSDGPair] = true;
        vetoCouncilContract = IVetoCouncil(_vetoCouncilContract);
        renounceOwnership();
    }

    /* -------------------------------------------------------------------------- */
    /*                                  veto council                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Freezes transfers permanently
     * @dev only veto council members can call this function
     * @dev after this function is called, all transfers are permanently frozen
     */
    function freezeContract() external {
        if (!vetoCouncilContract.isCouncilMember(msg.sender)) {
            revert ErrNotVetoCouncilMember();
        }
        permanentlyFreezeTransfers = true;
    }

    /* -------------------------------------------------------------------------- */
    /*                                  overrides                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice the decimals of USDG
     * @dev matches the decimals of USDC
     * @return decimals - the decimals of USDG
     */
    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    /**
     * @dev override transfers to make sure that only EOA's and allowlisted contracts can send or receive USDG
     * @param from the address to send USDG from
     * @param to the address to send USDG to
     * @param value the amount of USDG to send
     */
    function _update(address from, address to, uint256 value) internal override(ERC20) {
        if (permanentlyFreezeTransfers) {
            revert ErrPermanentlyFrozen();
        }
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

    /**
     * @notice Returns the univ2 pair for a given factory and token
     * @param factory the univ2 factory
     * @param _tokenA the first token
     * @param _tokenB the second token
     * @return pair - the univ2 pair
     */
    function getPair(address factory, address _tokenA, address _tokenB) internal view virtual returns (address) {
        return UniswapV2Library.pairFor(factory, _tokenA, _tokenB);
    }
}

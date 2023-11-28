// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IGlow} from "@/interfaces/IGlow.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {UniswapV2Library} from "@/libraries/UniswapV2Library.sol";
import {GCC} from "@/GCC.sol";
import {MinerPoolAndGCA} from "@/MinerPoolAndGCA/MinerPoolAndGCA.sol";
import {Glow} from "@/Glow.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IVetoCouncil} from "@/interfaces/IVetoCouncil.sol";
/**
 * @dev helper for managing tail and head in a mapping
 * @param tail the tail of the mapping
 * @param head the head of the mapping
 * @dev the head is the last index with data. If we need to push, we push at head + 1
 * @dev there are edge cases where head == tail and there is data,
 *         -   and conversely, head == tail and there is no data
 *         - These special cases are handled in the code
 */

struct Pointers {
    uint128 tail;
    uint128 head;
}

/**
 * @title Glow
 * @author DavidVorick
 * @author 0xSimon(twitter) - OxSimbo(github)
 * @notice The Glow token is the backbone of the protocol
 *         - Solar farms are rewarded with glow tokens as they produce solar
 *         - GCA's (Glow Certification Agents) and Veto Council Members are rewarded in GLOW
 *             - for their contributions
 *         - The Grants Treasury is rewarded in GLOW for their contributions
 *         - Holders can anchor (stake) glow to earn voting power in governance
 *             - anchoring lasts 5 years from the point of unstaking
 */
contract GlowGuardedLaunch is Glow, Ownable {
    error ErrIsContract();
    error ErrNotVetoCouncilMember();
    error ErrPermanentlyFrozen();

    /* -------------------------------------------------------------------------- */
    /*                                  immutables                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice The address of the USDG contract
     */
    address public immutable USDG;

    /* -------------------------------------------------------------------------- */
    /*                                 state vars                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice true if transfers are permanently frozen
     */
    bool public permanentlyFreezeTransfers;

    /**
     * @notice The address of the GlowUnlocker contract
     * @dev this contract unlocks 90 million pre-minted glow tokens over 6 years
     */
    address public glowUnlocker;

    /**
     * @notice address -> isAllowListedContract
     */
    mapping(address => bool) public allowlistedContracts;

    /* -------------------------------------------------------------------------- */
    /*                                 constructor                                */
    /* -------------------------------------------------------------------------- */

    /// @notice Sets the immutable variables (GENESIS_TIMESTAMP, EARLY_LIQUIDITY_ADDRESS)
    /// @notice sends 12 million GLW to the Early Liquidity Contract and 90 million GLW to the unlocker contract
    /// @param _earlyLiquidityAddress The address of the Early Liquidity Contract
    /// @param _vestingContract The address of the vesting contract
    /// @param _owner The address of the owner
    /// @param _usdg The address of the USDG contract
    /// @param _uniswapV2Factory The address of the Uniswap V2 Factory
    constructor(
        address _earlyLiquidityAddress,
        address _vestingContract,
        address _owner,
        address _usdg,
        address _uniswapV2Factory
    ) payable Glow(_earlyLiquidityAddress, _vestingContract) Ownable(_owner) {
        allowlistedContracts[address(this)] = true;
        allowlistedContracts[_earlyLiquidityAddress] = true;
        allowlistedContracts[_vestingContract] = true;
        allowlistedContracts[getPair(_uniswapV2Factory, address(this), _usdg)] = true;
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
        if (!IVetoCouncil(vetoCouncilAddress).isCouncilMember(msg.sender)) {
            revert ErrNotVetoCouncilMember();
        }
        permanentlyFreezeTransfers = true;
    }

    /* -------------------------------------------------------------------------- */
    /*                            one time setters override                       */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Sets the addresses of the GCA and Miner Pool, Veto Council, and Grants Treasury
     * @dev this function can only be called once
     */
    function setContractAddresses(
        address _gcaAndMinerPoolAddress,
        address _vetoCouncilAddress,
        address _grantsTreasuryAddress
    ) external override onlyOwner {
        // Zero address checks
        //Only need one check since all three addresses are set at the same time atomically
        if (!_isZeroAddress(gcaAndMinerPoolAddress)) _revert(IGlow.AddressAlreadySet.selector);
        if (_isZeroAddress(_gcaAndMinerPoolAddress)) _revert(IGlow.ZeroAddressNotAllowed.selector);
        if (_isZeroAddress(_vetoCouncilAddress)) _revert(IGlow.ZeroAddressNotAllowed.selector);
        if (_isZeroAddress(_grantsTreasuryAddress)) _revert(IGlow.ZeroAddressNotAllowed.selector);

        // Duplicate checks
        if (_gcaAndMinerPoolAddress == _vetoCouncilAddress) _revert(IGlow.DuplicateAddressNotAllowed.selector);
        if (_gcaAndMinerPoolAddress == _grantsTreasuryAddress) _revert(IGlow.DuplicateAddressNotAllowed.selector);
        if (_vetoCouncilAddress == _grantsTreasuryAddress) _revert(IGlow.DuplicateAddressNotAllowed.selector);

        //Set the addresses
        gcaAndMinerPoolAddress = _gcaAndMinerPoolAddress;
        vetoCouncilAddress = _vetoCouncilAddress;
        grantsTreasuryAddress = _grantsTreasuryAddress;
        allowlistedContracts[_gcaAndMinerPoolAddress] = true;
        allowlistedContracts[_vetoCouncilAddress] = true;
        allowlistedContracts[_grantsTreasuryAddress] = true;
        // address gccContract = address(MinerPoolAndGCA(gcaAndMinerPoolAddress).gccContract());
        // require(gccContract != address(0), "Glow: gccContract is zero");
        // address carbonCreditAuction = address(GCC(gccContract).CARBON_CREDIT_AUCTION());
        // require(carbonCreditAuction != address(0), "Glow: carbonCreditAuction is zero");
        // allowlistedContracts[carbonCreditAuction] = true;
    }

    function setGlowUnlocker(address _glowUnlocker) external onlyOwner {
        if (!_isZeroAddress(glowUnlocker)) _revert(IGlow.AddressAlreadySet.selector);
        if (_isZeroAddress(_glowUnlocker)) _revert(IGlow.ZeroAddressNotAllowed.selector);
        glowUnlocker = _glowUnlocker;
        allowlistedContracts[_glowUnlocker] = true;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 erc20 override                              */
    /* -------------------------------------------------------------------------- */

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
        if (!_isZeroAddress(from)) {
            _revertIfNotAllowlistedContract(from);
            _revertIfNotAllowlistedContract(to);
        }
        super._update(from, to, value);
    }

    /* -------------------------------------------------------------------------- */
    /*                                  utils                              */
    /* -------------------------------------------------------------------------- */
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
     * @param _tokenA the first tokenx
     * @param _tokenB the second token
     * @return pair - the univ2 pair
     */
    function getPair(address factory, address _tokenA, address _tokenB) internal view virtual returns (address pair) {
        pair = UniswapV2Library.pairFor(factory, _tokenA, _tokenB);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {GCC} from "@/GCC.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IVetoCouncil} from "@/interfaces/IVetoCouncil.sol";
import {UniswapV2Library} from "@/libraries/UniswapV2Library.sol";

/**
 * @title GCCGuardedLaunch
 * @notice This contract is used to guard the launch of the GCC token
 *               - GLOW Protocol's guraded launch is meant to protect the protocol from
 *                 malicious actors and to give the community time to audit the code
 *               - During the guarded launch, transfers are restricted to EOA's and allowlisted contracts
 *               - The veto council also has the ability to permanently freeze transfers in case of an emergency
 *                   - Post guarded-launch, Guarded Launch tokens will be airdropped 1:1 to GCC holders
 */
contract GCCGuardedLaunch is GCC {
    error ErrIsContract();
    error ErrNotVetoCouncilMember();
    error ErrPermanentlyFrozen();

    /* -------------------------------------------------------------------------- */
    /*                                  immutables                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice The address of the USDG contract
     */
    address public immutable VETO_COUNCIL_ADDRESS;

    /* -------------------------------------------------------------------------- */
    /*                                 state vars                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice true if transfers are permanently frozen
     */
    bool public permanentlyFreezeTransfers;

    /**
     * @notice address -> isAllowListedContract
     */
    mapping(address => bool) public allowlistedContracts;

    /* -------------------------------------------------------------------------- */
    /*                                 constructor                                */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice GCC constructor
     * @param _gcaAndMinerPoolContract The address of the GCAAndMinerPool contract
     * @param _governance The address of the governance contract
     * @param _glowToken The address of the GLOW token
     * @param _usdg The address of the USDG token
     * @param _vetoCouncilAddress The address of the veto council contract
     * @param _uniswapRouter The address of the Uniswap V2 router
     * @param _uniswapFactory The address of the Uniswap V2 factory
     */
    constructor(
        address _gcaAndMinerPoolContract,
        address _governance,
        address _glowToken,
        address _usdg,
        address _vetoCouncilAddress,
        address _uniswapRouter,
        address _uniswapFactory
    ) payable GCC(_gcaAndMinerPoolContract, _governance, _glowToken, _usdg, _uniswapRouter) {
        VETO_COUNCIL_ADDRESS = _vetoCouncilAddress;
        allowlistedContracts[address(this)] = true;
        allowlistedContracts[_governance] = true;
        allowlistedContracts[getPair(_uniswapFactory, _usdg)] = true;
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
        if (!IVetoCouncil(VETO_COUNCIL_ADDRESS).isCouncilMember(msg.sender)) {
            revert ErrNotVetoCouncilMember();
        }
        permanentlyFreezeTransfers = true;
    }

    /* -------------------------------------------------------------------------- */
    /*                               one time setters                             */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice Allowlist contracts that are created after the contract is deployed
     * @dev this includes [CarbonCreditAuction, ImpactCatalyst]
     */
    function allowlistPostConstructionContracts() external {
        allowlistedContracts[address(CARBON_CREDIT_AUCTION)] = true;
        allowlistedContracts[address(IMPACT_CATALYST)] = true;
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
     * @notice More efficient address(0) check
     */
    function _isZeroAddress(address _address) internal pure returns (bool isZero) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            isZero := iszero(_address)
        }
    }
}

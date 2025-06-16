// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {USDG} from "@/USDG.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract USDGGuardedLaunchV2 is USDG {
    error CannotSendZeroAmount();
    error ClaimNotAvailableYet();
    error NoUSDCToClaim();
    error ContractNotFrozen();
    /* -------------------------------------------------------------------------- */
    /*                                 constructor                                */
    /* -------------------------------------------------------------------------- */

    uint256 internal constant QUEUE_TIME = 14 days;

    struct USDCWithdrawal {
        uint192 amount;
        uint64 expirationTimestamp;
    }

    event USDCWithdrawalQueued(address indexed user, uint256 amount, uint64 expirationTimestamp);
    event USDCWithdrawalClaimed(address indexed user, uint256 amount);

    mapping(address => USDCWithdrawal) internal _usdcWithdrawalQueue;

    /**
     * @param _usdc the USDC token
     * @param _usdcReceiver the address to receive USDC from the `swap` function
     * @param _owner the owner of the contract
     * @param _univ2Factory the uniswap v2 factory
     * @param _glow the glow token
     * @param _gcc the gcc token
     * @param _holdingContract the holding contract
     * @param _vetoCouncilContract the veto council contract
     * @param _impactCatalyst the impact catalyst contract
     * @param _allowlistedMultisigContracts The addresses of the multisig contracts to allowlist
     * @param _migrationContractAndAmount The address and amount in bytes to send to the migration contract
     *     - To prevent stack too deep error
     */
    constructor(
        address _usdc,
        address _usdcReceiver,
        address _owner,
        address _univ2Factory,
        address _glow,
        address _gcc,
        address _holdingContract,
        address _vetoCouncilContract,
        address _impactCatalyst,
        address[] memory _allowlistedMultisigContracts,
        bytes memory _migrationContractAndAmount //To prevent stack too deep error
    )
        payable
        USDG(
            _usdc,
            _usdcReceiver,
            _owner,
            _univ2Factory,
            _glow,
            _gcc,
            _holdingContract,
            _vetoCouncilContract,
            _impactCatalyst
        )
    {
        for (uint256 i; i < _allowlistedMultisigContracts.length;) {
            allowlistedContracts[_allowlistedMultisigContracts[i]] = true;
            unchecked {
                ++i;
            }
        }

        _decodeMigrationContractAndSendAmount(_migrationContractAndAmount);
    }

    /// @notice Allows the `msg.sender` to deposit USDG into the withdrawal queue
    function depositUSDCToWithdrawalQueue(uint256 _amount) external {
        if (_amount == 0) {
            revert CannotSendZeroAmount();
        }
        _burn(msg.sender, _amount);
        uint64 expirationTimestamp = uint64(block.timestamp + QUEUE_TIME);
        USDCWithdrawal memory withdrawal = _usdcWithdrawalQueue[msg.sender];
        uint192 newTotalAmount = SafeCast.toUint192(uint256(withdrawal.amount) + _amount);
        _usdcWithdrawalQueue[msg.sender] = USDCWithdrawal(newTotalAmount, expirationTimestamp);
        emit USDCWithdrawalQueued(msg.sender, _amount, expirationTimestamp);
    }

    /// @notice Allows the `msg.sender` to claim USDG from the withdrawal queue
    function claimUSDCFromWithdrawalQueue() external {
        _revertIfFrozen();
        USDCWithdrawal memory withdrawal = _usdcWithdrawalQueue[msg.sender];
        if (withdrawal.amount == 0) {
            revert NoUSDCToClaim();
        }
        if (block.timestamp < withdrawal.expirationTimestamp) {
            revert ClaimNotAvailableYet();
        }
        delete _usdcWithdrawalQueue[msg.sender];
        SafeERC20.safeTransfer(IERC20(address(USDC)), msg.sender, withdrawal.amount);
        emit USDCWithdrawalClaimed(msg.sender, withdrawal.amount);
    }

    /// @notice Returns the USDG withdrawal queue for a user
    /// @param _user - The user to get the withdrawal queue for
    function usdcWithdrawalQueue(address _user) external view returns (USDCWithdrawal memory) {
        return _usdcWithdrawalQueue[_user];
    }

    /// @notice Sends all remaining USDC to the Multisig contract in case of a freeze
    function sendTokensToUSDCReceiverInCaseOfFreeze() public {
        if (!permanentlyFreezeTransfers) {
            revert ContractNotFrozen();
        }

        SafeERC20.safeTransfer(IERC20(address(USDC)), USDC_RECEIVER, USDC.balanceOf(address(this)));
    }

    /// @dev Decodes the migration contract and amount and sends the amount to the migration contract
    function _decodeMigrationContractAndSendAmount(bytes memory _migrationContractAndAmount) internal {
        (address _migrationContract, uint256 _amountToSendToMigrationContract) =
            abi.decode(_migrationContractAndAmount, (address, uint256));
        allowlistedContracts[_migrationContract] = true;
        _mint(_migrationContract, _amountToSendToMigrationContract);
    }
}

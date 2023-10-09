// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IVetoCouncil} from "@/interfaces/IVetoCouncil.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @dev Struct representing a holding of tokens in the HoldingContract.
 * @param amount The amount of tokens being held.
 * @param expirationTimestamp The timestamp at which the holding expires and can be withdrawn.
 */
struct Holding {
    uint192 amount;
    uint64 expirationTimestamp;
}

/**
 * @dev a helper type to organize claim holdings arguments
 * @param user the address of the user
 * @param token the address of the grc token to withdraw
 */
struct ClaimHoldingArgs {
    address user;
    address token;
}

interface IHoldingContract {
    function addHoldings(address user, address[] memory tokens, uint192[] memory amounts) external;
    function holdings(address user, address token) external view returns (Holding memory);
    function claimHoldings(ClaimHoldingArgs[] memory args) external;
    function setMinerPool(address _minerPool) external;
}

contract HoldingContract {
    error OnlyMinerPoolCanAddHoldings();
    error WithdrawalNotReady();
    error CallerMustBeVetoCouncilMember();
    error CanOnlyDelayEveryEightyDays();
    error NetworkIsFrozen();
    error AlreadyWithdrawnFromHolding();
    error MinerPoolAlreadySet();

    /**
     * @notice the address of the miner pool
     * @dev this is the address that can add holdings to the contract
     */
    address public minerPool;

    /**
     * @notice the address of the veto council
     * @dev veto council members can delay the network
     */
    IVetoCouncil public immutable VETO_COUNCIL;

    /**
     * @notice the default delay for withdrawals
     * @dev the default delay is 7 days
     * Whenever a user withdraws from the miner pool,
     *       their funds are locked for 7 days
     */
    uint256 private constant DEFAULT_DELAY = uint256(7 days);

    /**
     * @notice the delay for withdrawals after the network is delayed
     * @dev the delay is 90 days
     * all withdrawals will be delayed for 90 days
     */
    uint256 private constant VETO_HOLDING_DELAY = uint256(90 days);

    /**
     * @dev the 90 day delay can only be activated every 80 days
     */
    uint256 private constant EIGHTY_DAYS = uint256(80 days);

    uint256 public minimumWithdrawTimestamp;

    mapping(address => mapping(address => Holding)) private _holdings;

    /**
     * @param _vetoCouncil the address of the veto council
     */
    constructor(address _vetoCouncil) {
        VETO_COUNCIL = IVetoCouncil(_vetoCouncil);
    }

    /**
     * @notice allows veto council members to delay the network by 90 days
     * All withdrawals will be delayed until t + 90 days
     *         - where t is the block.timestamp
     */
    function delayNetwork() external {
        if (!VETO_COUNCIL.isCouncilMember(msg.sender)) {
            _revert(CallerMustBeVetoCouncilMember.selector);
        }
        uint256 _minimumWithdrawTimestamp = minimumWithdrawTimestamp;
        if (_minimumWithdrawTimestamp == 0) {
            minimumWithdrawTimestamp = block.timestamp + VETO_HOLDING_DELAY;
            return;
        }

        uint256 timeSinceLastDelay = block.timestamp - _minimumWithdrawTimestamp;
        if (timeSinceLastDelay < EIGHTY_DAYS) {
            _revert(CanOnlyDelayEveryEightyDays.selector);
        }
        minimumWithdrawTimestamp = block.timestamp + VETO_HOLDING_DELAY;
    }

    /**
     * @notice allows the miner pool contract to add holdings
     * @param user the address of the user
     * @param tokens the addresses of the grc tokens to withdraw
     * @param amounts the amounts of tokens to add to the holding
     */
    function addHoldings(address user, address[] memory tokens, uint192[] memory amounts) external {
        if (msg.sender != minerPool) {
            _revert(OnlyMinerPoolCanAddHoldings.selector);
        }
        for (uint256 i; i < tokens.length;) {
            addHolding(user, tokens[i], amounts[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice entrypoint to claim holdings
     * @param args - an array of {ClaimHoldingArgs}
     * @dev this is a batch method to claim holdings
     *     - this is more gas efficient than calling claimHolding for each holding
     *     - the protocol may use a relayer to bundle claims
     */
    function claimHoldings(ClaimHoldingArgs[] memory args) external {
        //If the network is frozen, don't allow withdrawals
        if (block.timestamp < minimumWithdrawTimestamp) {
            _revert(NetworkIsFrozen.selector);
        }
        //Loop over all the arguments
        for (uint256 i; i < args.length; ++i) {
            ClaimHoldingArgs memory arg = args[i];
            Holding memory holding = _holdings[arg.user][arg.token];
            if (block.timestamp < holding.expirationTimestamp) {
                _revert(WithdrawalNotReady.selector);
            }
            //Delete the holding args.
            //Should set all the data to zero.
            delete _holdings[arg.user][arg.token];
            //Add the amount to the amount to transfer
            SafeERC20.safeTransfer(IERC20(arg.token), arg.user, holding.amount);
        }
    }

    function setMinerPool(address _minerPool) external {
        if (minerPool != address(0)) {
            _revert(MinerPoolAlreadySet.selector);
        }
        minerPool = _minerPool;
    }
    /**
     * @notice returns the Holding struct for a user and token pair
     * @param user the address of the user
     * @param token the address of the grc token to withdraw
     * @return holding - the Holding struct
     */

    function holdings(address user, address token) external view returns (Holding memory) {
        return _holdings[user][token];
    }

    /**
     * @notice an internal method to increment the amount in a holding
     * @param user the address of the user
     * @param token the address of the grc token to withdraw
     * @param amount the amount of tokens to add to the holding
     */
    function addHolding(address user, address token, uint192 amount) internal {
        _holdings[user][token].amount += amount;
        _holdings[user][token].expirationTimestamp = uint64(block.timestamp + DEFAULT_DELAY);
    }

    /**
     * @dev more efficient reverts
     * @param selector the selector of the error
     */
    function _revert(bytes4 selector) internal pure {
        assembly {
            mstore(0, selector)
            revert(0, 4)
        }
    }
}

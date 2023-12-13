// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

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
 * @param token the address of the USDC token to withdraw
 */
struct ClaimHoldingArgs {
    address user;
    address token;
}

interface IHoldingContract {
    function addHolding(address user, address token, uint192 amount) external;
    function holdings(address user, address token) external view returns (Holding memory);
    function claimHoldings(ClaimHoldingArgs[] memory args) external;
    function setMinerPool(address _minerPool) external;
}

/**
 * @title HoldingContract
 * @notice This contract is used to hold tokens for users
 *         - This contract holds all USDC tokens that are part of the protocol
 *         - Once farms withdraw, there is a 1 week delay before they can claim their tokens
 *         - The Miner Pool Contract assigns these holdings as part of the withdraw process
 *         - Veto Agents can delay all withdrawals by 13 weeks
 *         - A holding can be max delayed for 97 days
 */
contract HoldingContract {
    /* -------------------------------------------------------------------------- */
    /*                                   errors                                   */
    /* -------------------------------------------------------------------------- */
    error OnlyMinerPoolCanAddHoldings();
    error WithdrawalNotReady();
    error CallerMustBeVetoCouncilMember();
    error DelayStillOnCooldown();
    error NetworkIsFrozen();
    error AlreadyWithdrawnFromHolding();
    error MinerPoolAlreadySet();

    /* -------------------------------------------------------------------------- */
    /*                                  constants                                 */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice the default delay for withdrawals
     * @dev the default delay is 7 days
     * Whenever a user withdraws from the miner pool,
     *       their funds are locked for 7 days
     */
    uint256 public constant DEFAULT_DELAY = uint256(7 days);

    /**
     * @dev 90 days in seconds
     */
    uint256 public constant NINETY_DAYS = uint256(90 days);

    /**
     * @notice the delay for withdrawals after the network is delayed
     * @dev the delay is 13 weeks
     * all withdrawals will be delayed for 13 weeks
     */
    uint256 public constant VETO_HOLDING_DELAY = uint256(13 weeks);

    /**
     * @dev a cached version of five weeks in seconds
     * @dev used in delayNetwork to ensure that the network can only be delayed every 5 weeks
     * @dev This helps prevent bad veto agents from spamming the delay network function
     *         - by giving governance enough time to kick out the veto agent
     */
    uint256 public constant FIVE_WEEKS = uint256(5 weeks);

    /* -------------------------------------------------------------------------- */
    /*                                 immutables                                 */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice the address of the veto council
     * @dev veto council members can delay the network
     */
    IVetoCouncil public immutable VETO_COUNCIL;

    /* -------------------------------------------------------------------------- */
    /*                                 state vars                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice the address of the miner pool
     * @dev this is the address that can add holdings to the contract
     */
    address public minerPool;

    /**
     * @notice the minimum timestamp for withdrawals
     * @dev any claims below this timestamp will revert
     */
    uint256 public minimumWithdrawTimestamp;

    /* -------------------------------------------------------------------------- */
    /*                                   mappings                                  */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice the holdings for each user
     *     Note: We could have chosen an array of holdings
     *     such that each withdraw truly is a FIFO queue with 1 week delay
     *     However, we chose to store all holdings in a single slot
     *     to avoid cold sstores and sloads
     *     The downside of this approach is that we can't have a FIFO queue
     *     and that any time a withdraw is made from the miner pool contract
     *     the user's holdings are locked for 7 days
     */
    mapping(address => mapping(address => Holding)) private _holdings;

    /* -------------------------------------------------------------------------- */
    /*                                   events                                  */
    /* -------------------------------------------------------------------------- */
    /**
     * @dev emitted when there is a network delay
     * @param vetoAgent the address of the veto agent that delayed the network
     * @param timestamp the timestamp at which the network was delayed
     */
    event NetworkDelay(address vetoAgent, uint256 timestamp);

    /**
     * @dev emitted whenever a holding is added to a user
     * @param user the address of the user
     * @param token the address of the USDC token
     * @param amount the amount of tokens added to the holding
     * @dev we dont emit a {HoldingClaimed} event since there may be a tax
     *     - on the token that will mess up the data.
     *     - we rely on catching transfer events
     */
    event HoldingAdded(address indexed user, address indexed token, uint192 amount);

    /* -------------------------------------------------------------------------- */
    /*                                 constructor                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @param _vetoCouncil the address of the veto council
     */
    constructor(address _vetoCouncil) payable {
        VETO_COUNCIL = IVetoCouncil(_vetoCouncil);
    }

    /* -------------------------------------------------------------------------- */
    /*                                    delay                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice allows veto council members to delay the network by 13 weeks
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
        if (block.timestamp < _minimumWithdrawTimestamp) {
            //The block.timestamp needs to be within 5 weeks of
            //minimumWithdrawTimestamp
            uint256 timeLeftInDelay = _minimumWithdrawTimestamp - block.timestamp;
            if (timeLeftInDelay > FIVE_WEEKS) {
                _revert(DelayStillOnCooldown.selector);
            }
        }

        minimumWithdrawTimestamp = block.timestamp + VETO_HOLDING_DELAY;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   claim                                    */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice entrypoint to claim holdings
     * @param args - an array of {ClaimHoldingArgs}
     * @dev this is a batch method to claim holdings
     *     - this is more gas efficient than calling claimHolding for each holding
     *     - the protocol may use a relayer to bundle claims
     */
    function claimHoldings(ClaimHoldingArgs[] memory args) external {
        //If the network is frozen, don't allow withdrawals
        bool networkIsFrozen = block.timestamp < minimumWithdrawTimestamp;
        //Loop over all the arguments
        uint256 len = args.length;
        for (uint256 i; i < len;) {
            ClaimHoldingArgs memory arg = args[i];
            Holding memory holding = _holdings[arg.user][arg.token];
            checkHoldingAvailable(holding.expirationTimestamp, networkIsFrozen);
            //Delete the holding args.
            //Should set all the data to zero.
            delete _holdings[arg.user][arg.token];
            //Add the amount to the amount to transfer
            SafeERC20.safeTransfer(IERC20(arg.token), arg.user, holding.amount);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice entrypoint to claim a single holding
     * @param user the address of the user
     * @param token the address of the USDC token to withdraw
     * @dev should be used if the user only wants to claim their holding
     */
    function claimHoldingSingleton(address user, address token) external {
        bool networkIsFrozen = block.timestamp < minimumWithdrawTimestamp;
        // If the network is frozen and timestamp since expiration is not more than 90 days, don't allow withdrawals
        Holding memory holding = _holdings[user][token];
        checkHoldingAvailable(holding.expirationTimestamp, networkIsFrozen);
        //Delete the holding args.
        //Should set all the data to zero.
        delete _holdings[user][token];
        //Add the amount to the amount to transfer
        SafeERC20.safeTransfer(IERC20(token), user, holding.amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                                 add holdings                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice an internal method to increment the amount in a holding
     * @param user the address of the user
     * @param token the address of the USDC token to withdraw
     * @param amount the amount of tokens to add to the holding
     */
    function addHolding(address user, address token, uint192 amount) external {
        if (msg.sender != minerPool) {
            _revert(OnlyMinerPoolCanAddHoldings.selector);
        }
        _holdings[user][token].amount += amount;
        _holdings[user][token].expirationTimestamp = uint64(block.timestamp + DEFAULT_DELAY);
        emit HoldingAdded(user, token, amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                               one time setters                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice a one time setter to set the miner pool
     * @dev the miner pool calls this function upon deployment
     * @param _minerPool the address of the miner pool
     */
    function setMinerPool(address _minerPool) external {
        //Make sure the miner pool is not already set
        if (minerPool != address(0)) {
            _revert(MinerPoolAlreadySet.selector);
        }
        minerPool = _minerPool;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 view functions                             */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice returns the Holding struct for a user and token pair
     * @param user the address of the user
     * @param token the address of the USDC token to withdraw
     * @return holding - the Holding struct
     */
    function holdings(address user, address token) external view returns (Holding memory) {
        return _holdings[user][token];
    }

    /**
     * @dev checks if the holding is available to be withdrawn
     * @param holdingExpirationTimestamp the timestamp at which the holding expires
     * @param isNetworkFrozen whether or not the network is currently frozen
     * @dev - if the network is frozen, the holding can be withdrawn only if it's been more than 90 days past the expiration of the holding
     *      - if the network is not frozen, the holding can be withdrawn only if it's past the expiration date of the holding
     */
    function checkHoldingAvailable(uint64 holdingExpirationTimestamp, bool isNetworkFrozen) internal view {
        if (block.timestamp < holdingExpirationTimestamp) {
            _revert(WithdrawalNotReady.selector);
        }
        //Can't underflow because of the check above
        //No claim should be able to be held for more than 97 days
        //If it's been less than than 97 days since the proposal has expired,
        //(expiration timestamp is always claim timestamp + 1 week, so )
        //in order for proposal to be held maximum 97 days,
        //We need to check if the diff is 90 days
        if (block.timestamp - holdingExpirationTimestamp < NINETY_DAYS) {
            if (isNetworkFrozen) {
                _revert(NetworkIsFrozen.selector);
            }
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                                   utils                                    */
    /* -------------------------------------------------------------------------- */
    /**
     * @dev more efficient reverts
     * @param selector the selector of the error
     */
    function _revert(bytes4 selector) internal pure {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(0, selector)
            revert(0, 4)
        }
    }
}

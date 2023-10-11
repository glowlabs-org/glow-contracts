// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IVetoCouncil} from "@/interfaces/IVetoCouncil.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

//TODO: change to weeks
//todo: a holding can be max delayed 97 days.
//so we need to add a nonce to the holding
//todo: can create a delay event, eveyy 60 days (9 weeks)

/**
 * @dev Struct representing a holding of tokens in the HoldingContract.
 * @param amount The amount of tokens being held.
 * @param expirationTimestamp The timestamp at which the holding expires and can be withdrawn.
 */
struct Holding {
    uint192 amount;
    uint64 expirationTimestamp; //TODO: if > 90 days past the expiration,
        // holding available to claim
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
    function addHolding(address user, address token, uint192 amount) external;
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
     * @dev a cached version of 10 days in seconds
     * @dev used in delayNetwork to ensure that the network can only be delayed every 80 days
     */
    uint256 private constant TEN_DAYS = uint256(10 days);

    /**
     * @notice the address of the veto council
     * @dev veto council members can delay the network
     */
    IVetoCouncil public immutable VETO_COUNCIL;

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

    /**
     * @dev emitted when there is a network delay
     * @param vetoAgent the address of the veto agent that delayed the network
     * @param timestamp the timestamp at which the network was delayed
     *         - timestamp + 90 days is the earliest time that withdrawals can be made
     */
    event NetworkDelay(address vetoAgent, uint256 timestamp);

    /**
     * @dev emitted whenever a holding is added to a user
     * @param user the address of the user
     * @param token the address of the grc token
     * @param amount the amount of tokens added to the holding
     * @dev we dont emit a {HoldingClaimed} event since there may be a tax
     *     - on the token that will mess up the data.
     *     - we rely on catching transfer events
     */
    event HoldingAdded(address indexed user, address indexed token, uint192 amount);

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
        if (block.timestamp < _minimumWithdrawTimestamp) {
            //The block.timestamp needs to be within 10 days of
            //minimumWithdrawTimestamp
            uint256 timeLeftInDelay = _minimumWithdrawTimestamp - block.timestamp;
            if (timeLeftInDelay > TEN_DAYS) {
                _revert(CanOnlyDelayEveryEightyDays.selector);
            }
        }

        minimumWithdrawTimestamp = block.timestamp + VETO_HOLDING_DELAY;
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

    function claimHoldingSingleton(address user, address token) external {
        //If the network is frozen, don't allow withdrawals
        if (block.timestamp < minimumWithdrawTimestamp) {
            _revert(NetworkIsFrozen.selector);
        }
        Holding memory holding = _holdings[user][token];
        if (block.timestamp < holding.expirationTimestamp) {
            _revert(WithdrawalNotReady.selector);
        }
        //Delete the holding args.
        //Should set all the data to zero.
        delete _holdings[user][token];
        //Add the amount to the amount to transfer
        SafeERC20.safeTransfer(IERC20(token), user, holding.amount);
    }

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
    function addHolding(address user, address token, uint192 amount) external {
        if (msg.sender != minerPool) {
            _revert(OnlyMinerPoolCanAddHoldings.selector);
        }
        _holdings[user][token].amount += amount;
        _holdings[user][token].expirationTimestamp = uint64(block.timestamp + DEFAULT_DELAY);
        emit HoldingAdded(user, token, amount);
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

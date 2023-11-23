// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IGlow} from "./interfaces/IGlow.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

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
contract Glow is ERC20, ERC20Permit, IGlow {
    /* -------------------------------------------------------------------------- */
    /*                                  constants                                 */
    /* -------------------------------------------------------------------------- */
    /// @notice The cooldown period after unstaking before a user can claim their tokens
    uint256 private constant _STAKE_COOLDOWN_PERIOD = 365 days * 5;

    /// @notice The amount of GLW that is minted per second for the GCA and Miner Pool
    /// @notice 185,000 GLW per week
    /// @dev 175,000 to miners
    /// @dev 10,000 to the GCAs
    uint256 public constant GCA_AND_MINER_POOL_INFLATION_PER_SECOND = 185_000 * 1 ether / uint256(7 days);

    /// @notice The amount of GLW that is minted per second for the Veto Council
    /// @notice 5,000 GLW per week
    uint256 public constant VETO_COUNCIL_INFLATION_PER_SECOND = 5_000 * 1 ether / uint256(7 days);

    /// @notice The amount of GLW that is minted per second for the Grants Treasury
    /// @notice 40,000 GLW per week
    uint256 public constant GRANTS_TREASURY_INFLATION_PER_SECOND = 40_000 * 1 ether / uint256(7 days);

    /// @notice the maximum number of times a user can unstake without clearing their unstaked positions
    /// @notice before they are forced to wait 1 day before staking again
    uint256 public constant MAX_UNSTAKES_BEFORE_EMERGENCY_COOLDOWN = 100;

    /// @notice the cooldown period once users stake over 100 times
    uint256 public constant EMERGENCY_COOLDOWN_PERIOD = 1 days;

    /* -------------------------------------------------------------------------- */
    /*                                  immutables                                */
    /* -------------------------------------------------------------------------- */
    /// @notice The timestamp of the genesis block
    // solhint-disable-next-line var-name-mixedcase
    uint256 public immutable GENESIS_TIMESTAMP;

    /// @notice The address of the Early Liquidity Contract
    //  solhint-disable-next-line var-name-mixedcase
    address public immutable EARLY_LIQUIDITY_ADDRESS;

    /* -------------------------------------------------------------------------- */
    /*                                 state vars                                */
    /* -------------------------------------------------------------------------- */
    /// @notice The last time the GCA and Miner Pool claimed GLW
    uint256 public gcaAndMinerPoolLastClaimedTimestamp;

    /// @notice The last time the Veto Council claimed GLW
    uint256 public vetoCouncilLastClaimedTimestamp;

    /// @notice The last time the Grants Treasury claimed GLW
    uint256 public grantsTreasuryLastClaimedTimestamp;

    /// @notice the GCA And Miner Pool address
    address public gcaAndMinerPoolAddress;

    /// @notice the Veto Council address
    address public vetoCouncilAddress;

    /// @notice the Grants Treasury address
    address public grantsTreasuryAddress;

    /* -------------------------------------------------------------------------- */
    /*                                   mappings                                  */
    /* -------------------------------------------------------------------------- */
    /// @notice stores the total amount of GLOW staked by a user
    mapping(address => uint256) public numStaked;

    /// @notice stores the unstaked positions of a user
    mapping(address => mapping(uint256 => UnstakedPosition)) private _unstakedPositions;

    /// @notice stores the head of the unstaked positions of a user
    /// @dev the head is the last index with data. If we need to push, we push at head + 1
    /// @dev if the head is zero, there may or may not be data.
    mapping(address => Pointers) private _unstakedPositionPointers;

    /// @notice stores the last time a user staked in case the user has over 100 staked positions
    mapping(address => uint256) public emergencyLastUnstakeTimestamp;

    /* -------------------------------------------------------------------------- */
    /*                                 constructor                                */
    /* -------------------------------------------------------------------------- */

    /// @notice Sets the immutable variables (GENESIS_TIMESTAMP, EARLY_LIQUIDITY_ADDRESS)
    /// @notice sends 12 million GLW to the Early Liquidity Contract and 90 million GLW to the unlocker contract
    /// @param _earlyLiquidityAddress The address of the Early Liquidity Contract
    /// @param _vestingContract The address of the vesting contract
    constructor(address _earlyLiquidityAddress, address _vestingContract)
        payable
        ERC20("Glow", "GLOW")
        ERC20Permit("Glow")
    {
        GENESIS_TIMESTAMP = block.timestamp;
        EARLY_LIQUIDITY_ADDRESS = _earlyLiquidityAddress;
        _mint(EARLY_LIQUIDITY_ADDRESS, 12_000_000 ether);
        _mint(_vestingContract, 96_000_000 ether);
    }

    /* -------------------------------------------------------------------------- */
    /*                                  staking                                   */
    /* -------------------------------------------------------------------------- */
    /**
     * @inheritdoc IGlow
     * @dev if the user has unstaked positions that have already expired,
     *         -   the function will auto claim those tokens for the user
     */
    function stake(uint256 stakeAmount) external {
        //Cannot stake zero tokens
        if (stakeAmount == 0) _revert(IGlow.CannotStakeZeroTokens.selector);

        //Find head tail in the mapping
        Pointers memory pointers = _unstakedPositionPointers[msg.sender];
        uint256 head = pointers.head;

        //Init the unstakedTotal
        uint256 amountInUserUnstakePool;

        //Init the new head
        uint256 newHead = head;

        uint256 tail = pointers.tail;

        //We need to loop through starting from the head (newest positions)
        for (uint256 i = head; i >= tail; --i) {
            //load the posiiton from storage into memory
            UnstakedPosition memory position = _unstakedPositions[msg.sender][i];

            //increase the amount in the user unstake pool
            //by the amount that is in the position we are on
            amountInUserUnstakePool += position.amount;

            //If it's exactly equal, that means the data will be fully cleared
            //And the head moves to i-1 or 0(if fully empty now)
            if (amountInUserUnstakePool == stakeAmount) {
                //If i is 0 and the amount is exactly zero,
                //that means we can restart the unstaked positions from scratch
                if (i == 0) {
                    newHead = 0;
                    delete _unstakedPositions[msg.sender][newHead];
                }
                //If i is not zero, we can just move the head to i-1
                else {
                    newHead = i - 1;
                }
                break;
            }

            //If the amount in the user unstake pool is greater than the stake amount
            //That means we overshot and we need to pull back the amount we overshot by
            if (amountInUserUnstakePool > stakeAmount) {
                uint256 overshoot = amountInUserUnstakePool - stakeAmount;
                //Let;s say we are at 49 in the stake pool, and then the current position has 10.
                //and we wanted to stake a total of 50
                //Once we add the amount in this pool, we have a total of 59 in the stake pool amount.
                //That means we overshot by 59-50, and the new amount in the stake pool
                //Should be the overshot amount.
                //Instead of having 10 in the latest pool, we have 9 since we needed to pull 1
                newHead = i; //If we overshot, the head stays the same and it does indeed still have data
                _unstakedPositions[msg.sender][i].amount = SafeCast.toUint192(overshoot);
                break;
            }

            //If we have reached the tail (oldest position) and we still haven't overshot
            //We delete the tail
            if (i == tail) {
                if (stakeAmount > amountInUserUnstakePool) {
                    delete _unstakedPositions[msg.sender][tail];
                }
                newHead = tail;
                break;
            }
        }

        //If the new head is not equal to the old head, we update the head in storage
        //We use this equality check to prevent redundant sstores
        if (newHead != head) {
            _unstakedPositionPointers[msg.sender].head = SafeCast.toUint128(newHead);
        }

        //If the stake amount is greater than the amount in the user unstake pool
        //Then we need to transfer the difference from the user to the contract
        if (stakeAmount > amountInUserUnstakePool) {
            uint256 amountGlowToTransfer = stakeAmount - amountInUserUnstakePool;
            _transfer(msg.sender, address(this), amountGlowToTransfer);
        }

        //Note: We don't handle the zero case since that would be a redundant transfer

        //Increase the number of tokens staked by the user
        numStaked[msg.sender] += stakeAmount;
        //Emit the Stake event
        emit IGlow.Stake(msg.sender, stakeAmount);
    }

    /**
     * @inheritdoc IGlow
     */
    function unstake(uint256 amount) external {
        //Revert on zero amount
        if (amount == 0) _revert(IGlow.CannotUnstakeZeroTokens.selector);

        //Load the number of tokens staked by the user
        uint256 numAccountStaked = numStaked[msg.sender];

        //if the user is unstaking more than they have staked, we revert
        if (amount > numAccountStaked) {
            _revert(IGlow.UnstakeAmountExceedsStakedBalance.selector);
        }

        //Find the length of the unstaked positions starting at the tail
        //This gives us the # of unstaked positions that the user has
        Pointers memory pointers = _unstakedPositionPointers[msg.sender];
        uint256 adjustedLenBefore = pointers.head - pointers.tail + 1;

        uint256 indexInMappingToPushTo = pointers.head + 1;
        if (pointers.head == pointers.tail) {
            if (_unstakedPositions[msg.sender][pointers.head].amount == 0) {
                adjustedLenBefore = 0;
                indexInMappingToPushTo = pointers.head;
            }
        }

        //if adjustlenBefore >= 99
        // we + 2 to proactively set emergencyLastUpdate when length will be 99 so the 100th unstake will trigger cooldown
        if (adjustedLenBefore + 2 > MAX_UNSTAKES_BEFORE_EMERGENCY_COOLDOWN) {
            uint256 lastUnstakedTimestamp = emergencyLastUnstakeTimestamp[msg.sender];

            //Handle the zero case
            if (lastUnstakedTimestamp == 0) {
                emergencyLastUnstakeTimestamp[msg.sender] = block.timestamp;
                // if the user has unstaked before, we need to check if they are in cooldown
            } else if (block.timestamp - lastUnstakedTimestamp < EMERGENCY_COOLDOWN_PERIOD) {
                _revert(IGlow.UnstakingOnEmergencyCooldown.selector);
                // if the user is not in cooldown, we need to update the timestamp
            } else {
                emergencyLastUnstakeTimestamp[msg.sender] = block.timestamp;
            }
        }

        //Decrease the number of tokens staked by the user
        numStaked[msg.sender] = numAccountStaked - amount;

        _unstakedPositions[msg.sender][indexInMappingToPushTo] = UnstakedPosition({
            amount: SafeCast.toUint192(amount),
            cooldownEnd: SafeCast.toUint64(block.timestamp + _STAKE_COOLDOWN_PERIOD)
        });

        pointers = Pointers({head: SafeCast.toUint128(indexInMappingToPushTo), tail: pointers.tail});

        _unstakedPositionPointers[msg.sender] = pointers;
        emit IGlow.Unstake(msg.sender, amount);
    }

    /**
     * @inheritdoc IGlow
     */
    function claimUnstakedTokens(uint256 amount) external {
        //Cannot claim zero tokens
        if (amount == 0) _revert(IGlow.CannotClaimZeroTokens.selector);
        uint256 claimableTotal;

        //Cache len]0
        Pointers memory pointers = _unstakedPositionPointers[msg.sender];

        uint256 head = pointers.head;
        uint256 tail = pointers.tail;
        uint256 newTail = tail;

        //Loop through the unstaked positions until claimableTotal >= amount
        //Tail will also be <= len so no risk of underflow
        //Tail should also remain close to len since we delete unstaked positions as we claim them
        //and we restrict the number of unstaked positions to 100 before a cooldown is enforced on the user

        for (uint256 i = tail; i <= head; ++i) {
            //Read the position from storage
            UnstakedPosition storage position = _unstakedPositions[msg.sender][i];
            //if block.timestamp <= position.cooldownEnd
            //If the position is not ready to be claimed, we revert
            //  -   this is so because we can't claim tokens that are not ready to be claimed
            //  -   and positions are chronologically ordered, so if one position is not ready to be claimed,
            //  -   all following positions are not ready to be claimed
            //  -   therefore, we can revert early since we'll never have enough tokens to fulfill the claim
            if (position.cooldownEnd >= block.timestamp) {
                _revert(IGlow.InsufficientClaimableBalance.selector);
            }

            //Increment the claimableTotal by the position amount
            claimableTotal += position.amount;

            //If the claimableTotal is equal to the amount, we need to delete the old position and increment the newTail
            // - since the old unstaked positions EXACTLY fulfill the amount
            if (claimableTotal == amount) {
                newTail = i + 1;
                if (newTail > head) {
                    newTail = head;
                }
                //Update the tail in storage
                _unstakedPositionPointers[msg.sender] =
                    Pointers({head: SafeCast.toUint128(head), tail: SafeCast.toUint128(newTail)});
                //delete the position for a gas refund
                delete _unstakedPositions[msg.sender][i];
                //transfer the amount to the user
                _transfer(address(this), msg.sender, amount);
                //emit the claim event
                emit IGlow.ClaimUnstakedGLW(msg.sender, amount);
                return;
            }

            //If the claimableTotal is greater than the amount, we need to  deduct from the position in storage
            // and the tail will stay the same since the unstaked position still has some tokens left
            if (claimableTotal > amount) {
                //New tail is equal to i
                newTail = i;
                //Check redundancy before sstoring the new tail
                if (newTail != tail) {
                    _unstakedPositionPointers[msg.sender] =
                        Pointers({head: SafeCast.toUint128(head), tail: SafeCast.toUint128(newTail)});
                }
                //Calculate the amount that is left in the position after the claim
                uint256 amountLeftInPosition = claimableTotal - amount;
                //Update the position amount in storage
                position.amount = SafeCast.toUint192(amountLeftInPosition);
                //Transfer the amount to the user
                _transfer(address(this), msg.sender, amount);
                //Emit the claim event
                emit IGlow.ClaimUnstakedGLW(msg.sender, amount);
                return;
            }

            //When looping, we delete all unstaked positions that are consumed
            // as part of the token claim
            delete _unstakedPositions[msg.sender][i];
        }

        _revert(IGlow.InsufficientClaimableBalance.selector);
    }

    /* -------------------------------------------------------------------------- */
    /*                                  inflation                                 */
    /* -------------------------------------------------------------------------- */
    /**
     * @inheritdoc IGlow
     */
    function claimGLWFromGCAAndMinerPool() external returns (uint256) {
        //If the address is not set, we revert
        if (_isZeroAddress(gcaAndMinerPoolAddress)) _revert(IGlow.AddressNotSet.selector);
        //If the caller is not the GCA and Miner Pool, we revert
        if (msg.sender != gcaAndMinerPoolAddress) _revert(IGlow.CallerNotGCA.selector);
        //Read the timestamp from storage
        uint256 timestampInStorage = gcaAndMinerPoolLastClaimedTimestamp;
        //If the timestamp is zero, we set it to the genesis timestamp
        // else we set it to the timestamp in storage
        uint256 timestampToClaimFrom = timestampInStorage == 0 ? GENESIS_TIMESTAMP : timestampInStorage;
        //Calculate the seconds since the last claim
        uint256 secondsSinceLastClaim = block.timestamp - timestampToClaimFrom;
        //Calculate the amount to claim
        uint256 amountToClaim = secondsSinceLastClaim * GCA_AND_MINER_POOL_INFLATION_PER_SECOND;
        //If the amount to claim is zero, we return zero and exit
        if (amountToClaim == 0) return 0;
        //if the amount is not zero, we update the timestamp in storage
        gcaAndMinerPoolLastClaimedTimestamp = block.timestamp;
        //and we mint the amount to the GCA and Miner Pool
        _mint(gcaAndMinerPoolAddress, amountToClaim);
        //we then return the amount to claim
        return amountToClaim;
    }

    /**
     * @inheritdoc IGlow
     */
    function claimGLWFromVetoCouncil() external returns (uint256) {
        //If the address is not set, we revert
        if (_isZeroAddress(vetoCouncilAddress)) _revert(IGlow.AddressNotSet.selector);
        //If the caller is not the Veto Council, we revert
        if (msg.sender != vetoCouncilAddress) _revert(IGlow.CallerNotVetoCouncil.selector);
        //Read the timestamp from storage
        uint256 timestampInStorage = vetoCouncilLastClaimedTimestamp;
        //If the timestamp is zero, we set it to the genesis timestamp
        // else we set it to the timestamp in storage
        uint256 timestampToClaimFrom = timestampInStorage == 0 ? GENESIS_TIMESTAMP : timestampInStorage;
        //Calculate the seconds since the last claim
        uint256 secondsSinceLastClaim = block.timestamp - timestampToClaimFrom;
        //Calculate the amount to claim
        uint256 amountToClaim = secondsSinceLastClaim * VETO_COUNCIL_INFLATION_PER_SECOND;
        //If the amount to claim is zero, we return zero and exit
        if (amountToClaim == 0) return 0;
        //if the amount is not zero, we update the timestamp in storage
        vetoCouncilLastClaimedTimestamp = block.timestamp;
        //and we mint the amount to the Veto Council
        _mint(vetoCouncilAddress, amountToClaim);
        //we then return the amount to claim
        return amountToClaim;
    }

    /**
     * @inheritdoc IGlow
     */
    function claimGLWFromGrantsTreasury() external returns (uint256) {
        //If the address is not set, we revert
        if (_isZeroAddress(grantsTreasuryAddress)) _revert(IGlow.AddressNotSet.selector);
        //If the caller is not the Grants Treasury, we revert
        if (msg.sender != grantsTreasuryAddress) _revert(IGlow.CallerNotGrantsTreasury.selector);
        //Read the timestamp from storage
        uint256 timestampInStorage = grantsTreasuryLastClaimedTimestamp;
        //If the timestamp is zero, we set it to the genesis timestamp
        // else we set it to the timestamp in storage
        uint256 timestampToClaimFrom = timestampInStorage == 0 ? GENESIS_TIMESTAMP : timestampInStorage;
        //Calculate the seconds since the last claim
        uint256 secondsSinceLastClaim = block.timestamp - timestampToClaimFrom;
        //Calculate the amount to claim
        uint256 amountToClaim = secondsSinceLastClaim * GRANTS_TREASURY_INFLATION_PER_SECOND;
        //If the amount to claim is zero, we return zero and exit
        if (amountToClaim == 0) return 0;
        //if the amount is not zero, we update the timestamp in storage
        grantsTreasuryLastClaimedTimestamp = block.timestamp;
        //and we mint the amount to the Grants Treasury
        _mint(grantsTreasuryAddress, amountToClaim);
        //we then return the amount to claim
        return amountToClaim;
    }

    /* -------------------------------------------------------------------------- */
    /*                                view functions                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @inheritdoc IGlow
     */
    function unstakedPositionsOf(address account) external view returns (UnstakedPosition[] memory) {
        Pointers memory pointers = _unstakedPositionPointers[account];
        uint256 start = pointers.tail;
        uint256 end = pointers.head + 1;
        UnstakedPosition[] memory positions = new UnstakedPosition[](end - start);

        if (pointers.tail == pointers.head) {
            UnstakedPosition memory position = _unstakedPositions[account][pointers.head];
            if (position.amount == 0) {
                // solhint-disable-next-line no-inline-assembly
                assembly {
                    mstore(positions, 0)
                }
                return positions;
            }
            positions[0] = position;
            ++start;
        }
        unchecked {
            //Start is always less than end so no risk of underflow
            //start should also be close to end since we delete unstaked positions as we claim them
            // and we restrict the number of unstaked positions to 100 before a cooldown is enforced on the user
            for (uint256 i = start; i < end; ++i) {
                UnstakedPosition memory position = _unstakedPositions[account][i];
                //If the tail is zero and the amount is zero, that means
                //There has never been a stake, because if there had been a stake,
                //The amount wouldn't be empty,
                //And if the amount is empty that means that there has been a claim on that position
                //And the tail would not be zero
                if (i == 0) {
                    if (position.amount == 0) {
                        // solhint-disable-next-line no-inline-assembly
                        assembly {
                            //set the length to 0 in memory
                            mstore(positions, 0)
                        }
                        break;
                    }
                }
                //No addition, therefore no risk of overflow
                //i always >= start so no risk of underflow
                positions[i - start] = position;
            }
            return positions;
        }
    }

    /**
     * @notice returns the tail of the unstaked positions for the user
     * @param account the account to get the tail for
     * @return the tail of the unstaked positions for the user
     */
    function accountUnstakedPositionPointers(address account) external view returns (Pointers memory) {
        return _unstakedPositionPointers[account];
    }

    /**
     * @inheritdoc IGlow
     */

    function unstakedPositionsOf(address account, uint256 start, uint256 end)
        external
        view
        returns (UnstakedPosition[] memory)
    {
        Pointers memory pointers = _unstakedPositionPointers[account];
        start = start + pointers.tail;
        end = end + pointers.tail;
        if (end > pointers.head + 1) {
            end = pointers.head + 1;
        }

        //If the start is greater than the end, we return an empty array
        if (start >= end) {
            return new UnstakedPosition[](0);
        }
        UnstakedPosition[] memory positions = new UnstakedPosition[](end - start);

        if (pointers.tail == pointers.head) {
            UnstakedPosition memory position = _unstakedPositions[account][pointers.head];
            if (position.amount == 0) {
                // solhint-disable-next-line no-inline-assembly
                assembly {
                    mstore(positions, 0)
                }
                return positions;
            }
            positions[0] = position;
            ++start;
        }

        unchecked {
            //Start is always less than end so no risk of underflow
            //start should also be close to end since we delete unstaked positions as we claim them
            // and we restrict the number of unstaked positions to 100 before a cooldown is enforced on the user
            for (uint256 i = start; i < end; ++i) {
                UnstakedPosition memory position = _unstakedPositions[account][i];
                //If the tail is zero and the amount is zero, that means
                //There has never been a stake, because if there had been a stake,
                //The amount wouldn't be empty,
                //And if the amount is empty that means that there has been a claim on that position
                //And the tail would not be zero
                if (i == 0) {
                    if (position.amount == 0) {
                        // solhint-disable-next-line no-inline-assembly
                        assembly {
                            //set the length to 0 in memory
                            mstore(positions, 0)
                        }
                        break;
                    }
                }
                //No addition, therefore no risk of overflow
                //i always >= start so no risk of underflow
                positions[i - start] = position;
            }
            return positions;
        }
    }

    /**
     * @inheritdoc IGlow
     */
    function gcaInflationData() external view returns (uint256, uint256 totalAlreadyClaimed, uint256 totalToClaim) {
        if (_isZeroAddress(gcaAndMinerPoolAddress)) _revert(IGlow.AddressNotSet.selector);
        uint256 timestampInStorage = gcaAndMinerPoolLastClaimedTimestamp;
        uint256 timestampToClaimFrom = timestampInStorage == 0 ? GENESIS_TIMESTAMP : timestampInStorage;
        uint256 secondsSinceLastClaim = block.timestamp - timestampToClaimFrom;
        totalToClaim = secondsSinceLastClaim * GCA_AND_MINER_POOL_INFLATION_PER_SECOND;
        totalAlreadyClaimed = timestampToClaimFrom - GENESIS_TIMESTAMP;
        return (timestampInStorage, totalAlreadyClaimed, totalToClaim);
    }

    /**
     * @inheritdoc IGlow
     */
    function vetoCouncilInflationData()
        external
        view
        returns (uint256, uint256 totalAlreadyClaimed, uint256 totalToClaim)
    {
        if (_isZeroAddress(vetoCouncilAddress)) _revert(IGlow.AddressNotSet.selector);
        uint256 timestampInStorage = vetoCouncilLastClaimedTimestamp;
        uint256 timestampToClaimFrom = timestampInStorage == 0 ? GENESIS_TIMESTAMP : timestampInStorage;
        uint256 secondsSinceLastClaim = block.timestamp - timestampToClaimFrom;
        totalToClaim = secondsSinceLastClaim * VETO_COUNCIL_INFLATION_PER_SECOND;
        totalAlreadyClaimed = timestampToClaimFrom - GENESIS_TIMESTAMP;
        return (timestampInStorage, totalAlreadyClaimed, totalToClaim);
    }

    /**
     * @inheritdoc IGlow
     */
    function grantsTreasuryInflationData()
        external
        view
        returns (uint256, uint256 totalAlreadyClaimed, uint256 totalToClaim)
    {
        if (_isZeroAddress(grantsTreasuryAddress)) _revert(IGlow.AddressNotSet.selector);
        uint256 timestampInStorage = grantsTreasuryLastClaimedTimestamp;
        uint256 timestampToClaimFrom = timestampInStorage == 0 ? GENESIS_TIMESTAMP : timestampInStorage;
        uint256 secondsSinceLastClaim = block.timestamp - timestampToClaimFrom;
        totalToClaim = secondsSinceLastClaim * GRANTS_TREASURY_INFLATION_PER_SECOND;
        totalAlreadyClaimed = timestampToClaimFrom - GENESIS_TIMESTAMP;
        return (timestampInStorage, totalAlreadyClaimed, totalToClaim);
    }

    /* -------------------------------------------------------------------------- */
    /*                                one time setters                            */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Sets the addresses of the GCA and Miner Pool, Veto Council, and Grants Treasury
     * @dev this function can only be called once
     */
    function setContractAddresses(
        address _gcaAndMinerPoolAddress,
        address _vetoCouncilAddress,
        address _grantsTreasuryAddress
    ) external {
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
    }

    /* -------------------------------------------------------------------------- */
    /*                                 privte utils                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Returns the smaller of two numbers
     * @param a The first number
     * @param b The second number
     */
    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @notice More efficiently reverts with a bytes4 selector
     * @param selector The selector to revert with
     */
    function _revert(bytes4 selector) private pure {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(0x0, selector)
            revert(0x0, 0x04)
        }
    }

    /**
     * @notice More efficient address(0) check
     */
    function _isZeroAddress(address _address) private pure returns (bool isZero) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            isZero := iszero(_address)
        }
    }
}

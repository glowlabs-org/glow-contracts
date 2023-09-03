// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IGlow} from "./interfaces/IGlow.sol";
import "forge-std/console.sol";

contract Glow is ERC20, IGlow {
    //----------------------- CONSTANTS -----------------------//

    /// @notice The cooldown period after unstaking before a user can claim their tokens
    uint256 private constant _STAKE_COOLDOWN_PERIOD = 365 days * 5;

    /// @notice The amount of GLW that is minted per second for the GCA and Miner Pool
    /// @notice 185,000 GLW per week
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

    //----------------------- IMMUTABLES -----------------------//

    /// @notice The timestamp of the genesis block
    // solhint-disable-next-line var-name-mixedcase
    uint256 public immutable GENESIS_TIMESTAMP;

    /// @notice The address of the Early Liquidity Contract
    //  solhint-disable-next-line var-name-mixedcase
    address public immutable EARLY_LIQUIDITY_ADDRESS;

    //----------------------- STATE VARIABLES -----------------------//

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

    //----------------------- MAPPINGS -----------------------//

    /// @notice stores the total amount of GLOW staked by a user
    mapping(address => uint256) public numStaked;

    /// @notice stores the unstaked positions of a user
    mapping(address => UnstakedPosition[]) private _unstakedPositions;

    /// @notice stores the tail of the unstaked positions of a user
    mapping(address => uint256) private _unstakedPositionTail;

    /// @notice stores the last time a user staked in case the user has over 100 staked positions
    mapping(address => uint256) public emergencyLastUnstakeTimestamp;

    //************************************************************* */
    //************************  CONSTRUCTOR    ******************* */
    //************************************************************* */

    /// @notice Sets the immutable variables (GENESIS_TIMESTAMP, EARLY_LIQUIDITY_ADDRESS)
    /// @notice sends 12 million GLW to the Early Liquidity Contract
    /// @param _earlyLiquidityAddress The address of the Early Liquidity Contract
    constructor(address _earlyLiquidityAddress, address _vestingContract) ERC20("Glow", "GLOW") {
        GENESIS_TIMESTAMP = block.timestamp;
        EARLY_LIQUIDITY_ADDRESS = _earlyLiquidityAddress;
        _mint(EARLY_LIQUIDITY_ADDRESS, 12_000_000 ether);
        _mint(_vestingContract, 60_000_000 ether);
    }

    /**
     * @inheritdoc IGlow
     * @dev if the user has unstaked positions that have already expired,
     *         -   the function will auto claim those tokens for the user
     */
    function stake(uint256 stakeAmount) external {
        //Cannot stake zero tokens
        if (stakeAmount == 0) _revert(IGlow.CannotStakeZeroTokens.selector);

        //Find the tail in the mapping
        uint256 tail = _unstakedPositionTail[msg.sender];

        //Init the unstakedTotal
        uint256 unstakedTotal;

        //Init the newTail
        uint256 newTail = tail;

        //Cache len that we are traversing
        //Unstaked positions should rarely be over 100 due to the cooldown period
        uint256 len = _unstakedPositions[msg.sender].length;

        //Init the amountClaimable -
        //  -   this is the amount of tokens that are claimable from unstaked positions that are ready to be claimed
        // This can't overflow since amountClaimable < totlaSupply < type(uint256).max
        uint256 amountClaimable;

        //Tail will also be <= len so no risk of underflow
        //Tail should also remain close to len since we delete unstaked positions as we claim them
        //and we restrict the number of unstaked positions to 100 before a cooldown is enforced on the user
        for (uint256 i = tail; i < len; ++i) {
            //Load position from storage
            UnstakedPosition storage position = _unstakedPositions[msg.sender][i];
            //Case 1: The position is ready to be claimed (block.timestamp > position.cooldownEnd)
            //  -   we add the amount to the amountClaimable
            //  -   we update the newTail in memory
            //  -  we continue to the next iteration
            if (block.timestamp > position.cooldownEnd) {
                amountClaimable += position.amount;
                newTail = i + 1;
                continue;
            }

            //Case 2: The position is not ready to be claimed (block.timestamp <= position.cooldownEnd)

            //cache the position amount (the amount of glow that is unstaked in the position)
            //increment the unstakedTotal by the position amount
            uint256 positionAmount = position.amount;
            unstakedTotal += positionAmount;

            //If the unstakedTotal is equal to the stakeAmount, we need to delete the old position and increment the newTail
            // because the old stake positions EXACTLY fulfill the stakeAmount
            // (this should be an extremely rare case)
            // - we also need to break since we have fulfilled the stakeAmount
            // the old "unstaked tokens" inside the position are now used to fulfill the stakeAmount
            if (unstakedTotal == stakeAmount) {
                newTail = i + 1;
                delete _unstakedPositions[msg.sender][i];
                break;
            }

            /*
                if claimableTotal > stakeAmount, it means that the user has more unstaked tokens than they need to fulfill the stakeAmount
                and we need to ensure to partially deduct the user's unstaked position ao we dont over fulfill the stakeAmount 
                the tail should not change since we are deducting "amount" from the current position and not deleting it
                    -   this is so because the position does not need to be fully drained to fulfill the stakeAmount, so we need to keep it in the array with its new amount
            */
            if (unstakedTotal > stakeAmount) {
                newTail = i;
                uint256 amountThatIsNeededToFulfill = unstakedTotal - stakeAmount;
                position.amount = uint192(amountThatIsNeededToFulfill);
                break;
            }

            //Case 4: If there aren't any more unstaked positions to check
            // that means that we've used up all the unstaked positions to fulfill the stakeAmount
            // and can remove them from the linked list
            // we also delete  the position for a gas refund
            newTail = i + 1;
            delete _unstakedPositions[msg.sender][i];
        }

        //Check if the newTail is different from the old tail
        //If it is, we need to update the tail
        // This conditional prevents redundant sstores
        if (newTail != tail) {
            _unstakedPositionTail[msg.sender] = newTail;
        }

        //set the unstakedTotal to the minimum of the stakeAmount and the unstakedTotal
        //  -   so that amountToTransferFromUser is never negative and we don't revert for underflow
        // we need to set it to min because there's a chance we overcounted unstakedTotal in the loop, so this line is a safety check
        unstakedTotal = _min(unstakedTotal, stakeAmount);

        //Calculate the amountToTransferFromUser which is the amount that the user needs to transfer to the contract
        //This should be impossible to overflow since supply is 72 million ether with an inflation of 12 million ether / year
        //It's impossible to overflow since unstakedTotal <= stakeAmount
        uint256 amountToTransferFromUser = stakeAmount - unstakedTotal;

        //Impossible to overflow since supply is 72 million ether
        //  -   with 12 million ether inflation / year
        // The amount the user owes is equal to the amount we need them to transfer - the amount they have claimable
        int256 amountUserOwes = int256(amountToTransferFromUser) - int256(amountClaimable);
        //numStaked shouldn't be able to overflow since supply is 72 million ether with 12 million ether inflation / year
        numStaked[msg.sender] += stakeAmount;

        //We now need to check if the user is owed tokens or if they owe the contrac tokens
        //In most cases, the user should need to transfer tokens to the contract
        //In the less rare cases, the user will receive claimable tokkens from the contract
        //      -People should use the claimTokens function to claim tokens rather than using the staking function
        //      -The staking function simply catches edge cases that would cause the user to incur a net loss of tokens

        //If the user owes us tokens, we need to transfer it from them
        if (amountUserOwes > 0) {
            _transfer(msg.sender, address(this), uint256(amountUserOwes));
        }

        //If the user has claimable tokens, we need to transfer it to them
        if (amountUserOwes < 0) {
            _transfer(address(this), msg.sender, uint256(-amountUserOwes));
        }

        //Note: We don't handle the zero case since that would be a redundant transfer

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

        //Cache the length of the unstaked positions
        uint256 lenBefore = _unstakedPositions[msg.sender].length;
        //Cache the tail of the unstaked positions
        uint256 tail = _unstakedPositionTail[msg.sender];

        //Find the length of the unstaked positions starting at the tail
        //This gives us the # of unstaked positions that the user has
        uint256 adjustedLenBefore = lenBefore - tail;

        //TODO: I don't think we actually need this. check with @david,  just let people DoS themselves
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

        //Push an unstaked position to the user's unstaked positions
        _unstakedPositions[msg.sender].push(
            UnstakedPosition({amount: uint192(amount), cooldownEnd: uint64(block.timestamp + _STAKE_COOLDOWN_PERIOD)})
        );

        //Emit the Unstake event
        emit IGlow.Unstake(msg.sender, amount);
    }

    /**
     * @inheritdoc IGlow
     */
    function claimUnstakedTokens(uint256 amount) external {
        //Cannot claim zero tokens
        if (amount == 0) _revert(IGlow.CannotClaimZeroTokens.selector);
        //read the tail of the msg.sender from storage
        uint256 tail = _unstakedPositionTail[msg.sender];
        //init the claimableTotal
        uint256 claimableTotal;
        //init the newTail (cache tail)
        uint256 newTail = tail;

        //Cache len
        uint256 len = _unstakedPositions[msg.sender].length;

        //Loop through the unstaked positions until claimableTotal >= amount
           //Tail will also be <= len so no risk of underflow
        //Tail should also remain close to len since we delete unstaked positions as we claim them
        //and we restrict the number of unstaked positions to 100 before a cooldown is enforced on the user
        for (uint256 i = tail; i < len; ++i) {
            //Read the position from storage
            UnstakedPosition storage position = _unstakedPositions[msg.sender][i];
            //another way of saying this is block.timestamp >= position.cooldownEnd
            //If the position is not ready to be claimed, we revert
            //  -   this is so because we can't claim tokens that are not ready to be claimed
            //  -   and positions are chronologically ordered, so if one position is not ready to be claimed,
            //  -   all following positions are not ready to be claimed
            //  -   therefore, we can revert early since we'll never have enough tokens to fulfill the claim
            if (!(position.cooldownEnd < block.timestamp)) {
                _revert(IGlow.InsufficientClaimableBalance.selector);
            }

            //Cache the position amount (the amount of glow that is unstaked in the position)
            uint256 positionAmount = position.amount;
            //Increment the claimableTotal by the position amount
            claimableTotal += positionAmount;

            //If the claimableTotal is equal to the amount, we need to delete the old position and increment the newTail
            // - since the old unstaked positions EXACTLY fulfill the amount
            if (claimableTotal == amount) {
                newTail = i + 1;
                //Update teh tail in storage
                _unstakedPositionTail[msg.sender] = newTail;
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
                    _unstakedPositionTail[msg.sender] = newTail;
                }
                //Calculate the amount that is left in the position after the claim
                uint256 amountLeftInPosition = claimableTotal - amount;
                //Update the position amount in storage
                position.amount = uint192(amountLeftInPosition);
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

    //************************************************************* */
    //*********************  TOKEN INFLATION STATE    ******************** */
    //************************************************************* */

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

    //************************************************************* */
    //**********************  VIEW FUNCTIONS    ******************** */
    //************************************************************* */

    /**
     * @inheritdoc IGlow
     */
    function unstakedPositionsOf(address account) external view returns (UnstakedPosition[] memory) {
        uint256 start = _unstakedPositionTail[account];
        uint256 end = _unstakedPositions[account].length;
        unchecked {
            //The sload is safe since it's in storage through {unstake}
            UnstakedPosition[] memory positions = new UnstakedPosition[](end - start);
            //Start is always less than end so no risk of underflow
            //start should also be close to end since we delete unstaked positions as we claim them
            // and we restrict the number of unstaked positions to 100 before a cooldown is enforced on the user
            for (uint256 i = start; i < end; ++i) {
                //No addittion, therefore no risk of overflow
                //i always >= start so no risk of underflow
                positions[i - start] = _unstakedPositions[account][i];
            }
            return positions;
        }
    }

    /**
     * @notice returns the tail of the unstaked positions for the user
     * @param account the account to get the tail for
     * @return the tail of the unstaked positions for the user
     */
    function tail(address account) external view returns (uint256) {
        return _unstakedPositionTail[account];
    }

    /**
     * @inheritdoc IGlow
     */

    function unstakedPositionsOf(address account, uint256 start, uint256 end)
        external
        view
        returns (UnstakedPosition[] memory)
    {
        //Find the total length of the unstaked positions
        uint256 length = _unstakedPositions[account].length;
        //Find the tail of the unstaked positions
        uint256 tail = _unstakedPositionTail[account];

        //Make sure the end is equal to the end + tail
        //This is so because start only counts from the start of tail
        end = end + tail;

        //If the start is greater than the length, we return an empty array
        if (start >= length) {
            return new UnstakedPosition[](0);
        }

        //If the end is greater than the length, we set the end to the length
        // so that we don't get an index out of bounds error
        if (end > length) {
            end = length;
        }

        //Make sure that start adjusts for the tail
        start = tail + start;

        //Calculate actu len
        uint256 len = end - start;

        //Init the positions array
        UnstakedPosition[] memory positions = new UnstakedPosition[](len);
         //Start is always less than end so no risk of underflow
        //start should also be close to end since we delete unstaked positions as we claim them
        // and we restrict the number of unstaked positions to 100 before a cooldown is enforced on the user
        for (uint256 i = start; i < end;) {
            positions[i - start] = _unstakedPositions[account][i];
            //No risk of overflow since i is always less than end
            unchecked {
                ++i;
            }
        }

        return positions;
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

    //************************************************************* */
    //*********************  ONE TIME SETTERS    ******************** */
    //************************************************************* */

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
        gcaAndMinerPoolAddress = _gcaAndMinerPoolAddress;
        vetoCouncilAddress = _vetoCouncilAddress;
        grantsTreasuryAddress = _grantsTreasuryAddress;
    }

    //************************************************************* */
    //*******************  PRIVATE HELPER FUNCS    **************** */
    //************************************************************* */

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
        assembly {
            mstore(0x0, selector)
            revert(0x0, 0x04)
        }
    }

    /**
     * @notice More efficient address(0) check
     */
    function _isZeroAddress(address _address) private pure returns (bool isZero) {
        assembly {
            isZero := iszero(_address)
        }
    }
}

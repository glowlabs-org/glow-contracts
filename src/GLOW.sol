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
    /// TODO: Implement this logic
    mapping(address => uint256) public emergencyLastStakeTime;

    //----------------------- CONSTRUCTOR -----------------------//

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
        uint256 len = _unstakedPositions[msg.sender].length;

        //Init the amountClaimable -
        //  -   this is the amount of tokens that are claimable from unstaked positions
        uint256 amountClaimable;

        for (uint256 i = tail; i < len;) {
            UnstakedPosition storage position = _unstakedPositions[msg.sender][i];

            if (block.timestamp > position.cooldownEnd) {
                amountClaimable += position.amount;
                newTail = i + 1;
                continue;
            }
            uint256 positionAmount = position.amount;
            unstakedTotal += positionAmount;
            if (unstakedTotal == stakeAmount) {
                newTail = i + 1;
                delete _unstakedPositions[msg.sender][i];
                break;
            }
            /*
                if claimableTotal > stakeAmount, it means we overshot claimableTotal
                and we need to ensure to partially deduct the user's unstaked position
                and need to correctly set the tail
            */
            if (unstakedTotal > stakeAmount) {
                newTail = i;
                uint256 amountThatIsNeededToFulfill = unstakedTotal - stakeAmount;
                position.amount = uint192(amountThatIsNeededToFulfill);
                break;
            }
            //In the less than case,
            newTail = i + 1;
            delete _unstakedPositions[msg.sender][i];

            //Unchecked since we are iterating over a bounded array
            unchecked {
                ++i;
            }
        }

        //Check if the newTail is different from the old tail
        //If it is, we need to update the tail
        if (newTail != tail) {
            _unstakedPositionTail[msg.sender] = newTail;
        }   

        //set the unstakedTotal to the minimum of the stakeAmount and the unstakedTotal
        //  -   so that amountToTransferFromUser is never negative and we don't revert for underflow
        unstakedTotal = _min(unstakedTotal, stakeAmount);

        //Calculate the amountToTransferFromUser
        uint256 amountToTransferFromUser = stakeAmount - unstakedTotal;

        //Impossible to overflow since supply is 72 million ether
        //  -   with 12 million ether inflation / year
        // The amount the user owes is equal to the amount we need them to transfer - the amount they have claimable
        int256 amountUserOwes = int256(amountToTransferFromUser) - int256(amountClaimable);
        numStaked[msg.sender] += stakeAmount;

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
        if (amount == 0) _revert(IGlow.CannotUnstakeZeroTokens.selector);
        uint256 numAccountStaked = numStaked[msg.sender];
        if (amount > numAccountStaked) {
            _revert(IGlow.UnstakeAmountExceedsStakedBalance.selector);
        }
        uint256 lenBefore = _unstakedPositions[msg.sender].length;
        uint256 tail = _unstakedPositionTail[msg.sender];
        uint256 adjustedLenBefore = lenBefore - tail;

        //TODO: I don't think we actually need this. check with @david,  just let people DoS themselves
        if (adjustedLenBefore + 1 > MAX_UNSTAKES_BEFORE_EMERGENCY_COOLDOWN) {
            uint256 lastStakedTimestamp = emergencyLastStakeTime[msg.sender];
            if (block.timestamp - lastStakedTimestamp < EMERGENCY_COOLDOWN_PERIOD) {
                _revert(IGlow.UnstakingOnEmergencyCooldown.selector);
            }
            emergencyLastStakeTime[msg.sender] = block.timestamp;
        }
        numStaked[msg.sender] = numAccountStaked - amount;
        _unstakedPositions[msg.sender].push(
            UnstakedPosition({amount: uint192(amount), cooldownEnd: uint64(block.timestamp + _STAKE_COOLDOWN_PERIOD)})
        );

        emit IGlow.Unstake(msg.sender, amount);
    }

    /**
     * @inheritdoc IGlow
     */
    function unstakedPositionsOf(address account) external view returns (UnstakedPosition[] memory) {
        uint256 start = _unstakedPositionTail[account];
        uint256 end = _unstakedPositions[account].length;
        unchecked {
            UnstakedPosition[] memory positions = new UnstakedPosition[](end - start);
            for (uint256 i = start; i < end; ++i) {
                positions[i - start] = _unstakedPositions[account][i];
            }
            return positions;
        }
    }

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
        uint256 length = _unstakedPositions[account].length;
        uint256 tail = _unstakedPositionTail[account];
        end = end + tail;
        if (start >= length) {
            return new UnstakedPosition[](0);
        }
        if (end > length) {
            end = length;
        }

        start = tail + start;
        uint256 len = end - start;
        UnstakedPosition[] memory positions = new UnstakedPosition[](len);
        for (uint256 i = start; i < end; ++i) {
            positions[i - start] = _unstakedPositions[account][i];
        }

        return positions;
    }

    /**
     * @inheritdoc IGlow
     */
    function claimUnstakedTokens(uint256 amount) external {
        if (amount == 0) _revert(IGlow.CannotClaimZeroTokens.selector);
        uint256 tail = _unstakedPositionTail[msg.sender];
        uint256 claimableTotal;
        uint256 newTail = tail;

        for (uint256 i = tail; i < _unstakedPositions[msg.sender].length; ++i) {
            UnstakedPosition storage position = _unstakedPositions[msg.sender][i];
            //another way of saying this is block.timestamp >= position.cooldownEnd
            if (!(position.cooldownEnd < block.timestamp)) {
                _revert(IGlow.InsufficientClaimableBalance.selector);
            }
            uint256 positionAmount = position.amount;
            claimableTotal += positionAmount;
            if (claimableTotal == amount) {
                newTail = i + 1;
                _unstakedPositionTail[msg.sender] = newTail;
                delete _unstakedPositions[msg.sender][i];
                _transfer(address(this), msg.sender, amount);
                emit IGlow.ClaimUnstakedGLW(msg.sender, amount);
                return;
            }

            if (claimableTotal > amount) {
                newTail = i;
                if (newTail != tail) {
                    _unstakedPositionTail[msg.sender] = newTail;
                }
                uint256 amountThatIsNeededToFulfill = claimableTotal - amount;
                position.amount = uint192(amountThatIsNeededToFulfill);
                _transfer(address(this), msg.sender, amount);
                emit IGlow.ClaimUnstakedGLW(msg.sender, amount);
                return;
            }

            delete _unstakedPositions[msg.sender][i];
        }

        _revert(IGlow.InsufficientClaimableBalance.selector);
    }

    //----------------------- TOKEN INFLATION ----------------------//

    /**
     * @inheritdoc IGlow
     */
    function claimGLWFromGCAAndMinerPool() external returns (uint256) {
        if (_isZeroAddress(gcaAndMinerPoolAddress)) _revert(IGlow.AddressNotSet.selector);
        if (msg.sender != gcaAndMinerPoolAddress) _revert(IGlow.CallerNotGCA.selector);
        uint256 timestampInStorage = gcaAndMinerPoolLastClaimedTimestamp;
        uint256 timestampToClaimFrom = timestampInStorage == 0 ? GENESIS_TIMESTAMP : timestampInStorage;
        uint256 secondsSinceLastClaim = block.timestamp - timestampToClaimFrom;
        uint256 amountToClaim = secondsSinceLastClaim * GCA_AND_MINER_POOL_INFLATION_PER_SECOND;
        if (amountToClaim == 0) return 0;
        gcaAndMinerPoolLastClaimedTimestamp = block.timestamp;
        _mint(gcaAndMinerPoolAddress, amountToClaim);
        return amountToClaim;
    }

    /**
     * @inheritdoc IGlow
     */
    function claimGLWFromVetoCouncil() external returns (uint256) {
        if (_isZeroAddress(vetoCouncilAddress)) _revert(IGlow.AddressNotSet.selector);
        if (msg.sender != vetoCouncilAddress) _revert(IGlow.CallerNotVetoCouncil.selector);
        uint256 timestampInStorage = vetoCouncilLastClaimedTimestamp;
        uint256 timestampToClaimFrom = timestampInStorage == 0 ? GENESIS_TIMESTAMP : timestampInStorage;
        uint256 secondsSinceLastClaim = block.timestamp - timestampToClaimFrom;
        uint256 amountToClaim = secondsSinceLastClaim * VETO_COUNCIL_INFLATION_PER_SECOND;
        if (amountToClaim == 0) return 0;
        vetoCouncilLastClaimedTimestamp = block.timestamp;
        _mint(vetoCouncilAddress, amountToClaim);
        return amountToClaim;
    }

    /**
     * @inheritdoc IGlow
     */
    function claimGLWFromGrantsTreasury() external returns (uint256) {
        if (_isZeroAddress(grantsTreasuryAddress)) _revert(IGlow.AddressNotSet.selector);
        if (msg.sender != grantsTreasuryAddress) _revert(IGlow.CallerNotGrantsTreasury.selector);
        uint256 timestampInStorage = grantsTreasuryLastClaimedTimestamp;
        uint256 timestampToClaimFrom = timestampInStorage == 0 ? GENESIS_TIMESTAMP : timestampInStorage;
        uint256 secondsSinceLastClaim = block.timestamp - timestampToClaimFrom;
        uint256 amountToClaim = secondsSinceLastClaim * GRANTS_TREASURY_INFLATION_PER_SECOND;
        if (amountToClaim == 0) return 0;
        grantsTreasuryLastClaimedTimestamp = block.timestamp;
        _mint(grantsTreasuryAddress, amountToClaim);
        return amountToClaim;
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

    //----------------------- ONE-TIME SETTERS -----------------------//

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

    //----------------------- PRIVATE FUNCTIONS ----------------------//

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

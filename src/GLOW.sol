// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

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

    //----------------------- IMMUTABLES -----------------------//

    /// @notice The timestamp of the genesis block
    // solhint-disable-next-line var-name-mixedcase
    uint256 public immutable GENESIS_TIMESTAMP;

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

    constructor() ERC20("Glow", "GLOW") {
        GENESIS_TIMESTAMP = block.timestamp;
    }

    /**
     * @inheritdoc IGlow
     */

    function stake(uint256 stakeAmount) external {
        if (stakeAmount == 0) _revert(IGlow.CannotStakeZeroTokens.selector);
        uint256 tail = _unstakedPositionTail[msg.sender];
        uint256 unstakedTotal;
        uint256 newTail = tail;

        for (uint256 i = tail; i < _unstakedPositions[msg.sender].length; ++i) {
            UnstakedPosition storage position = _unstakedPositions[msg.sender][i];
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
        }

        if (newTail != tail) {
            _unstakedPositionTail[msg.sender] = newTail;
        }
        unstakedTotal = _min(unstakedTotal, stakeAmount);
        uint256 amountToTransfer = stakeAmount - unstakedTotal;
        numStaked[msg.sender] += stakeAmount;
        if (amountToTransfer > 0) {
            _transfer(msg.sender, address(this), amountToTransfer);
        }
        emit IGlow.Stake(msg.sender, stakeAmount);
    }

    /**
     * @inheritdoc IGlow
     */
    function unstake(uint256 amount) external {
        uint256 numAccountStaked = numStaked[msg.sender];
        if (amount > numAccountStaked) {
            _revert(IGlow.UnstakeAmountExceedsStakedBalance.selector);
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

    /**
     * @inheritdoc IGlow
     */
    function unstakedPositionsOf(address account, uint256 start, uint256 end)
        external
        view
        returns (UnstakedPosition[] memory)
    {
        uint256 length = _unstakedPositions[account].length;
        if (start >= length) {
            return new UnstakedPosition[](0);
        }
        if (end > length) {
            end = length;
        }
        uint256 actualStart = _unstakedPositionTail[account] + start;
        unchecked {
            UnstakedPosition[] memory positions = new UnstakedPosition[](end - start);
            for (uint256 i = actualStart; i < end; ++i) {
                positions[i - start] = _unstakedPositions[account][i];
            }
            return positions;
        }
    }

    /**
     * @inheritdoc IGlow
     */
    function claimUnstakedTokens(uint256 amount) external {
        if (amount == 0) _revert(IGlow.CannotStakeZeroTokens.selector);
        uint256 tail = _unstakedPositionTail[msg.sender];
        uint256 claimableTotal;
        uint256 newTail = tail;

        for (uint256 i = tail; i < _unstakedPositions[msg.sender].length; ++i) {
            UnstakedPosition storage position = _unstakedPositions[msg.sender][i];
            if (position.cooldownEnd > block.timestamp) {
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
        @inheritdoc IGlow
    */
    function claimGLWFromGCAAndMinerPool() external {
        if(gcaAndMinerPoolAddress == address(0)) _revert(IGlow.AddressNotSet.selector);
        if(msg.sender != gcaAndMinerPoolAddress) _revert(IGlow.CallerNotGCA.selector);
        uint timestampInStorage = gcaAndMinerPoolLastClaimedTimestamp;
        uint timestampToClaimFrom = timestampInStorage == 0 ? GENESIS_TIMESTAMP : timestampInStorage;
        uint secondsSinceLastClaim = block.timestamp - timestampToClaimFrom;
        uint amountToClaim = secondsSinceLastClaim * GCA_AND_MINER_POOL_INFLATION_PER_SECOND;
        gcaAndMinerPoolLastClaimedTimestamp = block.timestamp;
        _mint(gcaAndMinerPoolAddress, amountToClaim);
    }

    /**
        @inheritdoc IGlow
    */
    function claimGLWFromVetoCouncil() external {
        if(vetoCouncilAddress == address(0)) _revert(IGlow.AddressNotSet.selector);
        if(msg.sender != vetoCouncilAddress) _revert(IGlow.CallerNotVetoCouncil.selector);
        uint timestampInStorage = vetoCouncilLastClaimedTimestamp;
        uint timestampToClaimFrom = timestampInStorage == 0 ? GENESIS_TIMESTAMP : timestampInStorage;
        uint secondsSinceLastClaim = block.timestamp - timestampToClaimFrom;
        uint amountToClaim = secondsSinceLastClaim * VETO_COUNCIL_INFLATION_PER_SECOND;
        vetoCouncilLastClaimedTimestamp = block.timestamp;
        _mint(vetoCouncilAddress, amountToClaim);
    }

    /**
        @inheritdoc IGlow
    */
    function claimGLWFromGrantsTreasury() external {
        if(grantsTreasuryAddress == address(0)) _revert(IGlow.AddressNotSet.selector);
        if(msg.sender != grantsTreasuryAddress) _revert(IGlow.CallerNotGrantsTreasury.selector);
        uint timestampInStorage = grantsTreasuryLastClaimedTimestamp;
        uint timestampToClaimFrom = timestampInStorage == 0 ? GENESIS_TIMESTAMP : timestampInStorage;
        uint secondsSinceLastClaim = block.timestamp - timestampToClaimFrom;
        uint amountToClaim = secondsSinceLastClaim * GRANTS_TREASURY_INFLATION_PER_SECOND;
        grantsTreasuryLastClaimedTimestamp = block.timestamp;
        _mint(grantsTreasuryAddress, amountToClaim);
    }

    /**
        @inheritdoc IGlow
    */
    function gcaInflationData() external view returns(
        uint256 ,
        uint256 totalAlreadyClaimed,
        uint256 totalToClaim) {
        if(gcaAndMinerPoolAddress == address(0)) _revert(IGlow.AddressNotSet.selector);
        uint timestampInStorage = gcaAndMinerPoolLastClaimedTimestamp;
        uint timestampToClaimFrom = timestampInStorage == 0 ? GENESIS_TIMESTAMP : timestampInStorage;
        uint secondsSinceLastClaim = block.timestamp - timestampToClaimFrom;
        totalToClaim = secondsSinceLastClaim * GCA_AND_MINER_POOL_INFLATION_PER_SECOND;
        totalAlreadyClaimed = timestampToClaimFrom - GENESIS_TIMESTAMP;
        return (timestampInStorage,totalAlreadyClaimed,totalToClaim);
    }

    /**
        @inheritdoc IGlow
    */
    function vetoCouncilInflationData() external view returns (
        uint256,
        uint256 totalAlreadyClaimed,
        uint256 totalToClaim) {
        if(vetoCouncilAddress == address(0)) _revert(IGlow.AddressNotSet.selector);
        uint timestampInStorage = vetoCouncilLastClaimedTimestamp;
        uint timestampToClaimFrom = timestampInStorage == 0 ? GENESIS_TIMESTAMP : timestampInStorage;
        uint secondsSinceLastClaim = block.timestamp - timestampToClaimFrom;
        totalToClaim = secondsSinceLastClaim * VETO_COUNCIL_INFLATION_PER_SECOND;
        totalAlreadyClaimed = timestampToClaimFrom - GENESIS_TIMESTAMP;
        return (timestampInStorage,totalAlreadyClaimed,totalToClaim);

    }

    /**
        @inheritdoc IGlow
    */
    function grantsTreasuryInflationData() external view returns (
        uint256,
        uint256 totalAlreadyClaimed,
        uint256 totalToClaim) {
        if(grantsTreasuryAddress == address(0)) _revert(IGlow.AddressNotSet.selector);
        uint timestampInStorage = grantsTreasuryLastClaimedTimestamp;
        uint timestampToClaimFrom = timestampInStorage == 0 ? GENESIS_TIMESTAMP : timestampInStorage;
        uint secondsSinceLastClaim = block.timestamp - timestampToClaimFrom;
        totalToClaim = secondsSinceLastClaim * GRANTS_TREASURY_INFLATION_PER_SECOND;
        totalAlreadyClaimed = timestampToClaimFrom - GENESIS_TIMESTAMP;
        return (timestampInStorage,totalAlreadyClaimed,totalToClaim);
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
        //Only need one check since all three addresses are set at the same time atomically
        if(gcaAndMinerPoolAddress != address(0)) _revert(IGlow.AddressAlreadySet.selector);
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
}

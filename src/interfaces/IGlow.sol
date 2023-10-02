// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGlow is IERC20 {
    error UnstakeAmountExceedsStakedBalance();
    error InsufficientClaimableBalance();
    error CannotStakeZeroTokens();
    error CannotUnstakeZeroTokens();
    error AddressAlreadySet();
    error AddressNotSet();
    error CallerNotGCA();
    error CallerNotVetoCouncil();
    error CallerNotGrantsTreasury();
    error UnstakingOnEmergencyCooldown();
    error ZeroAddressNotAllowed();
    error DuplicateAddressNotAllowed();
    error CannotClaimZeroTokens();

    /**
     * @notice Emitted when a user stakes GLOW
     * @param user The address of the user that is staking
     * @param amount The amount staked
     */
    event Stake(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user unstakes GLOW
     * @param user The address of the user that is unstaking
     * @param amount The amount unstaked
     */
    event Unstake(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user claims GLOW from there unstaked positions
     * @param user The address of the user that is claiming
     * @param amount The amount claimed
     */
    event ClaimUnstakedGLW(address indexed user, uint256 amount);

    /**
     * @notice represents an unstaked position
     * @param amount The amount of GLOW unstaked
     * @param cooldownEnd The timestamp when the user can reclaim the tokens
     */
    struct UnstakedPosition {
        uint192 amount;
        uint64 cooldownEnd;
    }

    /**
     * @notice The entry point for a user to stake glow.
     * @notice A user earns 1 ratify/reject vote per glw staked
     * @param amount The amount of GLOW to stake
     */
    function stake(uint256 amount) external;

    /**
     * @notice The entry point for a user to unstake glow.
     * @param amount The amount of GLOW to unstake
     */
    function unstake(uint256 amount) external;

    /**
     * @notice Returns the unstaked positions of a user
     * @param account The address of the user
     */
    function unstakedPositionsOf(address account) external view returns (UnstakedPosition[] memory);

    /**
     * @notice Returns the unstaked positions of a user
     * @param account The address of the user
     * @param start The start index of the positions to return
     * @param end The end index of the positions to return
     */
    function unstakedPositionsOf(address account, uint256 start, uint256 end)
        external
        view
        returns (UnstakedPosition[] memory);

    /**
     * @notice Entry point for users to claim unstaked tokens that are no longer on cooldown
     * @param amount The amount of tokens to claim
     * @dev emits a ```ClaimUnstakedGLW``` event
     */
    function claimUnstakedTokens(uint256 amount) external;

    /**
     * @notice Allows the GCA and Miner Pool Contract to claim GLW from inflation
     * @notice The GCA and Miner Pool Contract receives 185,00 * 1e18 tokens per week
     */
    function claimGLWFromGCAAndMinerPool() external returns (uint256);

    /**
     * @notice Allows the Veto Council to claim GLW from inflation
     * @notice The veto council receives 5,000 * 1e18 tokens per week
     */
    function claimGLWFromVetoCouncil() external returns (uint256);

    /**
     * @notice Allows the Grants Treasury to claim GLW from inflation
     * @notice The grants treasury receives 40,000 * 1e18 tokens per week
     */
    function claimGLWFromGrantsTreasury() external returns (uint256);

    /**
     * @return lastClaimTimestamp The last time the GCA and Miner Pool Contract claimed GLW
     * @return totalAlreadyClaimed The total amount of GLW already claimed by the GCA and Miner Pool Contract
     * @return totalToClaim The total amount of GLW available to claim by the GCA and Miner Pool Contract
     */
    function gcaInflationData()
        external
        view
        returns (uint256 lastClaimTimestamp, uint256 totalAlreadyClaimed, uint256 totalToClaim);

    /**
     * @return lastClaimTimestamp The last time the Veto Council claimed GLW
     * @return totalAlreadyClaimed The total amount of GLW already claimed by the Veto Council
     * @return totalToClaim The total amount of GLW available to claim by the Veto Council
     */
    function vetoCouncilInflationData()
        external
        view
        returns (uint256 lastClaimTimestamp, uint256 totalAlreadyClaimed, uint256 totalToClaim);

    /**
     * @return lastClaimTimestamp The last time the Grants Treasury claimed GLW
     * @return totalAlreadyClaimed The total amount of GLW already claimed by the Grants Treasury
     * @return totalToClaim The total amount of GLW available to claim by the Grants Treasury
     */
    function grantsTreasuryInflationData()
        external
        view
        returns (uint256 lastClaimTimestamp, uint256 totalAlreadyClaimed, uint256 totalToClaim);

    /**
     * @return the genesis timestamp
     */
    function GENESIS_TIMESTAMP() external view returns (uint256);

    /**
     * @notice the total amount of GLW currently staked by {account}
     * @return numStaked total amount of GLW currently staked by {account}
     * @param account the address of the account to get the staked balance of
     */
    function numStaked(address account) external view returns (uint256);
}

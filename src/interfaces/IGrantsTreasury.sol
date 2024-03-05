// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IGrantsTreasury {
    /* -------------------------------------------------------------------------- */
    /*                                   errors                                    */
    /* -------------------------------------------------------------------------- */
    error CallerNotGovernance();
    error AllocationCannotBeZero();

    /* -------------------------------------------------------------------------- */
    /*                                   events                                    */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Emitted when a grant is succesfully allocated
     *     @param recipient The address of the recipient
     *     @param amount The amount of GLOW allocated
     */
    event GrantFundsAllocated(address indexed recipient, uint256 amount);

    /**
     * @notice Emitted when a grant allocation fails due to insufficient balance
     *     @param recipient The address of the recipient
     *     @param amount The amount of GLOW allocated
     */
    event GrantFundsAllocationFailed(address indexed recipient, uint256 amount);

    /**
     * @notice Emitted when a grant is succesfully claimed
     * @param to The address of the recipient
     * @param amount The amount of GLOW claimed
     */
    event GrantFundsClaimed(address indexed to, uint256 amount);

    /**
     * @notice Emitted when the treasury is synced
     *     @param amount The amount of GLOW synced
     */
    event TreasurySynced(uint256 amount);

    /* -------------------------------------------------------------------------- */
    /*                                  state-changing                            */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice The entry point for the Governance contract to allocate grant funds
     * @param to The address of the recipient
     * @param amount The amount of GLOW to allocate
     * @dev emits a {GrantFundsAllocated} event on success
     * @dev emits a {GrantFundsAllocationFailed} event on failure
     * @return true on success and false on failure
     */
    function allocateGrantFunds(address to, uint256 amount) external returns (bool);

    /**
     *   @notice The entry point for a recipient to claim their grant funds
     *   @dev emits a {GrantFundsClaimed} event on success
     */
    function claimGrantReward() external;

    /**
     * @notice pulls any unclaimed GLW from the Glow contract
     */
    function claimGlowFromTreasury() external;

    /* -------------------------------------------------------------------------- */
    /*                                   view                                    */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice returns the total balance of GLW in the GrantsTreasury
     *     @return the total available balance that the Grants Treasury can allocate to new grants
     */
    function totalBalanceInGrantsTreasury() external view returns (uint256);
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

interface IGCA {
    error NotGCA();
    error CompensationPlanLengthMustBeGreaterThanZero();
    error InsufficientShares();
    error NoBalanceToPayout();

    /**
     * @return = true if the account is a gca , false otherwise
     */
    function isGCA(address account) external view returns (bool);

    /// @dev allows GCAs to submit a compensation plan
    function submitCompensationPlan(ICompensation[] calldata plans) external;

    /// @return - returns the compensation plan for a gca by unpacking the packed compensation plan
    function compensationPlan(address gca) external view returns (ICompensation[] memory);

    /// @return - returns all the gcas
    function allGcas() external view returns (address[] memory);

    /// @dev allows the contrac to pull glow from inflation
    function claimGlowFromInflation() external;

    /**
     * @param gca - the address of the gca to check
     * @return - returns the {GCAPayout} struct data for a gca
     */
    function gcaPayoutData(address gca) external view returns (GCAPayout memory);
    /**
     * @dev a struct to represent a compensation plan
     * @dev packed into a single uint256
     * @param shares - the amount of shares to be distributed
     * @param agent - the address of the gca agent to receive the shares
     */

    struct ICompensation {
        uint80 shares;
        address agent;
    }

    /**
     * @dev a struct to represent a gca payout
     * @param lastClaimedTimestamp - the last time the gca claimed their payout
     * @param totalSlashableBalance - the total slashable balance of the gca
     */
    struct GCAPayout {
        uint64 lastClaimedTimestamp;
        uint192 totalSlashableBalance;
    }

    /**
     * @dev Emitted when a gca submits a new compensation plan.
     * @param agent - the address of the gca agent proposing
     * @param plans - the compensation plans
     */
    event CompensationPlanSubmitted(address indexed agent, ICompensation[] plans);

    /**
     * @dev Emitted when a gca claims their payout
     * @param agent - the address of the gca agent claiming
     * @param amount - the amount of tokens claimed
     * @param totalSlashableBalance - the total slashable balance of the gca
     */
    event GCAPayoutClaimed(address indexed agent, uint256 amount, uint256 totalSlashableBalance);
}

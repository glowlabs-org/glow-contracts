// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IGlow} from "./interfaces/IGlow.sol";
import {IGrantsTreasury} from "./interfaces/IGrantsTreasury.sol";

contract GrantsTreasury is IGrantsTreasury {
    /// @notice glow token
    IGlow public immutable GLOW_TOKEN;

    /// @notice governance contract
    address public immutable GOVERNANCE;

    /// @notice timestamp of the genesis block of the glow token
    uint256 public immutable GENESIS_TIMESTAMP;

    /// @notice the balance of each recipient
    /// @dev this is a mapping of recipient => balance
    /// @dev if a user has a balance of 0, they are not owed any funds
    mapping(address => uint256) public recipientBalance;

    /// @notice the cumulative amount of funds allocated to recipients
    uint256 public cumulativeAllocated;

    /// @notice the cumulative amount of funds paid out to recipients
    uint256 public cumulativePaidOut;

    //************************************************************* */
    //*********************  CONSTRUCTOR    ********************** */
    //************************************************************* */
    /**
     * @notice GrantsTreasury constructor
     *     @param _glowToken The address of the Glow token
     *     @param _governance The address of the Governance contract
     */
    constructor(address _glowToken, address _governance) {
        GLOW_TOKEN = IGlow(_glowToken);
        GOVERNANCE = _governance;
        GENESIS_TIMESTAMP = GLOW_TOKEN.GENESIS_TIMESTAMP();
    }

    //************************************************************* */
    //*********************  EXTERNAL FUNCS    ********************** */
    //************************************************************* */

    /**
     * @inheritdoc IGrantsTreasury
     */
    function allocateGrantFunds(address to, uint256 amount) external returns (bool) {
        if (msg.sender != GOVERNANCE) _revert(IGrantsTreasury.CallerNotGovernance.selector);
        sync();
        uint256 balance = totalBalanceInGrantsTreasury();
        if (balance < amount) {
            emit IGrantsTreasury.GrantFundsAllocationFailed(to, amount);
            return false;
        }

        /// can't overflow because {amount} will never be greater than GLW's total supply
        recipientBalance[to] += amount;

        /// can't overflow because {amount} will never be greater than GLW's total supply
        /// and glow token's total supply will never be greater than 2^256
        cumulativeAllocated += amount;
        emit IGrantsTreasury.GrantFundsAllocated(to, amount);
        return true;
    }

    /**
     * @inheritdoc IGrantsTreasury
     */
    function claimGrantReward() external {
        uint256 allocation = recipientBalance[msg.sender];
        if (allocation == 0) _revert(IGrantsTreasury.AllocationCannotBeZero.selector);
        delete recipientBalance[msg.sender];
        cumulativePaidOut += allocation;
        GLOW_TOKEN.transfer(msg.sender, allocation);

        //Can't overflow because the amount a recipient will never be greater than the total supply of GLW
        emit IGrantsTreasury.GrantFundsClaimed(msg.sender, allocation);
    }

    /**
     * @inheritdoc IGrantsTreasury
     */
    function sync() public {
        uint256 amt = GLOW_TOKEN.claimGLWFromGrantsTreasury();
        emit IGrantsTreasury.TreasurySynced(amt);
    }

    //************************************************************* */
    //*********************  VIEW FUNCS    ********************** */
    //************************************************************* */
    /**
     * @inheritdoc IGrantsTreasury
     */
    function totalBalanceInGrantsTreasury() public view returns (uint256) {
        uint256 balance = GLOW_TOKEN.balanceOf(address(this));
        //TODO: Decide if this is too complicated for people
        /// @dev having two vars saves gas on sstores by almost always guaranteeing a hot sstore
        return balance + cumulativePaidOut - cumulativeAllocated;
    }

    //************************************************************* */
    //*********************  PRIVATE UTILS    ********************** */
    //************************************************************* */

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

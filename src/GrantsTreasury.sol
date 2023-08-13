// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IGlow} from "./interfaces/IGlow.sol";
import {IGrantsTreasury} from "./interfaces/IGrantsTreasury.sol";

contract GrantsTreasury is IGrantsTreasury {
    IGlow public immutable GLOW_TOKEN;
    address public immutable GOVERNANCE;
    uint256 public immutable GENESIS_TIMESTAMP;

    mapping(address => uint256) public recipientBalance;
    uint256 public cumulativeAllocated;
    uint256 public cumulativePaidOut;

    //-------------  CONSTRUCTOR --------------------//

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

        recipientBalance[to] += amount;
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
        GLOW_TOKEN.transfer(msg.sender, allocation);
        delete recipientBalance[msg.sender];
        cumulativePaidOut += allocation;
        emit IGrantsTreasury.GrantFundsClaimed(msg.sender, allocation);
    }

    /**
     * @inheritdoc IGrantsTreasury
     */
    function totalBalanceInGrantsTreasury() public view returns (uint256) {
        uint256 balance = GLOW_TOKEN.balanceOf(address(this));
        //TODO: Decide if this is too complicated for people
        /// @dev having two vars saves gas on sstores by almost always guaranteeing a hot sstore
        return balance + cumulativePaidOut - cumulativeAllocated;
    }

    /**
     * @inheritdoc IGrantsTreasury
     */
    function sync() public {
        uint256 amt = GLOW_TOKEN.claimGLWFromGrantsTreasury();
        emit IGrantsTreasury.TreasurySynced(amt);
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

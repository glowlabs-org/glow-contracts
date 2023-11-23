// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IGlow} from "@/interfaces/IGlow.sol";
/// @dev should be deployed by glow contract

/**
 * @title GlowUnlocker
 * @notice A contract for unlocking glow tokens
 *         - the contract takes in a list of addresses and amounts
 *         - and unlocks the glow tokens for those respective addresses and amounts over 6 years
 *            - The first year, no tokens are unlocked
 *            - Every year after, for 5 years, 20% of the tokens are unlocked
 */
contract GlowUnlocker2 {
    error ZeroAddressInConstructor();
    error NothingToClaim();
    error ReleasePeriodNotStarted();
    error InitializerAmountDoesNotMatchExpectedAmount();

    /**
     * @dev the expected amount of glow tokens to be unlocked
     */
    uint256 private constant EXPECTED_GLOW = 90_000_000 ether;
    /**
     * @dev the offset for the release period
     */
    uint256 private constant RELEASE_OFFSET = uint256(365 days); // 1 year
    /**
     * @dev the release duration for glow tokens
     */
    uint256 private constant RELEASE_DURATION = uint256(365 days) * 5; //5 years

    /**
     * @notice the amount of glow tokens each address unlocks over the course of the vesting period
     */
    mapping(address => uint256) public amountUnlockable;
    /**
     * @notice the last timestamp the user claimed unlockable glow tokens
     */
    mapping(address => uint256) public lastClaimedTimestamp;

    /**
     * @notice the glow token
     */
    IGlow public glow;

    /**
     * @notice the genesis timestamp of the glow protocol
     */
    uint256 public genesisTimestamp;

    /**
     * @notice Claims glow tokens {to}
     * @param to address to send glow tokens
     * @dev anyone can call this function
     *             - the idea is that users may not want to interact
     *             - directly with a contract, so they will trust a relay
     *             - to initiate the tx
     */
    function claim(address to) external {
        uint256 reward = nextReward(to);
        if (reward == 0) {
            revert NothingToClaim();
        }
        lastClaimedTimestamp[to] = block.timestamp;
        glow.transfer(to, reward);
    }

    /**
     * @notice Initializes the contract
     * @dev can only be called once
     * @dev called directly in the GlowUnlockerFactory
     */
    function initialize(address _glow, address[] memory _addresses, uint256[] memory _amounts) external {
        require(address(glow) == address(0), "Already initialized");
        uint256 totalGlow;
        glow = IGlow(_glow);
        genesisTimestamp = glow.GENESIS_TIMESTAMP();
        unchecked {
            for (uint256 i; i < _addresses.length; ++i) {
                if (_addresses[i] == address(0)) {
                    revert ZeroAddressInConstructor();
                }
                totalGlow += _amounts[i];
                amountUnlockable[_addresses[i]] = _amounts[i];
            }
        }
        if (totalGlow != EXPECTED_GLOW) {
            revert InitializerAmountDoesNotMatchExpectedAmount();
        }
    }

    /**
     * @notice Returns the next reward for a given address
     * @param from the address to get the next reward for
     * @return reward - next reward for a given address
     */
    function nextReward(address from) public view returns (uint256) {
        uint256 _genesisTimestamp = genesisTimestamp;
        uint256 releaseStartTimestamp = _genesisTimestamp + RELEASE_OFFSET;
        uint256 amount = amountUnlockable[from];
        if (block.timestamp < releaseStartTimestamp) {
            revert ReleasePeriodNotStarted();
        }
        uint256 lastClaimedTimestampUser = lastClaimedTimestamp[from];
        if (lastClaimedTimestampUser == 0) {
            lastClaimedTimestampUser = releaseStartTimestamp;
        }

        uint256 maxClaimableTimestamp = releaseStartTimestamp + RELEASE_DURATION;
        if (lastClaimedTimestampUser > maxClaimableTimestamp) {
            return 0;
        }

        uint256 timestampToCompare = min(block.timestamp, maxClaimableTimestamp);
        uint256 timeSinceLastClaim = timestampToCompare - lastClaimedTimestampUser;
        uint256 amountToClaim = (timeSinceLastClaim * amount) / RELEASE_DURATION;
        return amountToClaim;
    }

    /// @dev finds the minimum of two numbers
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? b : a;
    }
}

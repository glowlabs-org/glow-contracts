// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IGlow} from "@/interfaces/IGlow.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
/// @dev should be deployed by glow contract

contract GlowUnlocker is Ownable {
    error ZeroAddressInConstructor();
    error NothingToClaim();

    uint256 private constant VESTING_PERIOD = uint256(365 days) * 6; //6 years
    mapping(address => uint256) public amountOwed;
    mapping(address => uint256) public lastClaimedTimestamp;
    IGlow public glow;
    uint256 public genesisTimestamp;

    constructor(address[] memory _addresses, uint256[] memory _amounts) Ownable(tx.origin) {
        unchecked {
            for (uint256 i; i < _addresses.length; ++i) {
                if (_addresses[i] == address(0)) {
                    revert ZeroAddressInConstructor();
                }
                amountOwed[_addresses[i]] = _amounts[i];
            }
        }
    }

    /**
     * @notice Claims glow tokens {to}
     * @param to address to send glow tokens
     * @dev anyone can call this function
     *             - the idea is that users may not want to interact
     *             - directly with a contract, so they will trust a relay
     *             - to initiate the tx
     */
    function claim(address to) external {
        uint256 reward = nextReward(msg.sender);
        if (reward == 0) {
            revert NothingToClaim();
        }
        lastClaimedTimestamp[to] = block.timestamp;
        glow.transfer(to, reward);
    }

    /**
     * @notice Initializes the contract
     * @dev can only be called once
     */
    function initialize(address _glow) external {
        require(address(glow) == address(0), "Already initialized");
        glow = IGlow(_glow);
        genesisTimestamp = glow.GENESIS_TIMESTAMP();
        _transferOwnership(address(0));
    }

    function nextReward(address from) public view returns (uint256) {
        uint256 amount = amountOwed[from];
        uint256 lastClaimedTimestampUser = lastClaimedTimestamp[from];
        if (lastClaimedTimestampUser == 0) {
            lastClaimedTimestampUser = genesisTimestamp;
        }
        uint256 timestampToCompare = min(block.timestamp, genesisTimestamp + VESTING_PERIOD);
        uint256 timeSinceLastClaim = timestampToCompare - lastClaimedTimestampUser;
        uint256 amountToClaim = (timeSinceLastClaim * amount) / VESTING_PERIOD;
        return amountToClaim;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? b : a;
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract MinerPool {
    mapping(bytes32 => MinerInfo) public glwMinerPool;
    mapping(bytes32 => MinerInfo) public grcMinerPool;

    struct MinerInfo {
        uint128 amountMined;
        uint128 grcDeposited;
        address payoutAddress;
    }

    /// @dev allows the creation of a new farm by depositing GRC
    /// @dev this farm will mine in the GLW Pool
    /// @dev should revert if the farm already exists
    /// @dev should increment the amount of GRC in GRC Pool
    function joinGRCMinerPool(bytes32 farmId, uint256 grcAmount, address payoutAddress) external {}

    /// @dev allows the creation of a new farm by depositing GRC
    /// @dev this farm will mine in the GRC Pool
    /// @dev should revert if the farm already exists
    /// @dev should increment the amount of GRC in GLW Pool
    function joinGLWMinerPool(bytes32 farmId, uint256 glwAmount, address payoutAddress) external {}

    /// @dev allows a farm to claim their rewards
    /// @dev should revert if the farm does not exist
    /// @dev should revert if the farm has no rewards to claim
    /// @dev should payout to the payoutAddress
    /// @dev should decrement the amount of GRC in the GRC Miner Rewards Pool
    function claimGRCRewards(bytes32 farmId) external {}

    /// @dev allows a farm to claim their rewards
    /// @dev should revert if the farm does not exist
    /// @dev should revert if the farm has no rewards to claim
    /// @dev should payout to the payoutAddress
    function claimGLWRewards(bytes32 farmId) external {}

    /// @dev should be called if not enough GLW in order to pay out rewards
    function _claimGLWFromInflation() internal {}

    /// @dev only callable by the GCA contract
    function updateMinerAmountMined(uint256 amountMined) external {}

    /// @dev only callable by the Governance contract.
    /// @dev it will create a fair auction between the old and new GCA tokens
    function createGRCAuction(address oldGCAToken, address newGCAToken) external {}

    /// @dev should return the total amount of GRC in the GLW GRC Pool
    function _totalGRCInGLWPool() public view returns (uint256) {
        return 0;
    }
    /// @dev should return the total amount of GRC in the GRC GRC Pool

    function totalGRCInGRCPool() external view returns (uint256) {
        return 0;
    }

    /// @param farmId the farmId to check
    /// @dev should return the next reward payable to a GLW Miner
    function nextRewardGLWMiner(bytes32 farmId) public view returns (uint256) {
        return 0;
    }

    /// @param farmId the farmId to check
    /// @dev should return the next reward payable to a GRC Miner
    function nextRewardGRCMiner(bytes32 farmId) public view returns (uint256) {
        return 0;
    }
}

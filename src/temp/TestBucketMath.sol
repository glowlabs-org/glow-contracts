// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract TestBucketMath {
    mapping(uint256 => uint256) public totalDeposit;
    mapping(uint256 => uint256) public totalToDeduce;
    uint256 public lastUpdatedWeek;
    uint256 private immutable startTimestamp;
    uint256 public totalDeposited;
    uint256 public constant BUCKET_LENGTH = 1 weeks;
    uint256 public constant BUCKET_VESTING_SHIFT = 26;
    uint256 public constant VESTING_WEEK_LENGTH = 52;

    constructor() {
        startTimestamp = block.timestamp;
    }

    // function deposit()
    function getDepositChangeForBucket(uint256 bucket) internal view returns (uint256) {
        return totalToDeduce[bucket];
    }

    function deposit(uint256 amount) external {
        uint256 _currentWeek = getCurrentBucket();
        uint256 _lastUpdatedBucket = lastUpdatedWeek;

        if (_lastUpdatedBucket == _currentWeek) {
            totalDeposit[_currentWeek] += amount;
            totalToDeduce[_currentWeek + VESTING_WEEK_LENGTH + BUCKET_VESTING_SHIFT] += amount;
        }

        if (_lastUpdatedBucket != _currentWeek) {
            while (true) {
                uint256 _lastUpdatedBucketValue = totalDeposit[_lastUpdatedBucket];
                if (_lastUpdatedBucketValue != 0 || _lastUpdatedBucket == 0) {
                    totalDeposit[_currentWeek] =
                        amount + _lastUpdatedBucketValue - getDepositChangeForBucket(_currentWeek);
                    totalToDeduce[_currentWeek + VESTING_WEEK_LENGTH + BUCKET_VESTING_SHIFT] = amount;
                    break;
                }
                --_lastUpdatedBucket;
            }
        }
        lastUpdatedWeek = _currentWeek;
    }

    function getBucketValue(uint256 bucketId) public view returns (uint256) {
        if (bucketId >= getCurrentBucket() + BUCKET_VESTING_SHIFT) revert("Finalization Not Done");
        if (bucketId < BUCKET_VESTING_SHIFT) return 0;
        uint256 cachedBucketId = bucketId;
        uint256 _totalDepositForBucket = totalDeposit[bucketId - BUCKET_VESTING_SHIFT];
        uint256 _totalToDeduceForBucket = totalToDeduce[bucketId];
        while (true) {
            if (bucketId == 0) return 0;
            if (cachedBucketId - bucketId >= VESTING_WEEK_LENGTH) return 0;
            if (_totalDepositForBucket != 0) {
                return (_totalDepositForBucket - _totalToDeduceForBucket) / VESTING_WEEK_LENGTH;
            }
            --bucketId;
            _totalDepositForBucket = totalDeposit[bucketId - BUCKET_VESTING_SHIFT];
            _totalToDeduceForBucket += totalToDeduce[bucketId];
        }
        revert("error");
    }

    function getCurrentBucket() public view returns (uint256) {
        return (block.timestamp - startTimestamp) / BUCKET_LENGTH;
    }
}

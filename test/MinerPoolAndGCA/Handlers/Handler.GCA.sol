// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdCheats.sol";
import "forge-std/console.sol";
import {MockGCA} from "@/MinerPoolAndGCA/mock/MockGCA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGCA} from "@/interfaces/IGCA.sol";

contract Handler is Test {
    MockGCA public immutable gca;
    uint256 public immutable GENESIS_TIMESTAMP;
    uint256 private immutable _ONE_WEEK = 604800;

    uint256[] private _ghost_bucketIds;

    mapping(uint256 => bool) private _insideIssueWeeklyReport;

    mapping(uint256 => uint256) public bucketIdToSlashNonce;

    mapping(uint256 => bool) public initOnCurrentWeek;
    mapping(uint256 => bool) public initNotOnCurrentWeek;

    constructor(address _gca) public {
        gca = MockGCA(_gca);
        GENESIS_TIMESTAMP = gca.GENESIS_TIMESTAMP();
    }

    function incrementSlashNonce() public {
        gca.incrementSlashNonce();
    }

    function issueWeeklyReportCurrentBucket(
        uint256 totalNewGCC,
        uint256 totalGlwRewardsWeight,
        uint256 totalGRCRewardsWeight,
        bytes32 root,
        uint256 timeToWarp
    ) external {
        warp(timeToWarp);
        addGCA(msg.sender);
        uint256 bucketId = (block.timestamp - GENESIS_TIMESTAMP) / _ONE_WEEK;

        /**
         * This function will always issue a report for the current week
         *         If the bucket was already initialized, we don't initialize it again
         */
        bool alreadyInit = gca.bucket(bucketId).finalizationTimestamp != 0;
        if (!alreadyInit) {
            initOnCurrentWeek[bucketId] = true;
            bucketIdToSlashNonce[bucketId] = gca.slashNonce();
        }
        _pushIfNotInside(bucketId);
        gca.issueWeeklyReport(bucketId, totalNewGCC, totalGlwRewardsWeight, totalGRCRewardsWeight, root);
    }

    function warp(uint256 timeToWarp) public {
        vm.warp(block.timestamp + (timeToWarp % _ONE_WEEK) * 10);
    }

    function issueWeeklyReport(
        uint256 bucketId,
        uint256 totalNewGCC,
        uint256 totalGlwRewardsWeight,
        uint256 totalGRCRewardsWeight,
        bytes32 root,
        uint256 timeToWarp
    ) external {
        addGCA(msg.sender);
        warp(timeToWarp);

        /**
         * There's a chance that we end up in the current week from the fuzzer,
         *         so if we are, we need to make sure
         *         1. if the bucket is already initialized, we don't initialize it again
         *         2. if the bucket is not initialized, we initialize it in the proper mapping
         *         3. initOnCurrentWeek[bucketId] is set to true if the bucket is not initialized and we are in the current week
         *         4. initNotOnCurrentWeek[bucketId] is set to true if the bucket is not initialized and we are not in the current week
         */
        bool isCurrentWeek = (block.timestamp - GENESIS_TIMESTAMP) / _ONE_WEEK == bucketId;
        if (isCurrentWeek) {
            bool alreadyInit = gca.bucket(bucketId).finalizationTimestamp != 0;
            if (!alreadyInit) {
                initOnCurrentWeek[bucketId] = true;
                bucketIdToSlashNonce[bucketId] = gca.slashNonce();
            }
        } else {
            if (!initOnCurrentWeek[bucketId]) {
                initNotOnCurrentWeek[bucketId] = true;
            }
        }

        _pushIfNotInside(bucketId);
        gca.issueWeeklyReport(bucketId, totalNewGCC, totalGlwRewardsWeight, totalGRCRewardsWeight, root);
    }

    function addGCA(address newGCA) public {
        address[] memory allGCAs = gca.allGcas();
        address[] memory temp = new address[](allGCAs.length+1);
        for (uint256 i; i < allGCAs.length; i++) {
            temp[i] = allGCAs[i];
            if (allGCAs[i] == newGCA) {
                return;
            }
        }
        temp[allGCAs.length] = newGCA;
        gca.setGCAs(temp);
    }

    function ghost_bucketIds() public view returns (uint256[] memory) {
        return _ghost_bucketIds;
    }

    function _pushIfNotInside(uint256 bucketId) private {
        if (!_insideIssueWeeklyReport[bucketId]) {
            _ghost_bucketIds.push(bucketId);
            _insideIssueWeeklyReport[bucketId] = true;
        }
    }
}

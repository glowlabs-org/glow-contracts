// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

error NotAnAgent();
error AlreadyAnAgent();
error TooFewAgents();
error TooManyAgents();

struct CompensationI {
    uint80 shares;
    address agent;
}

struct Helper {
    uint96 lastRewardTimestamp;
    uint96 shares;
    bool isGCA;
}

contract GCAPayoutAlgo2 {
    mapping(address => Helper) private _helpers;
    mapping(address => uint256) public balance; //mock GLW
    mapping(address => CompensationI[]) public proposedCompensationPlans;
    uint256 public totalShares;
    uint256 constant SHARES_REQUIRED_ON_SUBMISSION = 100_000;
    uint256 public rewardsPerSecondForAll = 1 ether;
    address[] public agents;

    /// @dev not yet optimized -- this is a PoC
    function submitCompensationPlan(CompensationI[] calldata compensationPlan) public {
        //we need to checkpoint.
        if (!_helpers[msg.sender].isGCA) revert NotAnAgent();
        {
            for (uint256 i; i < agents.length; ++i) {
                if (nextReward(agents[i]) > 0) claimRewards(agents[i]);
            }
        }
        CompensationI[] storage oldCompensationPlan = proposedCompensationPlans[msg.sender];
        uint256 len = oldCompensationPlan.length;
        uint256 totalSharesToSubtract = len > 0 ? SHARES_REQUIRED_ON_SUBMISSION : 0;
        for (uint256 i; i < len; ++i) {
            //If not GCA, it's been deleted
            if (_helpers[oldCompensationPlan[i].agent].isGCA) {
                _helpers[oldCompensationPlan[i].agent].shares -= oldCompensationPlan[i].shares;
            }
        }
        assembly {
            let slot := oldCompensationPlan.slot
            //clear the array by overriding the length to 0
            sstore(slot, 0)
        }
        uint256 totalSharesSubmitted;
        for (uint256 i; i < compensationPlan.length; ++i) {
            if (!_helpers[compensationPlan[i].agent].isGCA) revert NotAnAgent();
            totalSharesSubmitted += compensationPlan[i].shares;
            if (_helpers[compensationPlan[i].agent].lastRewardTimestamp == 0) {
                _helpers[compensationPlan[i].agent].lastRewardTimestamp = uint96(block.timestamp);
            }
            _helpers[compensationPlan[i].agent].shares += compensationPlan[i].shares;
            proposedCompensationPlans[msg.sender].push(compensationPlan[i]);
        }
        require(totalSharesSubmitted == SHARES_REQUIRED_ON_SUBMISSION, "not 10,000");
        totalShares += totalSharesSubmitted - totalSharesToSubtract;
    }

    function removeGCA(address gca) external {
        totalShares -= _helpers[gca].shares;
        CompensationI[] storage oldCompensationPlan = proposedCompensationPlans[gca];
        uint256 len = oldCompensationPlan.length;
        for (uint256 i; i < len; ++i) {
            if (oldCompensationPlan[i].agent != gca) {
                _helpers[oldCompensationPlan[i].agent].shares -= oldCompensationPlan[i].shares;
            }
        }
        assembly {
            let slot := oldCompensationPlan.slot
            //clear the array by overriding the length to 0
            sstore(slot, 0)
        }
        uint256 oldLength = agents.length;
        for (uint256 i; i < oldLength; ++i) {
            if (agents[i] == gca) {
                agents[i] = agents[agents.length - 1];
                agents.pop();
            } else {
                //Need to handle edge case where there is only one agent
                _helpers[agents[i]].shares *= uint96(oldLength / (oldLength - 1 == 0 ? 1 : oldLength - 1));
            }
        }

        delete _helpers[gca];
    }

    function addGCA(address gca) external {
        _helpers[gca].isGCA = true;
    }

    function claimRewards() public {
        uint256 reward = nextReward(msg.sender);
        _helpers[msg.sender].lastRewardTimestamp = uint96(block.timestamp);
        balance[msg.sender] += reward;
    }

    function claimRewards(address gca) internal {
        uint256 reward = nextReward(gca);
        _helpers[gca].lastRewardTimestamp = uint96(block.timestamp);
        balance[gca] += reward;
    }

    function nextReward(address gca) public view returns (uint256) {
        uint256 _totalShares = totalShares;
        if (_totalShares == 0) return 0;
        Helper storage helper = _helpers[gca];
        if (!helper.isGCA) revert NotAnAgent();
        return (block.timestamp - helper.lastRewardTimestamp) * rewardsPerSecondForAll * helper.shares / _totalShares;
    }

    function nextRewardMockTimestamp(uint256 mockTimestamp, address gca) external view returns (uint256) {
        Helper storage helper = _helpers[gca];
        if (!helper.isGCA) revert NotAnAgent();
        require(mockTimestamp >= helper.lastRewardTimestamp, "mockTimestamp < lastRewardTimestamp");
        return (mockTimestamp - helper.lastRewardTimestamp) * rewardsPerSecondForAll * helper.shares / totalShares;
    }

    /// TODO: Fix this, it's not final or working.  Implementing rebalancing algorithm
    function editSeats(address[] calldata oldAccounts, address[] calldata newAccounts) external {
        for (uint256 i; i < oldAccounts.length; ++i) {
            CompensationI[] storage oldCompensationPlan = proposedCompensationPlans[oldAccounts[i]];
            if (oldCompensationPlan.length > 0) totalShares -= SHARES_REQUIRED_ON_SUBMISSION;
            assembly {
                let slot := oldCompensationPlan.slot
                //clear the array by overriding the length to 0
                sstore(slot, 0)
            }

            delete _helpers[oldAccounts[i]];
        }
        for (uint256 i; i < newAccounts.length; ++i) {
            _helpers[newAccounts[i]].isGCA = true;
        }
    }

    function helpers(address gca) external view returns (Helper memory) {
        return _helpers[gca];
    }
}

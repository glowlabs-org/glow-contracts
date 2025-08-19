// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Call} from "./Structs.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICounterfactualHolderFactory} from "./ICounterfactualHolderFactory.sol";

contract CounterfactualHolder {
    using SafeERC20 for IERC20;

    error ExecutionFailed(uint256 index, address target, bytes data);

    constructor(IERC20 _token) {
        ICounterfactualHolderFactory factory = ICounterfactualHolderFactory(msg.sender);
        Call[] memory _calls = factory.getTransientCalls();
        address nextHolder = factory.getTransientNextHolder();
        _executeCalls(_calls);
        uint256 leftoverBalance = _token.balanceOf(address(this));
        if (leftoverBalance > 0) {
            _token.safeTransfer(nextHolder, leftoverBalance);
        }
    }

    function _executeCalls(Call[] memory _calls) internal {
        uint256 length = _calls.length;
        for (uint256 i; i < length; ++i) {
            (bool success,) = _calls[i].target.call(_calls[i].data);
            if (!success) {
                revert ExecutionFailed(i, _calls[i].target, _calls[i].data);
            }
        }
    }
}

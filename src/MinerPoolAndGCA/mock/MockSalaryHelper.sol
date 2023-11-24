// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {GCASalaryHelper} from "../GCASalaryHelper.sol";

contract MockSalaryHelper is GCASalaryHelper {
    constructor(address[] memory _startingAgents) GCASalaryHelper(_startingAgents) {}

    function genesisTimestampWithin() public view returns (uint256) {
        return _genesisTimestamp();
    }

    function domainSeperatorV4Main() public view returns (bytes32) {
        return domainSeperatorV4Main();
    }

    function _domainSeperatorV4Main() internal view override returns (bytes32) {
        return domainSeperatorV4Main();
    }

    function claimGlowFromInflation() external {
        _claimGlowFromInflation();
    }

    function transferGlow(address to, uint256 amount) external {
        _transferGlow(to, amount);
    }

    function _claimGlowFromInflation() internal override {
        revert();
    }

    //--unused here

    function _genesisTimestamp() internal view override returns (uint256) {
        revert();
    }

    function _currentWeek() internal view override returns (uint256) {
        revert();
    }

    function _transferGlow(address to, uint256 amount) internal override {
        revert();
    }
}

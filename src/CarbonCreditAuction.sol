// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {ICarbonCreditAuction} from "@/interfaces/ICarbonCreditAuction.sol";

//TEMP!
contract CarbonCreditAuction is ICarbonCreditAuction {
    /// @inheritdoc ICarbonCreditAuction
    function receiveGCC(uint256 amount) external override {
        return;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ITokenDelegateFactory} from "./ITokenDelegateFactory.sol";

contract TokenDelegateExecutor {
    constructor() {
        ITokenDelegateFactory factory = ITokenDelegateFactory(msg.sender);
        address beam = factory.getTransientBeam();
        bytes memory data = factory.getTransientBeamData();

        (bool success, bytes memory ret) = beam.delegatecall(data);
        if (!success) {
            assembly {
                revert(add(ret, 0x20), mload(ret))
            }
        }
    }
}

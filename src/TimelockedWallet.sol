// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

error CannotWithdrawBeforeUnlockTimestamp();
error SenderNotReceiver();

contract TimelockedWallet is Initializable {
    address private constant PAYOUT_CONTRACT = address(10);

    address public receiver;
    uint256 public amount;
    uint256 public unlockTimestamp;
    //   /// @custom:oz-upgrades-unsafe-allow constructor
    //   constructor() {
    //     _disableInitializers();
    // }

    function initialize(address _receiver, uint256 _amount, uint256 _unlockTimestamp) public initializer {
        receiver = _receiver;
        amount = _amount;
        unlockTimestamp = _unlockTimestamp;
    }

    function withdraw() public {
        if (block.timestamp < unlockTimestamp) _revert(CannotWithdrawBeforeUnlockTimestamp.selector);
        IERC20 token = IERC20(PAYOUT_CONTRACT);
        token.transfer(receiver, amount);
    }

    function _revert(bytes4 code) internal pure {
        assembly {
            mstore(0x0, code)
            revert(0x0, 0x4)
        }
    }
}

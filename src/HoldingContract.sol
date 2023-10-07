// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IVetoCouncil} from "@/interfaces/IVetoCouncil.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract HoldingContract {
    error OnlyMinerPoolCanAddHoldings();

    address public immutable MINER_POOL;
    IVetoCouncil public immutable VETO_COUNCIL;

    uint256 private constant DEFAULT_DELAY = uint256(7 days);
    uint256 private constant VETO_HOLDING_DELAY = uint256(90 days);

    // mapping(address =>

    mapping(address => mapping(address => Holding[])) private _holdings;

    struct Holding {
        uint192 amount;
        uint64 timestamp;
    }

    constructor(address _minerPool, address _vetoCouncil) {
        MINER_POOL = _minerPool;
        VETO_COUNCIL = IVetoCouncil(_vetoCouncil);
    }

    function addHolding(address user, address token, uint192 amount) external {
        if (msg.sender != MINER_POOL) {
            revert OnlyMinerPoolCanAddHoldings();
        }
        _holdings[user][token].push(Holding(amount, uint64(block.timestamp + DEFAULT_DELAY)));
    }

    //todo: add claim holding

    function holdings(address user, address token) external view returns (Holding[] memory) {
        return _holdings[user][token];
    }

    function _revert(bytes4 selector) internal pure {
        assembly {
            mstore(0, selector)
            revert(0, 4)
        }
    }
}

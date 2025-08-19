// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {CounterfactualHolder} from "./CounterfactualHolder.sol";
import {Call} from "./Structs.sol";
import {TransientBytes} from "./utils/TransientBytes/TransientBytes.sol";
import {ICounterfactualHolderFactory} from "./ICounterfactualHolderFactory.sol";
import {TransientSlot} from "./utils/TransientBytes/TransientSlot.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract CounterfactualHolderFactory is ICounterfactualHolderFactory, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using TransientBytes for *;
    using TransientSlot for *;

    event TransferToCFH(
        address indexed from, address indexed toUser, address indexed token, address cfh, uint256 amount
    );

    event Execute(address indexed user, address indexed cfh, address indexed token, Call[] calls);

    struct UserTokenData {
        uint256 nextSalt;
    }

    mapping(address user => mapping(address token => UserTokenData)) userTokenData;

    function transferToCFH(address user, address token, uint256 amount) external nonReentrant {
        UserTokenData storage d = userTokenData[user][token];
        address currentHolder = _predictCFH(token, deriveUserNonce(user, token, d.nextSalt));
        IERC20(token).safeTransferFrom(msg.sender, currentHolder, amount);
        emit TransferToCFH(msg.sender, user, token, currentHolder, amount);
    }

    function execute(address token, Call[] memory calls) external nonReentrant {
        bytes32 baseCallsSlot = deriveCallsBaseSlot();
        bytes memory dataCalls = abi.encode(calls);
        baseCallsSlot.tstoreBytes(dataCalls);

        UserTokenData storage d = userTokenData[msg.sender][token];

        uint256 nextSalt = d.nextSalt;
        address nextHolder = _predictCFH(token, deriveUserNonce(msg.sender, token, nextSalt + 1));
        bytes32 baseNextHolderSlot = deriveNextHolderBaseSlot();
        baseNextHolderSlot.asAddress().tstore(nextHolder);

        address cfh = address(new CounterfactualHolder{salt: deriveUserNonce(msg.sender, token, nextSalt)}(IERC20(token)));
        d.nextSalt = nextSalt + 1;

        emit Execute(msg.sender, cfh, token, calls);
    }

    function getCurrentCFH(address user, address token) external view returns (address) {
        UserTokenData storage d = userTokenData[user][token];
        return _predictCFH(token, deriveUserNonce(user, token, d.nextSalt));
    }

    function deriveUserNonce(address user, address token, uint256 nonce) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(user, token, nonce, address(this)));
    }

    function getTransientCalls() external view returns (Call[] memory) {
        bytes32 baseCallsSlot = deriveCallsBaseSlot();
        bytes memory dataCalls = baseCallsSlot.tloadBytes();
        return abi.decode(dataCalls, (Call[]));
    }

    function getTransientNextHolder() external view returns (address) {
        bytes32 baseNextHolderSlot = deriveNextHolderBaseSlot();
        return baseNextHolderSlot.asAddress().tload();
    }

    function deriveCallsBaseSlot() internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("CALLS"));
    }

    function deriveNextHolderBaseSlot() internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("NEXT_HOLDER"));
    }

    /// @dev Predict the create2
    function _predictCFH(address token, bytes32 salt) internal view returns (address currentHolder) {
        bytes32 initCodeHash = keccak256(abi.encodePacked(type(CounterfactualHolder).creationCode, abi.encode(token)));
        // EIP-1014: keccak256(0xff ++ deployer ++ salt ++ keccak256(init_code))[12:]
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash));

        currentHolder = address(uint160(uint256(hash)));
    }
}

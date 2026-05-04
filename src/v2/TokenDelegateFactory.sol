// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITokenDelegateFactory} from "./ITokenDelegateFactory.sol";
import {TokenDelegateExecutor} from "./TokenDelegateExecutor.sol";
import {TransientBytes} from "./utils/TransientBytes/TransientBytes.sol";
import {TransientSlot} from "./utils/TransientBytes/TransientSlot.sol";

/// @notice Funds a deterministic CREATE2 wallet with a basket of ERC20s, then
/// has that wallet `delegatecall` an arbitrary "beam" contract — Sky-style.
/// The wallet's address depends only on `(factory, salt)`, so callers can
/// pre-compute it and have other contracts (e.g. a `CounterfactualHolder`)
/// route tokens to it within the same transaction.
contract TokenDelegateFactory is ITokenDelegateFactory {
    using SafeERC20 for IERC20;
    using TransientBytes for *;
    using TransientSlot for *;

    error LengthMismatch();
    error PredictedMismatch(address predicted, address deployed);

    event Execute(
        address indexed caller,
        address indexed executor,
        address indexed beam,
        uint256 salt,
        address[] tokens,
        uint256[] amounts,
        bytes beamData
    );

    uint256 public nextSalt;

    function predictAddress(uint256 salt) public view returns (address) {
        bytes32 initCodeHash = keccak256(type(TokenDelegateExecutor).creationCode);
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), bytes32(salt), initCodeHash))))
        );
    }

    function exec(address[] calldata tokens, uint256[] calldata amounts, address beam, bytes calldata beamData)
        external
        returns (address executor)
    {
        if (tokens.length != amounts.length) revert LengthMismatch();

        uint256 salt = nextSalt++;
        address predicted = predictAddress(salt);

        for (uint256 i; i < tokens.length; ++i) {
            IERC20(tokens[i]).safeTransferFrom(msg.sender, predicted, amounts[i]);
        }

        deriveBeamSlot().asAddress().tstore(beam);
        deriveBeamDataSlot().tstoreBytes(beamData);

        executor = address(new TokenDelegateExecutor{salt: bytes32(salt)}());
        if (executor != predicted) revert PredictedMismatch(predicted, executor);

        deriveBeamSlot().asAddress().tstore(address(0));
        deriveBeamDataSlot().tclear();

        emit Execute(msg.sender, executor, beam, salt, tokens, amounts, beamData);
    }

    function getTransientBeam() external view returns (address) {
        return deriveBeamSlot().asAddress().tload();
    }

    function getTransientBeamData() external view returns (bytes memory) {
        return deriveBeamDataSlot().tloadBytes();
    }

    function deriveBeamSlot() internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("TokenDelegateFactory.BEAM"));
    }

    function deriveBeamDataSlot() internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("TokenDelegateFactory.BEAM_DATA"));
    }
}

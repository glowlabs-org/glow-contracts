// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdCheats.sol";
import "forge-std/console.sol";
import {HalfLife} from "@/libraries/HalfLife.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract DivergenceHandler is Test {
    mapping(uint256 => uint128) public amountFromSolidity;
    mapping(uint256 => uint128) public amountFromRust;
    uint256 public iterations;

    function runSims(uint64 initialAmount, uint32 secondsElapsed) external {
        string[] memory inputs = new string[](3);
        //can be max u64
        inputs[0] = "./test/Governance/ffi/half_life";
        inputs[1] = Strings.toString(initialAmount);
        inputs[2] = Strings.toString(secondsElapsed);

        bytes memory res = vm.ffi(inputs);
        uint256 resi = abi.decode(res, (uint256));

        uint256 halfLifeLibRes = HalfLife.calculateHalfLifeValue(initialAmount, secondsElapsed);

        amountFromSolidity[iterations] = uint128(halfLifeLibRes);
        amountFromRust[iterations] = uint128(resi);

        ++iterations;
    }
}

// SPDX-License-Identifier: MIT
import {GCC} from "../../src/GCC.sol";
import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdCheats.sol";
import "forge-std/console.sol";
import {IGCC} from "../../src/interfaces/IGCC.sol";

contract Handler is Test {
    GCC public gcc;
    bool boundVars = true;
    uint256[] public ghost_fuzzBitmapIds;
    uint256[] public ghost_notFuzzedIds;
    address public gca;

    constructor(address _gcc, address _gca) public {
        gcc = GCC(_gcc);
        gca = _gca;
        // deal(address(this), 1e18 ether);
    }

    function mintToCarbonCreditAuction(uint256 bucketId, bool shouldStore) public {
        bool inFuzzed = inArr(ghost_fuzzBitmapIds, bucketId);
        bool inNotFuzzed = inArr(ghost_notFuzzedIds, bucketId);
        if (shouldStore) {
            if (!inFuzzed && !inNotFuzzed) {
                ghost_fuzzBitmapIds.push(bucketId);
                vm.startPrank(gca);
                gcc.mintToCarbonCreditAuction(bucketId, 1e20 ether);
                vm.stopPrank();
            }
            // fuzzBitmapIds.push(bucketId);
        } else {
            if (!inFuzzed && !inNotFuzzed) {
                ghost_notFuzzedIds.push(bucketId);
            }
        }
        return;
    }

    function getAllFuzzIds() public view returns (uint256[] memory) {
        return ghost_fuzzBitmapIds;
    }

    function getAllNotFuzzIds() public view returns (uint256[] memory) {
        return ghost_notFuzzedIds;
    }

    function inArr(uint256[] memory array, uint256 element) public pure returns (bool) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == element) {
                return true;
            }
        }
        return false;
    }

    function isBucketMinted(uint256 bucketId) public view returns (bool) {
        return gcc.isBucketMinted(bucketId);
    }
}

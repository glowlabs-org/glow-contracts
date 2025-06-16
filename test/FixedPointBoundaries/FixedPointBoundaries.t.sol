import {Test} from "forge-std/Test.sol";
import {HalfLife} from "@/libraries/HalfLife.sol";
import {HalfLifeCarbonCreditAuction} from "@/libraries/HalfLifeCarbonCreditAuction.sol";
import {console2} from "forge-std/console2.sol";

contract FixedPointBoundariesTest is Test {
    function setUp() public {}

    //Create some test functions to see the max boundaries

    function test_maxValueHalfLife_notAuction() public {
        //Try with uint128.max
        uint256 value = HalfLife.calculateHalfLifeValue(type(uint256).max, 1);
        console2.log("Value", value);
    }

    function test_maxValueHalfLife_auction() public {
        //Try with uint128.max
        uint256 value = HalfLifeCarbonCreditAuction.calculateHalfLifeValue(type(uint256).max, 1);
        console2.log("Value", value);
    }
}

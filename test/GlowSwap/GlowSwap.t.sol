// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import {GlowSwap} from "@/GlowSwap.sol";
import {TestGLOW} from "@/testing/TestGlow.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GlowSwap2} from "@/GlowSwap2.sol";

contract GlowSwapTest is Test {
    GlowSwap glowSwap;
    GlowSwap2 glowSwap2;
    TestGLOW glow;
    MockUSDC usdc;
    address public constant GCA = address(0x1);
    address public constant VETO_COUNCIL = address(0x2);
    address public constant GRANTS_TREASURY = address(0x3);
    address public constant EARLY_LIQUIDITY = address(0x4);
    address public constant VESTING_CONTRACT = address(0x5);
    address me = address(0xfffffafafaf41);

    function setUp() public {
        vm.startPrank(me);
        glow = new TestGLOW(EARLY_LIQUIDITY, VESTING_CONTRACT, GCA, VETO_COUNCIL, GRANTS_TREASURY);
        usdc = new MockUSDC();
        glow.mint(me, 1000000000000 ether);
        usdc.mint(me, 1000000000000 ether);
        glowSwap = new GlowSwap({_glow: IERC20(address(glow)), _usdc: IERC20(address(usdc))});
        //approve glow swap
        glow.approve(address(glowSwap), 1000000000000 ether);
        usdc.approve(address(glowSwap), 1000000000000 ether);
        glowSwap2 = new GlowSwap2();
        vm.stopPrank();
    }

    /*function test_initialize() public {
        //120 glow in pool
        //180 USD in pool
        //Glow price = 180/120 = $1.5 per glow
        address other = address(0x1);
        vm.startPrank(me);
        glowSwap.initialize(_toEther(120), _toUSDC(180), me);
        assertEq(glowSwap.x(), _toEther(120));
        assertEq(glowSwap.y(), _toUSDC(180));
        glowSwap.swap(_toEther(30), 0, 0, _toUSDC(60), me);
        //log the balance
        uint256 poolGlowBalance = glow.balanceOf(address(glowSwap));
        uint256 poolUSDCBalance = usdc.balanceOf(address(glowSwap));
        //log both
        // console.log("Pool Glow Balance: ", poolGlowBalance);
        // console.log("Pool USDC Balance: ", poolUSDCBalance);

        uint256 liquidity = glowSwap.balanceOf(me);
        console.log("liquidity: ", liquidity);
        glowSwap.removeLiquidity(liquidity, 0, 0, other);

        vm.stopPrank();

        //assert that both (m,c) are 60
        // assertEq(glowSwap.m(), 60);
    }*/

    function test_glowSwap2() public {
        glowSwap2.setState({
            _usdRef: uint112(_toEther(180)), //Let's just use same decimals for now
            _glowRef: uint112(_toEther(120)),
            _m: (int256(_toEther(60)))
        });
        //Buy $60
        uint256 amountGlow = glowSwap2.buyGlow(_toEther(60));
        /*console.log("amount glow = %s", amountGlow);*/
        //Print the state
        /*glowSwap2.printState();*/
    }

    function _toEther(uint256 _amount) internal pure returns (uint256) {
        return _amount * 1e18;
    }

    function _toUSDC(uint256 _amount) internal pure returns (uint256) {
        return _amount * 10 ** 6;
    }

    function _a0() internal pure returns (address) {
        return address(0);
    }
}

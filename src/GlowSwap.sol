// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GlowSwap is ERC20 {
    error InsufficientLiquidityMinted();
    error InsufficientLiquidityBurned();
    error InsufficientAmountGlow();
    error InsufficientAmountUSD();

    uint256 public constant MINIMUM_LIQUIDITY = 1e3;
    IERC20 public immutable glow;
    IERC20 public immutable usdc;

    uint112 public reserveX;
    uint112 public reserveY;
    // 'x': the amount of GLW in the pool's reference point
    // 'y': the amount of USD in the pool's reference point
    // 'm': the maximum USD that was added to the pool since the reference point was set
    uint256 public x;
    uint256 public y;
    uint256 public m;
    uint32 public blockTimestampLast;

    constructor(IERC20 _glow, IERC20 _usdc) payable ERC20("GlowSwap", "GLOW") {
        glow = _glow;
        usdc = _usdc;
    }

    function initialize(uint256 _x, uint256 _y, address to) public {
        //transfer
        // glow.transferFrom(msg.sender, address(this), _x);
        // usdc.transferFrom(msg.sender, address(this), _y);
        // reserveX = uint112(_x);
        // reserveY = uint112(_y);
        addLiquidty(_x, _y, 0, 0, to);
        x = _x;
        y = _y;
    }

    function swap(uint256 amountGlowOut, uint256 amountUSDOut, uint256 amountGlowTin, uint256 amountUSDTin, address to)
        public
    {
        if (amountGlowTin > 0) {
            glow.transferFrom(msg.sender, address(this), amountGlowTin);
        }
        if (amountUSDTin > 0) {
            usdc.transferFrom(msg.sender, address(this), amountUSDTin);
            m += amountUSDTin;
        }
        (uint256 glowReserve, uint256 usdcReserve) = getReserves();
        uint256 balanceGlow;
        uint256 balanceUSD;
        {}
        uint256 glowFee;
        uint256 usdcFee;
        if (amountGlowOut > 0) {
            //optmistically transfer tokens
            glowFee = computeFee(amountGlowOut, m, y);
            glow.transfer(to, amountGlowOut - glowFee);
        }
        if (amountUSDOut > 0) {
            //optimistically transfer tokens
            usdcFee = computeFee(amountUSDOut, m, y);
            usdc.transfer(to, amountUSDOut);
        }

        balanceGlow = glow.balanceOf(address(this));
        balanceUSD = usdc.balanceOf(address(this));
        // console.log("balanceGlow: ", balanceGlow);
        // console.log("balanceUSD: ", balanceUSD);

        uint256 amountGlowIn =
            balanceGlow > glowReserve - amountGlowOut ? balanceGlow - (glowReserve - amountGlowOut) : 0;
        uint256 amountUSDIn = balanceUSD > usdcReserve - amountUSDOut ? balanceUSD - (usdcReserve - amountUSDOut) : 0;
        if (amountGlowIn | amountUSDIn == 0) revert("Insufficient Input Amount");
        {
            uint256 balanceGlowAdjusted = (balanceGlow - glowFee) * 1000;
            uint256 balanceUSDAdjusted = (balanceUSD - usdcFee) * 1000;
            // console.log("balanceGlowAdjusted: ", balanceGlowAdjusted);
            // console.log("balanceUSDAdjusted: ", balanceUSDAdjusted);
            require(
                balanceGlowAdjusted * balanceUSDAdjusted >= uint256(glowReserve) * usdcReserve * 1000 ** 2,
                "UniswapV2: K"
            );
        }

        _updateReserves(balanceGlow, balanceUSD);
        //transfer usdc here
        // usdc.transferFrom(msg.sender, address(this), amountUSD);
        // m = amountUSD;
        // uint balanceUSDC = usdc.balanceOf(address(this));
        // uint balance
        // reserveY += uint112(amountUSD);
        // uint256 amountGlow = amountUSD * reserveX / reserveY;
        // uint256 fee = computeFee(amountGlow, m, y);
        // uint256 amountToSendToUser = amountGlow - fee;
        // reserveX -= uint112(amountGlow);
        // //transfer
        // glow.transfer(to, amountToSendToUser);
        // //log reserves
        // console.log("amount glow = ", amountGlow);
        // //log fee
        // console.log("fee = ", fee);
        // console.log("ReserveX: ", reserveX);
        // console.log("ReserveY: ", reserveY);
        // console.log("Amount to send to user: ", amountToSendToUser);
    }

    function computeFee(uint256 _amount, uint256 _m, uint256 _y) public pure returns (uint256) {
        return _amount * _m / (2 * _m + _y);
    }

    function getReserves() public view returns (uint256, uint256) {
        return (uint256(reserveX), uint256(reserveY));
    }

    function addLiquidty(
        uint256 amountGlowDesired,
        uint256 amountUSDDesired,
        uint256 amountGlowMin,
        uint256 amountUSDMin,
        address to
    ) public returns (uint256 liquidity) {
        //transfer glow and usdc here
        (uint256 amountGlow, uint256 amountUSD) =
            _computeLiquidityAmounts(amountGlowDesired, amountUSDDesired, amountGlowMin, amountUSDMin);
        glow.transferFrom(msg.sender, address(this), amountGlow);
        usdc.transferFrom(msg.sender, address(this), amountUSD);
        uint256 balanceGlow = glow.balanceOf(address(this));
        uint256 balanceUSD = usdc.balanceOf(address(this));
        uint256 _totalSupply = totalSupply();

        uint256 diffGlow = balanceGlow - reserveX;
        uint256 diffUSD = balanceUSD - reserveY;

        if (_totalSupply == 0) {
            liquidity = FixedPointMathLib.sqrt(diffGlow * diffUSD) - MINIMUM_LIQUIDITY;
            _mint(address(0xdead), MINIMUM_LIQUIDITY);
        } else {
            liquidity = _min((diffGlow * _totalSupply) / reserveX, (diffUSD * _totalSupply) / reserveY);
        }

        if (liquidity == 0) {
            revert InsufficientLiquidityMinted();
        }

        _mint(to, liquidity);
        _updateReserves(balanceGlow, balanceUSD);
    }

    function removeLiquidity(uint256 liquidity, uint256 amountGlowMin, uint256 amountUSDMin, address to)
        public
        returns (uint256 amountGlow, uint256 amountUSD)
    {
        uint256 balanceGlow = glow.balanceOf(address(this));
        uint256 balanceUSD = usdc.balanceOf(address(this));

        amountGlow = (liquidity * balanceGlow) / reserveX;

        if (amountGlow < amountGlowMin) {
            revert InsufficientAmountGlow();
        }
        amountUSD = (liquidity * balanceUSD) / reserveY;
        if (amountUSD < amountUSDMin) {
            revert InsufficientAmountUSD();
        }

        if (amountGlow == 0 || amountUSD == 0) {
            revert InsufficientLiquidityBurned();
        }
        console.log("amountGlow: ", amountGlow);
        console.log("amountUSD: ", amountUSD);
        _burn(msg.sender, liquidity);
        _updateReserves(balanceGlow - amountGlow, balanceUSD - amountUSD);

        glow.transfer(to, amountGlow);
        usdc.transfer(to, amountUSD);
    }

    function _computeLiquidityAmounts(
        uint256 amountGlowDesired,
        uint256 amountUSDDesired,
        uint256 amountGlowMin,
        uint256 amountUSDMin
    ) public view returns (uint256 amountGlow, uint256 amountUSD) {
        uint256 reserveGlow = reserveX;
        uint256 reserveUSD = reserveY;

        if (reserveGlow == 0 && reserveUSD == 0) {
            (amountGlow, amountUSD) = (amountGlowDesired, amountUSDDesired);
            return (amountGlow, amountUSD);
        }
        amountGlow = quote(amountUSDDesired, reserveUSD, reserveGlow);
        if (amountGlow <= amountGlowDesired) {
            if (amountGlow < amountGlowMin) {
                revert InsufficientAmountGlow();
            }
        } else {
            amountUSD = quote(amountGlowDesired, reserveGlow, reserveUSD);
            if (amountUSD < amountUSDMin) {
                revert InsufficientAmountUSD();
            }
        }
    }

    function quote(uint256 amount0, uint256 reserve0, uint256 reserve1) public pure returns (uint256) {
        return (amount0 * reserve1) / reserve0;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _updateReserves(uint256 balanceGlow, uint256 balanceUSD) internal {
        reserveX = uint112(balanceGlow);
        reserveY = uint112(balanceUSD);
        blockTimestampLast = uint32(block.timestamp);
    }
}

// // this low-level function should be called from a contract which performs important safety checks
//     function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
//         require(amount0Out > 0 || amount1Out > 0, 'UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT');
//         (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
//         require(amount0Out < _reserve0 && amount1Out < _reserve1, 'UniswapV2: INSUFFICIENT_LIQUIDITY');

//         uint balance0;
//         uint balance1;
//         { // scope for _token{0,1}, avoids stack too deep errors
//         address _token0 = token0;
//         address _token1 = token1;
//         require(to != _token0 && to != _token1, 'UniswapV2: INVALID_TO');
//         if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
//         if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
//         if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
//         balance0 = IERC20(_token0).balanceOf(address(this));
//         balance1 = IERC20(_token1).balanceOf(address(this));
//         }
//         uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
//         uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
//         require(amount0In > 0 || amount1In > 0, 'UniswapV2: INSUFFICIENT_INPUT_AMOUNT');
//         { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
//         uint balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3));
//         uint balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3));
//         require(balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(1000**2), 'UniswapV2: K');
//         }

//         _update(balance0, balance1, _reserve0, _reserve1);
//         emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
//     }

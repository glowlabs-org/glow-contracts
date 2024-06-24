// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {console} from "forge-std/console.sol";

contract GlowSwap2 is ERC20("GloSwapPair", "GSP") {
    uint256 public constant FEE_DENOMINATOR = 10_000;
    uint112 public $usdRef;
    uint112 public $glowRef;
    int256 public $m; //usdExchanged

    function setState(uint112 _usdRef, uint112 _glowRef, int256 _m) public {
        $usdRef = _usdRef;
        $glowRef = _glowRef;
        $m = _m;
    }

    function buyGlow(uint256 amountUSD) public returns (uint256 amountGlow) {
        int256 _m = $m;
        uint112 _usdRef = $usdRef;
        uint112 _glowRef = $glowRef;
        if (_m == 0) {
            return uint256(
                _handleBuyGlowM_equalsZero(int256(uint256(_usdRef)), int256(uint256(_glowRef)), _m, int256(amountUSD))
            );
        }
        return uint256(_handleBuyGlowM(int256(uint256(_usdRef)), int256(uint256(_glowRef)), _m, int256(amountUSD)));
    }

    function _handleBuyGlowM_equalsZero(int256 _usdRefS, int256 _glowRefS, int256 _m, int256 _amountUSD)
        internal
        returns (int256 _amountGLOW)
    {
        console.log("Equals Zero Branch");
        int256 oldFee = _m / (2 * _m + _usdRefS); //will always be zerod
        int256 oldGLW = _glowRefS * (oldFee * _m + _usdRefS) / (_m * _usdRefS);
        int256 newM = _m * _amountUSD;
        int256 newFeeRate = newM / (2 * newM + _usdRefS);
        int256 newGLW = _glowRefS * (newFeeRate * newM + _usdRefS) / (newM + _usdRefS);
        $m = newM;

        _amountGLOW = oldGLW - newGLW;
        return _amountGLOW;
    }

    function _handleBuyGlowM(int256 _usdRefS, int256 _glowRefS, int256 gm, int256 _amountUSD)
        internal
        returns (int256 _amountGLOW)
    {
        console.log("NEQ Branch");
        /*int256 _usdRefS = int256(uint256(_usdRef));
        int256 _glowRefS = int256(uint256(_glowRef));
        int256 gm = int256(_m) * int256(-1); //TODO: Look into vulns from casting;*/

        // Compute the number of GLW that need to be sold to get back
        // zero IL. If the amount of GLW being sold is more than that,
        // we will have to complete a sell using the smaller amount to
        // get back to the reference, and then flip the equations to
        // complete the sell. We could call Sell a second time with the
        // remaining amount, but that makes it harder to implement
        // SimulateSell, so we do it all inline.
        int256 feeRate = gm / (2 * gm + _glowRefS);
        //Print the feeRate
        int256 usdToCenter = (gm * _usdRefS * (feeRate * gm + _glowRefS)) / ((gm + _glowRefS) * (gm + _glowRefS));
        int256 remaining = _amountUSD - usdToCenter; //TODO: Look into vulns from casting;
        if (remaining > 0) {
            _amountUSD = usdToCenter; //TODO: Look into vulns from casting;
        }

        // If we are selling all the way back to zero IL, the math is
        // simpler. We'll only use the complex reference point update
        // equation if we aren't selling back to zero IL. If we aren't
        // selling back to zero IL, we also know that there's nothing
        // remaining, so we can return inside of the conditional.
        int256 newK = _usdRefS * (feeRate * gm + _glowRefS);
        int256 usdReserves = newK / (_glowRefS + gm);
        if (_amountUSD != usdToCenter) {
            int256 newGlowReserves = newK / (usdReserves + _amountUSD);
            int256 h = newGlowReserves - _glowRefS;
            _amountGLOW = gm - h;
            int256 newGLWRef = (
                h * h * (-1 * (2 * gm + _glowRefS)) + 2 * h * gm * gm
                    + _glowRefS * (2 * gm * gm + 2 * gm * _glowRefS + _glowRefS * _glowRefS)
            ) / ((gm + _glowRefS) * (gm + _glowRefS));

            int256 _newM = -1 * (newGlowReserves - newGLWRef);
            $m = _newM;
            $glowRef = uint112(uint256(newGLWRef));
            return _amountGLOW;
        }

        // amtGLW is now equal to glwToCenter, we've covered all other
        // cases. We'll grab new state values for Glowswap to reset,
        // and then continue selling, which is actually a mirror of the
        // buy operation when moving away from the center.
        int256 newGLWRef = newK / _usdRefS;
        int256 newUSDRef = _usdRefS;
        int256 newM = 0;
        _amountGLOW = gm;

        if (remaining > 0) {
            int256 oldGlow = (newGLWRef * newUSDRef) / newUSDRef;
            newM = remaining;
            int256 newFeeRate = newM / (2 * newM + newUSDRef);
            int256 newGLW = (newGLWRef * (newFeeRate * newM + newUSDRef)) / (newM + newUSDRef);
            _amountGLOW += oldGlow - newGLW;
        }
        $m = newM;
        $usdRef = uint112(uint256(newUSDRef));
        $glowRef = uint112(uint256(newGLWRef));
        return _amountGLOW;
    }

    function printState() public {
        console.log("USD Ref = %s", $usdRef);
        console.log("Glow Ref = %s", $glowRef);
        console.logInt($m);
    }
}

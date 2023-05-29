pragma solidity ^0.8.0;

import "@/abdk-libraries/ABDKMath64x64.sol";

contract ExpApproximation {
    function oneOverExpX(uint256 whole, uint256 decimals, uint256 decimalShifts) public pure returns (int128) {
        // Convert the whole and decimal parts into a single fixed-point number
        decimals = decimals * 10 ** decimalShifts;
        int128 x = ABDKMath64x64.fromUInt(whole);
        if (decimals > 0) {
            int128 xDecimals = ABDKMath64x64.divu(decimals, 10 ** 18);
            x = ABDKMath64x64.add(x, xDecimals);
        }

        // Calculate e^x
        int128 expX = ABDKMath64x64.exp(x);

        // Calculate 1 / e^x
        int128 result = ABDKMath64x64.inv(expX);

        return result;
    }

    function convert(int128 fixedPointNumber) public pure returns (uint256 whole, uint256 decimals) {
        whole = ABDKMath64x64.toUInt(fixedPointNumber);
        int128 remainder = ABDKMath64x64.sub(fixedPointNumber, ABDKMath64x64.fromUInt(whole));

        // Conversion from the fractional part of fixed-point number to an integer might lead to precision loss
        // Multiply first by 10**18 to keep precision
        remainder = ABDKMath64x64.mul(remainder, ABDKMath64x64.fromUInt(10 ** 18));

        // Extract the decimals as an integer
        decimals = ABDKMath64x64.toUInt(remainder);
    }

    function calculatePurchasePrice(uint256 treasurySize, uint256 assetNominalValue, uint256 shift)
        public
        pure
        returns (uint256)
    {
        treasurySize = treasurySize * 10 ** shift;
        assetNominalValue = assetNominalValue * 10 ** shift;
        // Calculate the proportion of the treasury that would be used to purchase the asset
        uint256 whole = assetNominalValue / treasurySize;
        uint256 decimals = (assetNominalValue % treasurySize) * 10 ** 18 / treasurySize;

        // Calculate 1 / e^x
        int128 oneOverExpX = oneOverExpX(whole, decimals, 0);

        // Calculate treasurySize * 1 / e^x
        uint256 decrease = ABDKMath64x64.mulu(oneOverExpX, treasurySize);

        // Calculate the final purchase price
        uint256 purchasePrice = treasurySize - decrease;

        return purchasePrice;
    }
}

contract HalfLife {
    uint256 constant HALF_LIFE_MONTHS = 12;
    uint256 constant SECONDS_IN_MONTH = 30 days;

    function calculateHalfLifeValue(uint256 initialValue, uint256 elapsedSeconds) public pure returns (uint256) {
        // Convert the half-life from months to seconds
        uint256 halfLifeSeconds = HALF_LIFE_MONTHS * SECONDS_IN_MONTH;

        // Calculate the ratio of elapsed time to half-life in fixed point format
        int128 tOverT =
            ABDKMath64x64.div(ABDKMath64x64.fromUInt(elapsedSeconds), ABDKMath64x64.fromUInt(halfLifeSeconds));

        // Calculate (1/2)^(t/T) using the fact that e^(ln(0.5)*t/T) = (0.5)^(t/T)
        int128 halfPowerTOverT =
            ABDKMath64x64.exp(ABDKMath64x64.mul(ABDKMath64x64.ln(ABDKMath64x64.divu(1, 2)), tOverT));

        // Calculate the final amount
        uint256 finalValue = ABDKMath64x64.mulu(halfPowerTOverT, initialValue);

        return finalValue;
    }
}

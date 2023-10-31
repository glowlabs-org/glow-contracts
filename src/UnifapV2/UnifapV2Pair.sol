// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

import "solmate/tokens/ERC20.sol";
import "solmate/utils/FixedPointMathLib.sol";
import "solmate/utils/ReentrancyGuard.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./interfaces/IERC20.sol";
import "./libraries/Math.sol";
import "./libraries/UQ112x112.sol";
import "forge-std/console.sol";
/// @title UnifapV2Pair
/// @author Uniswap Labs
/// @notice maintains a liquidity pool of a pair of tokens
contract UnifapV2Pair is ERC20, ReentrancyGuard, Initializable {
    // ========= Custom Errors =========

    error InsufficientLiquidityMinted();
    error InsufficientLiquidityBurned();
    error SafeTransferFailed();
    error SwapToSelf();
    error InsufficientLiquidity();
    error InvalidAmount();
    error InvalidConstantProductFormula();
    error BalanceOverflow();

    // ========= Libraries =========

    using Math for uint256;
    using FixedPointMathLib for uint256;
    using UQ112x112 for uint224;

    // ========= Constants =========

    uint256 public constant MINIMUM_LIQUIDITY = 1e3;
    bytes4 public constant SELECTOR = bytes4(keccak256("transfer(address,uint256"));

    // ========= State Variables =========

    address public token0;
    address public token1;

    // reserves are tracked rather than balances to prevent price manipulation
    // bit-packing is done to save gas
    uint112 public reserve0;
    uint112 public reserve1;
    uint32 public blockTimestampLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;

    // ======== Events ========

    event Mint(address indexed _operator, uint256 _value);
    event Burn(address indexed _operator, uint256 _value);
    event Swap(address indexed sender, uint256 amount0Out, uint256 amount1Out, address indexed to);
    event Sync(uint112 reserve0, uint112 reserve1);

    // ========= Constructor =========

    constructor() ERC20("UnifapV2", "UNIV2", 18) {}

    // ========= Initializer =========

    function initialize(address _token0, address _token1) external initializer {
        token0 = _token0;
        token1 = _token1;
    }

    // ========= Public Functions =========

    /// @notice Returns reserves and last synced block timestamp
    /// @return reserve0 Reserve of token 0
    /// @return reserve1 Reserve of token 1
    /// @return blockTimestampLast Block timestamp of last sync
    function getReserves() public view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, blockTimestampLast);
    }

    /// @notice Calculate the pool tokens for the given new liquidity amount
    /// @dev If new pool is created, then minimum liquidity is 1e3 transfered to 0x0
    /// @param to Address to which pool tokens are minted
    /// @return liquidity Total liquidity minted
    function mint(address to) public nonReentrant returns (uint256 liquidity) {
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint256 amount0 = balance0 - uint256(reserve0);
        uint256 amount1 = balance1 - uint256(reserve1);

        if (totalSupply == 0) {
            // Initial liquidity = sqrt(a0 * a1)
            liquidity = FixedPointMathLib.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;

            // Prevents value of 1 LP token being too high
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            // Minimum because max is prone to price manipulation
            liquidity = Math.min((amount0 * totalSupply) / reserve0, (amount1 * totalSupply) / reserve1);
        }

        if (liquidity == 0) revert InsufficientLiquidityMinted();

        _mint(to, liquidity);

        _update(balance0, balance1, reserve0, reserve1);

        emit Mint(to, liquidity);
    }

    /// @notice Burns pool tokens of a particular address
    /// @dev Needs to transfer pool tokens to the pool first to be burnt
    /// @param to Address whose tokens are burned
    /// @return amount0 Amount of token0 burned
    /// @return amount1 Amount of token1 burned
    function burn(address to) public nonReentrant returns (uint256 amount0, uint256 amount1) {
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint256 liquidity = balanceOf[address(this)];

        amount0 = (liquidity * balance0) / uint256(reserve0);
        amount1 = (liquidity * balance1) / uint256(reserve1);

        if (amount0 == 0 || amount1 == 0) revert InsufficientLiquidityBurned();

        _burn(address(this), liquidity);

        _safeTransfer(token0, to, amount0);
        _safeTransfer(token1, to, amount1);

        _update(balance0 - amount0, balance1 - amount1, reserve0, reserve1);

        emit Burn(to, liquidity);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external nonReentrant {
        console.log("here mom!");
        require(amount0Out > 0 || amount1Out > 0, "UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT");
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "UniswapV2: INSUFFICIENT_LIQUIDITY");

        uint256 balance0;
        uint256 balance1;
        {
            // scope for _token{0,1}, avoids stack too deep errors
            address _token0 = token0;
            address _token1 = token1;
            require(to != _token0 && to != _token1, "UniswapV2: INVALID_TO");
            if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
            if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
            if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }
        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, "UniswapV2: INSUFFICIENT_INPUT_AMOUNT");
        {
            // scope for reserve{0,1}Adjusted, avoids stack too deep errors
            uint256 balance0Adjusted = balance0 * (1000) - (amount0In * (3));
            uint256 balance1Adjusted = balance1 * (1000) - (amount1In * (3));
            require(
                balance0Adjusted * (balance1Adjusted) >= uint256(_reserve0) * (_reserve1) * (1000 ** 2), "UniswapV2: K"
            );
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        // emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    /// @notice Syncs reserves
    function sync() public {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }

    // ========= Internal functions =========

   // update reserves and, on the first call per block, price accumulators
    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, 'UniswapV2: OVERFLOW');
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        // emit Sync(reserve0, reserve1);
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        bool success = IERC20(token).transfer(to, amount);
        if (!success) revert SafeTransferFailed();
    }
}

interface IUniswapV2Callee {
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}

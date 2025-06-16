// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdCheats.sol";
import "forge-std/console.sol";
import {MainnetForkTestGCC} from "../../MainnetForkTestGCC.sol";
import {IUniswapV2Pair} from "@glow/interfaces/IUniswapV2Pair.sol";
import {ImpactCatalyst} from "@glow/ImpactCatalyst.sol";
import {UnifapV2Router} from "@unifapv2/UnifapV2Router.sol";
import {MockUSDC} from "@glow/testing/MockUSDC.sol";

contract EstimateNominationsHandler is Test {
    uint256 constant MINIMUM_LIQUIDITY = 1e3;
    uint256 numGCCSwapSuccesses;
    uint256 numGCCSwapFailures;
    uint256 numUSDCSwapSuccesses;
    uint256 numUSDCSwapFailures;

    uint256 numOtherFailures;

    bool hasSeededLP;

    MockUSDC public immutable usdc;
    MainnetForkTestGCC public immutable gcc;
    UnifapV2Router public immutable uniswapRouter;

    mapping(uint256 => uint256) public estimatedmpactPowerForRound;
    mapping(uint256 => uint256) public actualImpactPowerForRound;

    struct Dust {
        uint256 amountGCCToSwap;
        uint256 gccDust;
        uint256 usdcDust;
    }

    mapping(uint256 => Dust) private _dustForRound;

    uint256 public round;

    constructor(address _gcc, address _uniswapRouter) {
        gcc = MainnetForkTestGCC(_gcc);
        usdc = MockUSDC(gcc.USDC());
        uniswapRouter = UnifapV2Router(_uniswapRouter);
    }

    function seedAndCommitGCCHandler(
        address from,
        uint256 amountGCCToSeedLP,
        uint256 amountUSDCToSeedLP,
        uint256 amount
    ) external {
        (bool res,) =
            address(this).call(abi.encodeWithSelector(0xb00073d9, from, amountGCCToSeedLP, amountUSDCToSeedLP, amount));
        if (!res) numOtherFailures++;
        numOtherFailures++;
    }

    function seedAndCommitGCC(address from, uint256 amountGCCToSeedLP, uint256 amountUSDCToSeedLP, uint256 amount)
        public
        returns (bool)
    {
        Dust memory dust = _dustForRound[round];
        if (!hasSeededLP) {
            amountGCCToSeedLP = bound(amountGCCToSeedLP, 10 ether, 1_000_000_000 ether);
            amountUSDCToSeedLP = bound(amountUSDCToSeedLP, 10 * 1e6, 1_000_000_000 * 1e6);
            seedLP(from, amountGCCToSeedLP, amountUSDCToSeedLP);
            hasSeededLP = true;
        }
        uint256 reservesGCC;
        {
            (uint256 reserveA, uint256 reserveB,) =
                IUniswapV2Pair(address(gcc.IMPACT_CATALYST().UNISWAP_V2_PAIR())).getReserves();
            reservesGCC = address(gcc) > address(gcc.USDC()) ? reserveB : reserveA;
            amount = bound(reservesGCC, MINIMUM_LIQUIDITY, reservesGCC);
        }
        vm.startPrank(from);
        if (gcc.balanceOf(from) < amount) {
            uint256 amountNeeded = amount - gcc.balanceOf(from);
            gcc.mint(from, amountNeeded);
        }

        ImpactCatalyst impactCatalyst = gcc.IMPACT_CATALYST();
        uint256 estimate = impactCatalyst.estimateGCCCommitImpactPower(amount);
        uint256 impactPowerBefore = gcc.totalImpactPowerEarned(from);

        dust.amountGCCToSwap = amount;
        dust.gccDust = gcc.balanceOf(address(impactCatalyst)); //bal before
        dust.usdcDust = usdc.balanceOf(address(impactCatalyst)); //bal before
        (bool success, bytes memory data) = address(gcc).call(abi.encodeWithSelector(0x4ca9a234, amount, from, 0));
        if (!success) {
            // vm.writeLine("t.csv", "1");
            numGCCSwapFailures++;
            //Uniswap error for insufficient amount in case we need it
            //0x08c379a000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000025556e697377617056323a20494e53554646494349454e545f4f55545055545f414d4f554e54000000000000000000000000000000000000000000000000000000
        } else {
            dust.gccDust = gcc.balanceOf(address(impactCatalyst)); //bal after (accumulated)
            dust.usdcDust = usdc.balanceOf(address(impactCatalyst)); //bal after (accumulated)
            _dustForRound[round] = dust;
            estimatedmpactPowerForRound[round] = estimate;
            uint256 impactPowerEarned = gcc.totalImpactPowerEarned(from) - impactPowerBefore;
            actualImpactPowerForRound[round++] = impactPowerEarned;
            numGCCSwapSuccesses++;
        }

        // if(!success && )
        vm.stopPrank();
        return success;
    }

    function seedLP(address from, uint256 amountGCC, uint256 amountUSDC) public {
        vm.startPrank(from);
        usdc.mint(from, amountUSDC);
        gcc.mint(from, amountGCC);
        gcc.approve(address(uniswapRouter), amountGCC);
        usdc.approve(address(uniswapRouter), amountUSDC);
        uniswapRouter.addLiquidity(
            address(gcc), address(usdc), amountGCC, amountUSDC, amountGCC, amountUSDC, from, block.timestamp
        );
        vm.stopPrank();
    }

    function dustForRound(uint256 round) external view returns (Dust memory) {
        return _dustForRound[round];
    }
}

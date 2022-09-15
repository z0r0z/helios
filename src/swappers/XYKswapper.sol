// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {FixedPointMathLib} from "@solbase/utils/FixedPointMathLib.sol";
import {ReentrancyGuard} from "@solbase/utils/ReentrancyGuard.sol";
import {ERC20, IHelios} from "../interfaces/IHelios.sol";

/// @notice XYK swapper for Helios.
/// @author Modified from UniswapV2Pair (https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol)
contract XYKswapper is ReentrancyGuard {
    /// -----------------------------------------------------------------------
    /// Library Usage
    /// -----------------------------------------------------------------------

    using FixedPointMathLib for uint256;

    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------

    uint224 private constant Q112 = 2**112;
    uint256 private constant MIN_LP = 10**3;

    /// -----------------------------------------------------------------------
    /// Math
    /// -----------------------------------------------------------------------

    function min(uint256 x, uint256 y) private pure returns (uint256 z) {
        z = x < y ? x : y;
    }

    /// -----------------------------------------------------------------------
    /// LP Logic
    /// -----------------------------------------------------------------------

    function addLiquidity(
        uint256 id,
        uint256 token0amount,
        uint256 token1amount
    ) external nonReentrant returns (uint256 liq) {
        IHelios.Pair memory pair = IHelios(msg.sender).pairs(id);

        uint256 reserve0 = pair.reserve0;
        uint256 reserve1 = pair.reserve1;

        uint256 totalSupply = IHelios(msg.sender).totalSupplyForId(id);

        if (totalSupply == 0) {
            liq = (token0amount * token1amount).sqrt() - MIN_LP;
        } else {
            liq = min(
                (token0amount * totalSupply) / reserve0,
                (token1amount * totalSupply) / reserve1
            );
        }

        require(liq != 0, "XYKswapper: INSUFFICIENT_LIQUIDITY_MINTED");
    }

    function removeLiquidity(uint256 id, uint256 lp)
        external
        nonReentrant
        returns (uint256 amount0out, uint256 amount1out)
    {
        IHelios.Pair memory pair = IHelios(msg.sender).pairs(id);

        uint256 reserve0 = pair.reserve0;
        uint256 reserve1 = pair.reserve1;

        uint256 totalSupply = IHelios(msg.sender).totalSupplyForId(id);

        amount0out = (lp * reserve0) / totalSupply;
        amount1out = (lp * reserve1) / totalSupply;

        require(
            amount0out != 0 && amount1out != 0,
            "XYKswapper: INSUFFICIENT_LIQUIDITY_BURNED"
        );
    }

    /// -----------------------------------------------------------------------
    /// Swap Logic
    /// -----------------------------------------------------------------------

    function swap(
        uint256 id,
        ERC20 tokenIn,
        uint256 amountIn
    ) external nonReentrant returns (uint256 amountOut) {
        IHelios.Pair memory pair = IHelios(msg.sender).pairs(id);

        uint256 reserve0 = pair.reserve0;
        uint256 reserve1 = pair.reserve1;

        uint256 fee = pair.fee;

        if (tokenIn == pair.token0) {
            amountOut = _getAmountOut(amountIn, reserve0, reserve1, fee);
        } else {
            require(tokenIn == pair.token1, "XYKswapper: INVALID_INPUT_TOKEN");
            amountOut = _getAmountOut(amountIn, reserve1, reserve0, fee);
        }
    }

    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveAmountIn,
        uint256 reserveAmountOut,
        uint256 fee
    ) private pure returns (uint256 amountOut) {
        uint256 amountInWithFee = amountIn * (10000 - fee);
        uint256 newReserveIn = reserveAmountIn * 10000 + amountInWithFee;
        amountOut =
            (amountInWithFee * reserveAmountOut + (newReserveIn >> 1)) /
            newReserveIn;
    }
}

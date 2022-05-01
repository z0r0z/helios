// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity >=0.8.4;

import {SqrtMath} from '../libraries/math/SqrtMath.sol';
import {ReentrancyGuard} from '../utils/ReentrancyGuard.sol';
import {IHelios} from '../interfaces/IHelios.sol';

/// @notice XYK swapper for Helios
/// @author Modified from UniswapV2Pair (https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol)
/// License-Identifier: GPL-3.0
contract XYKswapper is ReentrancyGuard {
    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------
    
    error InsuffLiquidityMint();
    error InsuffLiquidityBurn();
    error InvalidInputToken();
    
    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------

    uint224 private constant Q112 = 2**112;
    uint256 private constant MIN_LP = 10**3;
    
    /// -----------------------------------------------------------------------
    /// Math
    /// -----------------------------------------------------------------------

    function min(uint256 x, uint256 y) internal pure virtual returns (uint256 z) {
        z = x < y ? x : y;
    }
    
    /// -----------------------------------------------------------------------
    /// LP Logic
    /// -----------------------------------------------------------------------

    function addLiquidity(uint256 id, uint256 token0amount, uint256 token1amount) public nonReentrant returns (uint256 liq) {
        IHelios.Pair memory pair = IHelios(msg.sender).pairs(id);

        uint256 reserve0 = pair.reserve0;
        uint256 reserve1 = pair.reserve1;

        uint256 totalSupply = IHelios(msg.sender).totalSupplyForId(id);
  
        if (totalSupply == 0) {
            liq = SqrtMath.sqrt(token0amount * token1amount) - MIN_LP;
        } else {
            liq = min(token0amount * totalSupply / reserve0, token1amount * totalSupply / reserve1);
        }

        if (liq == 0) revert InsuffLiquidityMint();
    }

    function removeLiquidity(uint256 id, uint256 lp) public nonReentrant returns (uint256 amount0out, uint256 amount1out) {
        IHelios.Pair memory pair = IHelios(msg.sender).pairs(id);

        uint256 reserve0 = pair.reserve0;
        uint256 reserve1 = pair.reserve1;

        uint256 totalSupply = IHelios(msg.sender).totalSupplyForId(id);

        amount0out = lp * reserve0 / totalSupply; 
        amount1out = lp * reserve1 / totalSupply;

        if (amount0out == 0 || amount1out == 0) revert InsuffLiquidityBurn();
    }
    
    /// -----------------------------------------------------------------------
    /// Swap Logic
    /// -----------------------------------------------------------------------

    function swap(uint256 id, address tokenIn, uint256 amountIn) public nonReentrant returns (uint256 amountOut) {
        IHelios.Pair memory pair = IHelios(msg.sender).pairs(id);

        uint256 reserve0 = pair.reserve0;
        uint256 reserve1 = pair.reserve1;
        
        uint256 fee = pair.fee;

        if (tokenIn == pair.token0) {
            amountOut = _getAmountOut(amountIn, reserve0, reserve1, fee);
        } else {
            if (tokenIn != pair.token1) revert InvalidInputToken();
            amountOut = _getAmountOut(amountIn, reserve1, reserve0, fee);
        }
    }

    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveAmountIn,
        uint256 reserveAmountOut,
        uint256 fee
    ) internal view virtual returns (uint256 amountOut) {
        uint256 amountInWithFee = amountIn * (10000 - fee);
        amountOut = (amountInWithFee * reserveAmountOut) / (reserveAmountIn * 10000 + amountInWithFee);
    }
}

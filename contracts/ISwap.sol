// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.4;

/// @notice Helios interface for liquidity management and swap.
interface ISwap {
    function addLiquidity(uint256 id, uint256 token0amount, uint256 token1amount) external returns (uint256 lp);

    function removeLiquidity(uint256 id, uint256 lp) external returns (uint256 amount0out, uint256 amount1out);

    function swap(uint256 id, address tokenIn, uint256 amountIn) external returns (uint256 amountOut);
}

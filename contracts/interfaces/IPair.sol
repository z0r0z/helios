// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity >=0.8.4;

/// @notice Helios interface for liquidity management and pair swap
interface IPair {
    function addLiquidity(uint256 id, uint256 token0amount, uint256 token1amount) external returns (uint256 liq);

    function removeLiquidity(uint256 id, uint256 liq) external returns (uint256 amount0out, uint256 amount1out);

    function swap(uint256 id, address tokenIn, uint256 amountIn) external returns (uint256 amountOut);
}

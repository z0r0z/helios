// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface ERC20 {}

/// @notice Swapper interface for Helios
interface IHelios {
    struct Pair {
        ERC20 token0;
        ERC20 token1;
        IHelios swapper;
        uint112 reserve0;
        uint112 reserve1;
        uint8 fee;
    }

    function pairs(uint256 id) external view returns (Pair memory pair);

    function totalSupplyForId(uint256 id) external view returns (uint256);

    function addLiquidity(
        uint256 id,
        uint256 token0amount,
        uint256 token1amount
    ) external returns (uint256 liq);

    function removeLiquidity(uint256 id, uint256 liq)
        external
        returns (uint256 amount0out, uint256 amount1out);

    function swap(
        uint256 id,
        address tokenIn,
        uint256 amountIn
    ) external returns (uint256 amountOut);
}

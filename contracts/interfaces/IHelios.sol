// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.4;

/// @notice Swapper interface for Helios
interface IHelios {
    struct Pair {
        address token0; 
        address token1; 
        address swapper; 
        uint112 reserve0; 
        uint112 reserve1; 
        uint8 fee;
    }

    function pairs(uint256 id) external view returns (Pair memory pair);

    function totalSupplyForId(uint256 id) external view returns (uint256);
}

// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity >=0.8.4;

import {SafeTransferLib} from '../libraries/SafeTransferLib.sol';

/// @notice Minimal ERC-20 interface.
interface IERC20minimal { 
    function approve(address spender, uint256 amount) external view returns (bool);
}

/// @notice Helios interface for liquidity management and pair swap
interface IPair {
    function addLiquidity(
        address to,
        uint256 id, 
        uint256 token0amount,
        uint256 token1amount,
        bytes calldata data
    ) external returns (uint256 liq);

    function removeLiquidity(uint256 id, uint256 liq) external returns (uint256 amount0out, uint256 amount1out);

    function swap(uint256 id, address tokenIn, uint256 amountIn) external returns (uint256 amountOut);
}

/// @notice Minimal Uniswap V2 LP interface
interface IUniswapV2Minimal {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function burn(address to) external returns (uint256 amount0, uint256 amount1);
}

/// @notice Uniswap V2-style migrator for Helios
contract HeliosMigrator {
    using SafeTransferLib for address;

    IPair helios;

    constructor(IPair helios_) {
        helios = helios_;
    }

    function migrate(
        address pair,
        address to,
        uint256 id, 
        uint256 amount
    ) public returns (uint256 liq) {
        address token0 = IUniswapV2Minimal(pair).token0();
        address token1 = IUniswapV2Minimal(pair).token1();

        pair._safeTransferFrom(msg.sender, pair, amount);
        (uint256 token0amount, uint256 token1amount) = IUniswapV2Minimal(pair).burn(address(this));

        IERC20minimal(token0).approve(address(helios), token0amount);
        IERC20minimal(token1).approve(address(helios), token1amount);

        liq = helios.addLiquidity(to, id, token0amount, token1amount, '');
    }
}

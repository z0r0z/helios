// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.4;

import './ERC1155.sol';
import './libraries/SafeTransferLib.sol';
import './utils/Multicall.sol';
import './interfaces/IPairSwap.sol';

/// @notice Extensible 1155-based exchange for liquidity pairs
contract Helios is ERC1155, Multicall {
    /// -----------------------------------------------------------------------
    /// Library usage
    /// -----------------------------------------------------------------------

    using SafeTransferLib for address;

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event PairCreated(address indexed to, address token0, address token1, uint256 indexed id);
    event LiquidityAdded(address indexed to, uint256 indexed id, uint256 token0amount, uint256 token1amount);
    event LiquidityRemoved(address indexed from, uint256 indexed id, uint256 amount0out, uint256 amount1out);
    event Swapped(address indexed to, uint256 indexed id, address tokenIn, uint256 amountIn, uint256 amountOut);

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error IdenticalTokens();
    error NoSwapper();
    error PairExists();
    error NoPair();
    error NoLiquidity();
    error NotPairToken();

    /// -----------------------------------------------------------------------
    /// LP Storage
    /// -----------------------------------------------------------------------

    /// @dev tracks new LP ids
    uint256 public totalSupply;
    /// @dev tracks LP amount per id
    mapping(uint256 => uint256) totalSupplyForId;
    /// @dev maps Helios LP to settings
    mapping(uint256 => Pair) public pairs;
    /// @dev internal mapping to check Helios LP settings
    mapping(address => mapping(address => mapping(address => mapping(uint256 => uint256)))) private pairSettings;

    struct Pair {
        address token0; // first pair token
        address token1; // second pair token
        address swapper; // pair output target
        uint112 reserve0; // first pair token reserve
        uint112 reserve1; // second pair token reserve
        uint8 fee; // fee back to pair liquidity providers
    }

    /// -----------------------------------------------------------------------
    /// LP Logic
    /// -----------------------------------------------------------------------

    /// @notice Create new Helios LP
    /// @param to The recipient of Helios liquidity
    /// @param tokenA The first asset in Helios LP (will be sorted)
    /// @param tokenB The second asset in Helios LP (will be sorted)
    /// @param tokenAamount The value deposited for tokenA
    /// @param tokenBamount The value deposited for tokenB
    /// @param swapper The contract that provides swapping logic for LP
    /// @param fee The designated LP fee
    /// @param data Bytecode provided for recipient of Helios liquidity
    /// @return id The Helios LP id in 1155 tracking
    /// @return liq The liquidity output from swapper
    function createPair(
        address to,
        address tokenA,
        address tokenB,
        uint112 tokenAamount,
        uint112 tokenBamount,
        address swapper,
        uint8 fee,
        bytes calldata data
    ) public payable virtual returns (uint256 id, uint256 liq) {
        if (tokenA == tokenB) revert IdenticalTokens();
        if (swapper == address(0) || swapper.code.length == 0) revert NoSwapper();

        // sort tokens and amounts
        (address token0, address token1) = (tokenA, tokenB);
        (uint112 token0amount, uint112 token1amount) = (tokenAamount, tokenBamount);
        
        if (tokenB > tokenA) {
            (token0, token1) = (tokenB, tokenA);
            (token0amount, token1amount) = (tokenBamount, tokenAamount);
        }

        if (pairSettings[token0][token1][swapper][fee] != 0) revert PairExists();

        // if ETH attached, overwrite token0 and token0amount
        if (msg.value != 0) {
            token0 = address(0);
            token0amount = uint112(msg.value);
            token1._safeTransferFrom(msg.sender, address(this), token1amount);
        } else {
            token0._safeTransferFrom(msg.sender, address(this), token0amount);
            token1._safeTransferFrom(msg.sender, address(this), token1amount);
        }

        id = ++totalSupply;
        
        pairSettings[token0][token1][swapper][fee] = id;

        pairs[id] = Pair({
            token0: token0,
            token1: token1,
            swapper: swapper,
            reserve0: token0amount,
            reserve1: token1amount,
            fee: fee
        });

        // swapper logic returns output liquidity
        liq = ISwap(swapper).addLiquidity(id, token0amount, token1amount);

        _mint(
            to,
            id,
            liq,
            data
        );

        totalSupplyForId[id] = liq;

        emit PairCreated(to, token0, token1, id);
    }

    /// @notice Add liquidity to Helios LP
    /// @param to The recipient of Helios liquidity
    /// @param id The Helios LP id in 1155 tracking
    /// @param token0amount The asset amount deposited for token0
    /// @param token1amount The asset amount deposited for token1
    /// @param data Bytecode provided for recipient of Helios liquidity
    /// @return liq The liquidity output from swapper
    function addLiquidity(
        address to,
        uint256 id, 
        uint256 token0amount,
        uint256 token1amount,
        bytes calldata data
    ) public payable virtual returns (uint256 liq) {
        if (id > totalSupply) revert NoPair();

        Pair storage pair = pairs[id];

        // if base is address(0), assume ETH and overwrite amount
        if (pair.token0 == address(0)) {
            token0amount = uint112(msg.value);
            pair.token1._safeTransferFrom(msg.sender, address(this), token1amount);
        } else { 
            pair.token0._safeTransferFrom(msg.sender, address(this), token0amount);
            pair.token1._safeTransferFrom(msg.sender, address(this), token1amount);
        }

        // swapper dictates output LP
        liq = ISwap(pair.swapper).addLiquidity(id, token0amount, token1amount);
        
        if (liq == 0) revert NoLiquidity();

        pair.reserve0 += uint112(token0amount);
        pair.reserve1 += uint112(token1amount);

        _mint(
            to,
            id,
            liq,
            data
        );

        totalSupplyForId[id] += liq;

        emit LiquidityAdded(to, id, token0amount, token1amount);
    }

    /// @notice Remove liquidity from Helios LP
    /// @param to The recipient of Helios outputs
    /// @param id The Helios LP id in 1155 tracking
    /// @param liq The liquidity amount to burn
    /// @return amount0out The value output for token0
    /// @return amount1out The value output for token1
    function removeLiquidity(
        address to, 
        uint256 id, 
        uint256 liq
    ) public payable virtual returns (uint256 amount0out, uint256 amount1out) {
        if (id > totalSupply) revert NoPair();

        Pair storage pair = pairs[id];

        _burn(
            msg.sender,
            id,
            liq
        );

        // swapper dictates output amounts
        (amount0out, amount1out) = ISwap(pair.swapper).removeLiquidity(id, liq);
        
        if (pair.token0 == address(0)) {
            to._safeTransferETH(amount0out);
        } else {
            pair.token0._safeTransfer(to, amount0out);
        }

        pair.token1._safeTransfer(to, amount1out);

        pair.reserve0 -= uint112(amount0out);
        pair.reserve1 -= uint112(amount1out);

        totalSupplyForId[id] -= liq;

        emit LiquidityRemoved(to, id, amount0out, amount1out);
    }

    /// -----------------------------------------------------------------------
    /// Swap Logic
    /// -----------------------------------------------------------------------

    /// @notice Swap against Helios LP
    /// @param to The recipient of Helios output
    /// @param id The Helios LP id in 1155 tracking
    /// @param tokenIn The asset to swap from
    /// @param amountIn The amount of asset to swap
    /// @param amountOut The Helios output from swap
    function swap(
        address to, 
        uint256 id, 
        address tokenIn, 
        uint256 amountIn
    ) public payable virtual returns (uint256 amountOut) {
        if (id > totalSupply) revert NoPair();

        Pair storage pair = pairs[id];

        if (tokenIn != pair.token0 && tokenIn != pair.token1) revert NotPairToken();
        
        if (tokenIn == address(0)) {
            amountIn = msg.value;
        } else {
            tokenIn._safeTransferFrom(msg.sender, address(this), amountIn);
        }

        amountOut = ISwap(pair.swapper).swap(id, tokenIn, amountIn);

        if (tokenIn == pair.token1) {
            if (pair.token0 == address(0)) {
                to._safeTransferETH(amountOut);
            } else {
                pair.token0._safeTransfer(to, amountOut);
            }

            pair.reserve0 -= uint112(amountOut);
            pair.reserve1 += uint112(amountIn);
        } else {
            pair.token1._safeTransfer(to, amountOut);

            pair.reserve0 += uint112(amountIn);
            pair.reserve1 -= uint112(amountOut);
        }

        emit Swapped(to, id, tokenIn, amountIn, amountOut);
    }
}
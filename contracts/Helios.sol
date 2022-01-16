// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.4;

import './ERC1155.sol';
import './libraries/SafeTransferLib.sol';
import './ISwap.sol';
import './utils/Multicall.sol';

/// @notice Multi-strategy multi-token exchange.
contract Helios is ERC1155, Multicall, ReentrancyGuard {
    using SafeTransferLib for address;

    /*///////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event PairCreated(address indexed to, address token0, address token1, uint256 indexed id);

    event LiquidityAdded(address indexed to, uint256 indexed id, uint256 token0amount, uint256 token1amount);

    event LiquidityRemoved(address indexed from, uint256 indexed id, uint256 amount0out, uint256 amount1out);

    event Swapped(address indexed to, uint256 indexed id, address tokenIn, uint256 amountIn, uint256 amountOut);

    /*///////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    error Locked();
    
    error IdenticalTokens();

    error NullStrategy();

    error PairExists();

    error NoPair();

    error NoLiquidity();

    error NotPairToken();

    /*///////////////////////////////////////////////////////////////
                            SWAP STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev tracks new LP ids
    uint256 public totalSupply;

    mapping(address => mapping(address => mapping(address => mapping(uint256 => uint256)))) public pairSettings;

    mapping(uint256 => Pair) pairs;

    struct Pair {
        address token0;
        address token1;
        address swapStrategy;
        uint112 reserve0;
        uint112 reserve1;
        uint256 fee;
    }

    /*///////////////////////////////////////////////////////////////
                            SWAP LOGIC
    //////////////////////////////////////////////////////////////*/

    function createPair(
        address to,
        address tokenA,
        address tokenB,
        uint256 tokenAamount,
        uint256 tokenBamount,
        address swapStrategy,
        uint256 fee,
        bytes calldata data
    ) public payable nonReentrant virtual returns (uint256 id, uint256 lp) {
        if (tokenA == tokenB) revert IdenticalTokens();

        if (swapStrategy == address(0)) revert NullStrategy();

        // sort tokens and amounts
        (address token0, address token1) = (tokenA, tokenB);
        (uint256 token0amount, uint256 token1amount) = (tokenAamount, tokenBamount);

        if (tokenB > tokenA){
            (token0, token1) = (tokenB, tokenA);
            (token0amount, token1amount) = (tokenBamount, tokenAamount);
        }

        if (pairSettings[token0][token1][swapStrategy][fee] != 0) revert PairExists();

        // if ETH attached, overwrite token0 and token0amount
        if (msg.value != 0) {
            token0 = address(0);

            token0amount = uint112(msg.value);

            token1._safeTransferFrom(msg.sender, address(this), token1amount);
        } else {
            token0._safeTransferFrom(msg.sender, address(this), token0amount);

            token1._safeTransferFrom(msg.sender, address(this), token1amount);
        }

        id = totalSupply++;

        pairSettings[token0][token1][swapStrategy][fee] = id;

        pairs[id] = Pair({
            token0: token0,
            token1: token1,
            swapStrategy: swapStrategy,
            reserve0: uint112(token0amount),
            reserve1: uint112(token1amount),
            fee: fee
        });

        // strategy dictates output LP
        lp = ISwap(swapStrategy).addLiquidity(id, token0amount, token1amount);

        _mint(
            to,
            id,
            lp,
            data
        );

        emit PairCreated(to, token0, token1, id);
    }

    function addLiquidity(
        address to,
        uint256 id, 
        uint256 token0amount,
        uint256 token1amount,
        bytes calldata data
    ) public payable nonReentrant virtual returns (uint256 lp) {
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

        // strategy dictates output LP
        lp = ISwap(pair.swapStrategy).addLiquidity(id, token0amount, token1amount);
        
        if (lp == 0) revert NoLiquidity();

        pair.reserve0 += uint112(token0amount);

        pair.reserve1 += uint112(token1amount);

        _mint(
            to,
            id,
            lp,
            data
        );

        emit LiquidityAdded(to, id, token0amount, token1amount);
    }

    function removeLiquidity(address to, uint256 id, uint256 lp) public payable nonReentrant virtual returns (
        uint256 amount0out, uint256 amount1out
    ) {
        if (id > totalSupply) revert NoPair();

        Pair storage pair = pairs[id];

        _burn(
            msg.sender,
            id,
            lp
        );

        // strategy dictates output amounts
        (amount0out, amount1out) = ISwap(pair.swapStrategy).removeLiquidity(id, lp);
        
        if (pair.token0 == address(0)) {
            to._safeTransferETH(amount0out);
        } else {
            pair.token0._safeTransfer(to, amount0out);
        }

        pair.token1._safeTransfer(to, amount1out);

        pair.reserve0 -= uint112(amount0out);

        pair.reserve1 -= uint112(amount1out);

        emit LiquidityRemoved(to, id, amount0out, amount1out);
    }

    function swap(
        address to, 
        uint256 id, 
        address tokenIn, 
        uint256 amountIn
    ) public payable nonReentrant virtual returns (uint256 amountOut) {
        if (id > totalSupply) revert NoPair();

        Pair storage pair = pairs[id];

        if (tokenIn != pair.token0 && tokenIn != pair.token1) revert NotPairToken();

        if (tokenIn == address(0)) {
            amountIn = msg.value;
        } else {
            tokenIn._safeTransferFrom(msg.sender, address(this), amountIn);
        }

        amountOut = ISwap(pair.swapStrategy).swap(id, tokenIn, amountIn);

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

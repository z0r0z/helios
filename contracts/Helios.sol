// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import './ERC1155.sol';
import './libraries/SafeTransferLib.sol';
import './ISwap.sol';

/// @notice Multi-strategy multi-token exchange.
contract Helios is ERC1155 {
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

    error Forbidden();

    /*///////////////////////////////////////////////////////////////
                            SWAP STORAGE
    //////////////////////////////////////////////////////////////*/

    address public feeTo;
    
    address public feeToSetter;

    /// @dev tracks new LP ids
    uint256 public totalSupply;

    uint256 internal unlocked = 1;

    mapping(address => mapping(address => mapping(address => mapping(uint256 => uint256)))) public pairSettings;

    mapping(uint256 => Pair) pairs;

    struct Pair {
        address token0;
        address token1;
        address swapStrategy;
        uint256 fee;
    }

    /*///////////////////////////////////////////////////////////////
                            SWAP LOGIC
    //////////////////////////////////////////////////////////////*/

    modifier lock() {
        if (unlocked == 2) revert Locked();

        unlocked = 2;

        _;

        unlocked = 1;
    }

    function createPair(
        address to,
        address tokenA, 
        address tokenB, 
        uint256 token0amount,
        uint256 token1amount,
        address swapStrategy, 
        uint256 fee,
        bytes calldata data
    ) external payable lock returns (uint256 id, uint256 lp) {
        if (tokenA == tokenB) revert IdenticalTokens();

        if (swapStrategy == address(0)) revert NullStrategy();

        // sort tokens
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        if (pairSettings[token0][token1][swapStrategy][fee] != 0) revert PairExists();

        totalSupply++;

        id = totalSupply;

        pairSettings[token0][token1][swapStrategy][fee] = id;

        pairs[id] = Pair({
            token0: token0,
            token1: token1,
            swapStrategy: swapStrategy,
            fee: fee
        });

        // if base is address(0), assume ETH and overwrite amount
        if (token0 == address(0)) token0amount = msg.value;

        // strategy dictates output LP
        lp = ISwap(swapStrategy).addLiquidity(token0amount, token1amount);

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
    ) external payable lock returns (uint256 lp) {
        if (id > totalSupply) revert NoPair();

        Pair storage pair = pairs[id];

        // if base is address(0), assume ETH and overwrite amount
        if (pair.token0 == address(0)) token0amount = msg.value;

        pair.token1._safeTransferFrom(msg.sender, address(this), token1amount);

        // strategy dictates output LP
        lp = ISwap(pair.swapStrategy).addLiquidity(token0amount, token1amount);
        
        if (lp == 0) revert NoLiquidity();

        _mint(
            to,
            id,
            lp,
            data
        );

        emit LiquidityAdded(to, id, token0amount, token1amount);
    }

    function removeLiquidity(address to, uint256 id, uint256 lp) external payable lock returns (
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
        (amount0out, amount1out) = ISwap(pair.swapStrategy).removeLiquidity(lp);
        
        if (pair.token0 == address(0)) {
            to._safeTransferETH(amount0out);
        } else {
            pair.token0._safeTransfer(to, amount0out);
        }

        pair.token1._safeTransfer(to, amount1out);

        emit LiquidityRemoved(to, id, amount0out, amount1out);
    }

    function swap(
        address to, 
        uint256 id, 
        address tokenIn, 
        uint256 amountIn
    ) external payable lock returns (uint256 amountOut) {
        if (id > totalSupply) revert NoPair();

        Pair storage pair = pairs[id];

        if (tokenIn == address(0)) {
            amountIn = msg.value;
        } else {
            tokenIn._safeTransferFrom(msg.sender, address(this), amountIn);
        }

        amountOut = ISwap(pair.swapStrategy).swap(tokenIn, amountIn);

        emit Swapped(to, id, tokenIn, amountIn, amountOut);
    }

    /*///////////////////////////////////////////////////////////////
                            MGMT LOGIC
    //////////////////////////////////////////////////////////////*/

    function setFeeTo(address feeTo_) external {
        if (msg.sender != feeToSetter) revert Forbidden();

        feeTo = feeTo_;
    }

    function setFeeToSetter(address feeToSetter_) external {
        if (msg.sender != feeToSetter) revert Forbidden();

        feeToSetter = feeToSetter_;
    }
}

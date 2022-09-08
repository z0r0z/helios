// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4;

import {ERC1155 as SolmateERC1155} from "@solmate/tokens/ERC1155.sol";
import {ERC20, SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {Multicall} from './utils/Multicall.sol';
import {IHelios} from './interfaces/IHelios.sol';

/// @notice Extensible 1155-based vault with router and liquidity pairing
/// @author z0r0z.eth
contract Helios is SolmateERC1155, Multicall {
    /// -----------------------------------------------------------------------
    /// Library usage
    /// -----------------------------------------------------------------------

    using SafeTransferLib for address;
    using SafeTransferLib for ERC20;

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event PairCreated(address indexed to, uint256 id, ERC20 indexed token0, ERC20 indexed token1);
    event LiquidityAdded(address indexed to, uint256 id, uint256 token0amount, uint256 token1amount);
    event LiquidityRemoved(address indexed from, uint256 id, uint256 amount0out, uint256 amount1out);
    event Swapped(address indexed to, uint256 id, ERC20 indexed tokenIn, uint256 amountIn, uint256 amountOut);

    /// -----------------------------------------------------------------------
    /// Metadata/URI logic
    /// -----------------------------------------------------------------------

    string public constant name = "Helios";
    string public constant symbol = "HELI";

    function uri(uint256) public override pure returns (string memory) {
        return "PLACEHOLDER";
    }

    /// -----------------------------------------------------------------------
    /// LP Storage
    /// -----------------------------------------------------------------------

    /// @dev tracks new LP ids
    uint256 public totalSupply;
    /// @dev tracks LP amount per id
    mapping(uint256 => uint256) public totalSupplyForId;
    /// @dev maps Helios LP to settings
    mapping(uint256 => Pair) public pairs;
    /// @dev internal mapping to check Helios LP settings
    mapping(ERC20 => mapping(ERC20 => mapping(IHelios => mapping(uint256 => uint256)))) private pairSettings;

    struct Pair {
        ERC20 token0; // first pair token
        ERC20 token1; // second pair token
        IHelios swapper; // pair output target
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
        ERC20 tokenA,
        ERC20 tokenB,
        uint256 tokenAamount,
        uint256 tokenBamount,
        IHelios swapper,
        uint8 fee,
        bytes calldata data
    ) external payable returns (uint256 id, uint256 liq) {
        require(tokenA != tokenB, "Helios: IDENTICAL_ADDRESSES");
        require(address(swapper).code.length != 0, "Helios: INVALID_SWAPPER");

        // sort tokens and amounts
        (ERC20 token0, uint112 token0amount, ERC20 token1, uint112 token1amount) = 
            tokenA < tokenB ? (tokenA, uint112(tokenAamount), tokenB, uint112(tokenBamount)) : 
                (tokenB, uint112(tokenBamount), tokenA, uint112(tokenAamount));

        require(pairSettings[token0][token1][swapper][fee] == 0, "Helios: PAIR_EXISTS");

        // if null included or msg.value, assume ETH pairing
        if (address(token0) == address(0) || msg.value != 0) {
            // overwrite token0 with null if not so
            if (address(token0) != address(0)) token0 = ERC20(address(0));
            // overwrite token0amount with value
            token0amount = uint112(msg.value);
            token1.safeTransferFrom(msg.sender, address(this), token1amount);
        } else {
            token0.safeTransferFrom(msg.sender, address(this), token0amount);
            token1.safeTransferFrom(msg.sender, address(this), token1amount);
        }

        // incrementing supply won't overflow on human timescales
        unchecked {
            id = ++totalSupply;
        }
        
        pairSettings[token0][token1][swapper][fee] = id;

        pairs[id] = Pair({
            token0: token0,
            token1: token1,
            swapper: swapper,
            reserve0: token0amount,
            reserve1: token1amount,
            fee: fee
        });

        // swapper dictates output LP
        liq = swapper.addLiquidity(id, token0amount, token1amount);

        //_mint(
        //    to,
        //    id,
        //    liq,
        //    data
        //);

        totalSupplyForId[id] = liq;

        //emit PairCreated(to, id, token0, token1);
        emit LiquidityAdded(to, id, token0amount, token1amount);
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
    ) external payable returns (uint256 liq) {
        require(id <= totalSupply, "Helios: PAIR_DOESNT_EXIST");

        Pair storage pair = pairs[id];

        // if base is address(0), assume ETH and overwrite amount
        if (address(pair.token0) == address(0)) {
            token0amount = msg.value;
            pair.token1.safeTransferFrom(msg.sender, address(this), token1amount);
        } else { 
            pair.token0.safeTransferFrom(msg.sender, address(this), token0amount);
            pair.token1.safeTransferFrom(msg.sender, address(this), token1amount);
        }

        // swapper dictates output LP
        liq = pair.swapper.addLiquidity(id, token0amount, token1amount);
        
        require(liq != 0, "Helios: INSUFFICIENT_LIQUIDITY_MINTED");
        
        _mint(
            to,
            id,
            liq,
            data
        );

        pair.reserve0 += uint112(token0amount);
        pair.reserve1 += uint112(token1amount);

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
    ) external payable returns (uint256 amount0out, uint256 amount1out) {
        require(id <= totalSupply, "Helios: PAIR_DOESNT_EXIST");

        Pair storage pair = pairs[id];
        
        // swapper dictates output amounts
        (amount0out, amount1out) = pair.swapper.removeLiquidity(id, liq);
        
        if (address(pair.token0) == address(0)) {
            to.safeTransferETH(amount0out);
        } else {
            pair.token0.safeTransfer(to, amount0out);
        }

        pair.token1.safeTransfer(to, amount1out);
        
        _burn(
            msg.sender,
            id,
            liq
        );

        pair.reserve0 -= uint112(amount0out);
        pair.reserve1 -= uint112(amount1out);
        
        // underflow is checked in HeliosERC1155 by balanceOf decrement
        unchecked {
            totalSupplyForId[id] -= liq;
        }

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
    /// @return amountOut The Helios output from swap
    function swap(
        address to, 
        uint256 id, 
        ERC20 tokenIn, 
        uint256 amountIn
    ) external payable returns (uint256 amountOut) {
        require(id <= totalSupply, "Helios: PAIR_DOESNT_EXIST");

        Pair storage pair = pairs[id];

        require(tokenIn == pair.token0 || tokenIn == pair.token1, "Helios: NOT_PAIR_TOKEN");
        
        if (address(tokenIn) == address(0)) {
            amountIn = msg.value;
        } else {
            tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);
        }

        // swapper dictates output amount
        amountOut = pair.swapper.swap(id, address(tokenIn), amountIn);

        if (tokenIn == pair.token1) {
            if (address(pair.token0) == address(0)) {
                to.safeTransferETH(amountOut);
            } else {
                pair.token0.safeTransfer(to, amountOut);
            }

            pair.reserve0 -= uint112(amountOut);
            pair.reserve1 += uint112(amountIn);
        } else {
            pair.token1.safeTransfer(to, amountOut);

            pair.reserve0 += uint112(amountIn);
            pair.reserve1 -= uint112(amountOut);
        }

        emit Swapped(to, id, tokenIn, amountIn, amountOut);
    }

    /// @notice Update reserves of Helios LP
    /// @param to The recipient, only used for logging events
    /// @param id The Helios LP id in 1155 tracking
    /// @param tokenIn The asset to swap from
    /// @param amountIn The amount of asset to swap
    /// @return tokenOut The asset to swap to
    /// @return amountOut The Helios output from swap
    function _updateReserves(address to, uint256 id, ERC20 tokenIn, uint256 amountIn)
        internal
        returns (ERC20 tokenOut, uint256 amountOut)
    {
        require(id <= totalSupply, "Helios: PAIR_DOESNT_EXIST");

        Pair storage pair = pairs[id];

        require(tokenIn == pair.token0 || tokenIn == pair.token1, "Helios: NOT_PAIR_TOKEN");

        // swapper dictates output amount
        amountOut = pair.swapper.swap(id, address(tokenIn), amountIn);

        if (tokenIn == pair.token1) {
            tokenOut = pair.token0;
            pair.reserve0 -= uint112(amountOut);
            pair.reserve1 += uint112(amountIn);
        } else {
            tokenOut = pair.token1;
            pair.reserve0 += uint112(amountIn);
            pair.reserve1 -= uint112(amountOut);
        }

        emit Swapped(to, id, tokenIn, amountIn, amountOut);
    }

    /// @notice Swap against Helios LP
    /// @param to The recipient of Helios output
    /// @param ids Array of Helios LP ids in 1155 tracking
    /// @param tokenIn The asset to swap from
    /// @param amountIn The amount of asset to swap
    /// @return amountOut The Helios output from swap
    function swap(address to, uint256[] calldata ids, ERC20 tokenIn, uint256 amountIn)
        external
        payable
        returns (uint256 amountOut)
    {
        if (address(tokenIn) == address(0)) {
            amountIn = msg.value;
        } else {
            tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);
        }

        uint256 len = ids.length;
        //These will be overwritten by the loop
        amountOut = amountIn;
        ERC20 tokenOut = tokenIn;
        for (uint256 i = 0; i < len;) {
            (tokenOut, amountOut) = _updateReserves(to, ids[i], tokenOut, amountOut);
            unchecked {
                ++i;
            }
        }

        if (address(tokenOut) == address(0)) {
            to.safeTransferETH(amountOut);
        } else {
            tokenOut.safeTransfer(to, amountOut);
        }
    }
}

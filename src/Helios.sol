// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {IHelios} from "./interfaces/IHelios.sol";
import {OwnedThreeStep} from "@solbase/auth/OwnedThreeStep.sol";
import {SafeTransferLib} from "@solbase/utils/SafeTransferLib.sol";
import {SafeMulticallable} from "@solbase/utils/SafeMulticallable.sol";
import {ERC1155, ERC1155TokenReceiver} from "@solbase/tokens/ERC1155.sol";

/// @notice ERC1155 vault with router and liquidity pools.
/// @author z0r0z.eth (SolDAO)
contract Helios is
    OwnedThreeStep(tx.origin),
    SafeMulticallable,
    ERC1155,
    ERC1155TokenReceiver
{
    constructor() payable {} // Clean deployment.

    /// -----------------------------------------------------------------------
    /// Library Usage
    /// -----------------------------------------------------------------------

    using SafeTransferLib for address;

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event CreatePair(
        address indexed to,
        uint256 id,
        address indexed token0,
        address indexed token1
    );

    event AddLiquidity(
        address indexed to,
        uint256 id,
        uint256 token0amount,
        uint256 token1amount
    );

    event RemoveLiquidity(
        address indexed from,
        uint256 id,
        uint256 amount0out,
        uint256 amount1out
    );

    event Swap(
        address indexed to,
        uint256 id,
        address indexed tokenIn,
        uint256 amountIn,
        uint256 amountOut
    );

    event SetURIfetcher(ERC1155 indexed uriFetcher);

    /// -----------------------------------------------------------------------
    /// Metadata/URI Logic
    /// -----------------------------------------------------------------------

    ERC1155 internal uriFetcher;

    string public constant name = "Helios";

    string public constant symbol = "HELI";

    function uri(uint256 id) public view override returns (string memory) {
        return uriFetcher.uri(id);
    }

    function setURIfetcher(ERC1155 _uriFetcher) public payable onlyOwner {
        uriFetcher = _uriFetcher;

        emit SetURIfetcher(_uriFetcher);
    }

    /// -----------------------------------------------------------------------
    /// LP Storage
    /// -----------------------------------------------------------------------

    /// @dev Tracks new LP ids.
    uint256 public totalSupply;

    /// @dev Tracks LP amount per id.
    mapping(uint256 => uint256) public totalSupplyForId;

    /// @dev Maps Helios LP to settings.
    mapping(uint256 => Pair) public pairs;

    /// @dev Internal mapping to check Helios LP settings.
    mapping(address => mapping(address => mapping(IHelios => mapping(uint256 => uint256))))
        internal pairSettings;

    struct Pair {
        address token0; // First pair token.
        address token1; // Second pair token.
        IHelios swapper; // Pair output target.
        uint112 reserve0; // First pair token reserve.
        uint112 reserve1; // Second pair token reserve.
        uint8 fee; // Fee back to pair liquidity providers.
    }

    /// -----------------------------------------------------------------------
    /// LP Logic
    /// -----------------------------------------------------------------------

    /// @notice Create new Helios LP.
    /// @param to The recipient of Helios liquidity.
    /// @param tokenA The first asset in Helios LP (will be sorted).
    /// @param tokenB The second asset in Helios LP (will be sorted).
    /// @param tokenAamount The value deposited for tokenA.
    /// @param tokenBamount The value deposited for tokenB.
    /// @param swapper The contract that provides swapping logic for LP.
    /// @param fee The designated LP fee.
    /// @param data Bytecode provided for recipient of Helios liquidity.
    /// @return id The Helios LP id in 1155 tracking.
    /// @return liq The liquidity output from swapper.
    function createPair(
        address to,
        address tokenA,
        address tokenB,
        uint256 tokenAamount,
        uint256 tokenBamount,
        IHelios swapper,
        uint8 fee,
        bytes calldata data
    ) external payable returns (uint256 id, uint256 liq) {
        require(tokenA != tokenB, "Helios: IDENTICAL_ADDRESSES");

        require(address(swapper).code.length != 0, "Helios: INVALID_SWAPPER");

        // Sort tokens and amounts.
        (
            address token0,
            uint112 token0amount,
            address token1,
            uint112 token1amount
        ) = tokenA < tokenB
                ? (tokenA, uint112(tokenAamount), tokenB, uint112(tokenBamount))
                : (
                    tokenB,
                    uint112(tokenBamount),
                    tokenA,
                    uint112(tokenAamount)
                );

        require(
            pairSettings[token0][token1][swapper][fee] == 0,
            "Helios: PAIR_EXISTS"
        );

        // If null included or `msg.value`, assume native token pairing.
        if (address(token0) == address(0) || msg.value != 0) {
            // Overwrite token0 with null if not so.
            if (token0 != address(0)) token0 = address(0);

            // Overwrite token0amount with value.
            token0amount = uint112(msg.value);

            token1.safeTransferFrom(msg.sender, address(this), token1amount);
        } else {
            token0.safeTransferFrom(msg.sender, address(this), token0amount);

            token1.safeTransferFrom(msg.sender, address(this), token1amount);
        }

        // Unchecked because the only math done is incrementing
        // `totalSupply()` which cannot realistically overflow.
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

        // Swapper dictates output LP.
        liq = swapper.addLiquidity(id, token0amount, token1amount);

        _mint(to, id, liq, data);

        totalSupplyForId[id] = liq;

        emit CreatePair(to, id, token0, token1);

        emit AddLiquidity(to, id, token0amount, token1amount);
    }

    /// @notice Add liquidity to Helios LP.
    /// @param to The recipient of Helios liquidity.
    /// @param id The Helios LP id in 1155 tracking.
    /// @param token0amount The asset amount deposited for token0.
    /// @param token1amount The asset amount deposited for token1.
    /// @param data Bytecode provided for recipient of Helios liquidity.
    /// @return liq The liquidity output from swapper.
    function addLiquidity(
        address to,
        uint256 id,
        uint256 token0amount,
        uint256 token1amount,
        bytes calldata data
    ) external payable returns (uint256 liq) {
        require(id <= totalSupply, "Helios: PAIR_DOESNT_EXIST");

        Pair storage pair = pairs[id];

        // If base is address(0), assume native token and overwrite amount.
        if (pair.token0 == address(0)) {
            token0amount = msg.value;

            pair.token1.safeTransferFrom(
                msg.sender,
                address(this),
                token1amount
            );
        } else {
            pair.token0.safeTransferFrom(
                msg.sender,
                address(this),
                token0amount
            );

            pair.token1.safeTransferFrom(
                msg.sender,
                address(this),
                token1amount
            );
        }

        // Swapper dictates output LP.
        liq = pair.swapper.addLiquidity(id, token0amount, token1amount);

        require(liq != 0, "Helios: INSUFFICIENT_LIQUIDITY_MINTED");

        _mint(to, id, liq, data);

        pair.reserve0 += uint112(token0amount);

        pair.reserve1 += uint112(token1amount);

        totalSupplyForId[id] += liq;

        emit AddLiquidity(to, id, token0amount, token1amount);
    }

    /// @notice Remove liquidity from Helios LP.
    /// @param to The recipient of Helios outputs.
    /// @param id The Helios LP id in 1155 tracking.
    /// @param liq The liquidity amount to burn.
    /// @return amount0out The value output for token0.
    /// @return amount1out The value output for token1.
    function removeLiquidity(
        address to,
        uint256 id,
        uint256 liq
    ) external payable returns (uint256 amount0out, uint256 amount1out) {
        require(id <= totalSupply, "Helios: PAIR_DOESNT_EXIST");

        Pair storage pair = pairs[id];

        // Swapper dictates output amounts.
        (amount0out, amount1out) = pair.swapper.removeLiquidity(id, liq);

        // If base is address(0), assume native token.
        if (pair.token0 == address(0)) {
            to.safeTransferETH(amount0out);
        } else {
            pair.token0.safeTransfer(to, amount0out);
        }

        pair.token1.safeTransfer(to, amount1out);

        _burn(msg.sender, id, liq);

        pair.reserve0 -= uint112(amount0out);

        pair.reserve1 -= uint112(amount1out);

        // Underflow is checked in {ERC1155} by `balanceOf()` decrement.
        unchecked {
            totalSupplyForId[id] -= liq;
        }

        emit RemoveLiquidity(to, id, amount0out, amount1out);
    }

    /// -----------------------------------------------------------------------
    /// Swap Logic
    /// -----------------------------------------------------------------------

    /// @notice Swap against Helios LP.
    /// @param to The recipient of Helios output.
    /// @param id The Helios LP id in 1155 tracking.
    /// @param tokenIn The asset to swap from.
    /// @param amountIn The amount of asset to swap.
    /// @return amountOut The Helios output from swap.
    function swap(
        address to,
        uint256 id,
        address tokenIn,
        uint256 amountIn
    ) external payable returns (uint256 amountOut) {
        require(id <= totalSupply, "Helios: PAIR_DOESNT_EXIST");

        Pair storage pair = pairs[id];

        require(
            tokenIn == pair.token0 || tokenIn == pair.token1,
            "Helios: NOT_PAIR_TOKEN"
        );

        // If `tokenIn` is address(0), assume native token.
        if (tokenIn == address(0)) {
            amountIn = msg.value;
        } else {
            tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);
        }

        // Swapper dictates output amount.
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

        emit Swap(to, id, tokenIn, amountIn, amountOut);
    }

    /// @notice Update reserves of Helios LP.
    /// @param to The recipient, only used for logging events.
    /// @param id The Helios LP id in 1155 tracking.
    /// @param tokenIn The asset to swap from.
    /// @param amountIn The amount of asset to swap.
    /// @return tokenOut The asset to swap to.
    /// @return amountOut The Helios output from swap.
    function _updateReserves(
        address to,
        uint256 id,
        address tokenIn,
        uint256 amountIn
    ) internal returns (address tokenOut, uint256 amountOut) {
        require(id <= totalSupply, "Helios: PAIR_DOESNT_EXIST");

        Pair storage pair = pairs[id];

        require(
            tokenIn == pair.token0 || tokenIn == pair.token1,
            "Helios: NOT_PAIR_TOKEN"
        );

        // Swapper dictates output amount.
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

        emit Swap(to, id, tokenIn, amountIn, amountOut);
    }

    /// @notice Swap against Helios LP.
    /// @param to The recipient of Helios output.
    /// @param ids Array of Helios LP ids in 1155 tracking.
    /// @param tokenIn The asset to swap from.
    /// @param amountIn The amount of asset to swap.
    /// @return amountOut The Helios output from swap.
    function swap(
        address to,
        uint256[] calldata ids,
        address tokenIn,
        uint256 amountIn
    ) external payable returns (uint256 amountOut) {
        if (address(tokenIn) == address(0)) {
            amountIn = msg.value;
        } else {
            tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);
        }

        uint256 len = ids.length;

        // These will be overwritten by the loop.
        amountOut = amountIn;

        address tokenOut = tokenIn;

        for (uint256 i; i < len; ) {
            (tokenOut, amountOut) = _updateReserves(
                to,
                ids[i],
                tokenOut,
                amountOut
            );

            // Unchecked because the only math done is incrementing
            // the array index counter which cannot possibly overflow.
            unchecked {
                ++i;
            }
        }

        if (tokenOut == address(0)) {
            to.safeTransferETH(amountOut);
        } else {
            tokenOut.safeTransfer(to, amountOut);
        }
    }
}

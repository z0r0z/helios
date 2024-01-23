// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import {Math2} from "./libraries/Math2.sol";
import {ERC6909} from "./utils/ERC6909.sol";
import {ReentrancyGuard} from "./utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";

/// @notice Simple xyk-style exchange for ERC20 tokens.
/// LP shares are tokenized using the ERC6909 interface.
/// @author Modified from Uniswap V2
/// (https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol)
contract Helios is ERC6909, ReentrancyGuard {
    /// ========================= LIBRARIES ========================= ///

    /// @dev Did the maths.
    using Math2 for uint224;

    /// @dev Safety library for ERC20.
    using SafeTransferLib for address;

    /// ======================= CUSTOM ERRORS ======================= ///

    /// @dev Not enough liquidity minted.
    error InsufficientLiquidityMinted();

    /// @dev Not enough liquidity burned.
    error InsufficientLiquidityBurned();

    /// @dev Not enough tokens sent out.
    error InsufficientOutputAmount();

    /// @dev Not enough tokens sent in.
    error InsufficientInputAmount();

    /// @dev Not enough liquidity.
    error InsufficientLiquidity();

    /// @dev Invalid recipient.
    error InvalidTo();

    /// @dev Bad math.
    error Overflow();

    /// @dev K.
    error K();

    /// =========================== EVENTS =========================== ///

    /// @dev Logs swap of tokens within the ERC6909 token ID.
    event Swap(
        uint256 indexed id,
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );

    /// @dev Logs update of reserves within the ERC6909 token ID.
    event Sync(uint256 id, uint112 reserve0, uint112 reserve1);

    /// ========================= CONSTANTS ========================= ///

    /// @dev Minimum liquidity to start pool.
    uint256 internal constant MIN_LIQ = 1000;

    /// ========================= IMMUTABLES ========================= ///

    /// @dev Helios Singleton DAO.
    address internal immutable DAO;

    /// ========================== STORAGE ========================== ///

    /// @dev Pool swapping data mapping.
    mapping(uint256 id => Pool) public pools;

    /// @dev Pool cumulative price mapping.
    mapping(uint256 id => Price) public prices;

    /// ========================== STRUCTS ========================== ///

    /// @dev Pool data.
    struct Pool {
        address token0;
        address token1;
        uint112 reserve0;
        uint112 reserve1;
        uint32 blockTimestampLast;
    }

    /// @dev Price data.
    struct Price {
        uint256 price0CumulativeLast;
        uint256 price1CumulativeLast;
        uint256 kLast;
    }

    /// ======================== CONSTRUCTOR ======================== ///

    /// @dev Constructs
    /// this implementation.
    /// DAO is set to caller.
    constructor() payable {
        DAO = msg.sender;
    }

    /// ======================== MINT & BURN ======================== ///

    /// @dev This low-level function should be called from a contract which performs important safety checks.
    function mint(uint256 id, address to) public payable nonReentrant returns (uint256 liquidity) {
        Pool storage pool = pools[id];

        uint256 balance0 = pool.token0.balanceOf(address(this));
        uint256 balance1 = pool.token1.balanceOf(address(this));
        uint256 amount0 = balance0 - pool.reserve0;
        uint256 amount1 = balance1 - pool.reserve1;

        _mintFee(id, pool.reserve0, pool.reserve1);
        uint256 _totalSupply = totalSupply[id]; // Gas savings, must be defined here since `totalSupply` can update in `_mintFee`.
        if (_totalSupply == 0) {
            liquidity = Math2.sqrt((amount0 * amount1) - MIN_LIQ);
            _mint(address(0), id, MIN_LIQ); // Permanently lock the first `MIN_LIQ` tokens.
        } else {
            liquidity = Math2.min(
                (amount0 * _totalSupply) / pool.reserve0, (amount1 * _totalSupply) / pool.reserve1
            );
        }
        if (liquidity == 0) revert InsufficientLiquidityMinted();
        _mint(to, id, liquidity);

        _update(id, balance0, balance1, pool.reserve0, pool.reserve1);
        prices[id].kLast = uint256(pool.reserve0) * (pool.reserve1); // `reserve0` and `reserve1` are up-to-date.
    }

    /// @dev This low-level function should be called from a contract which performs important safety checks.
    function burn(uint256 id, address to)
        public
        payable
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        Pool storage pool = pools[id];

        uint256 balance0 = pool.token0.balanceOf(address(this));
        uint256 balance1 = pool.token1.balanceOf(address(this));
        uint256 liquidity = balanceOf[address(this)][id];

        _mintFee(id, pool.reserve0, pool.reserve1);
        uint256 _totalSupply = totalSupply[id]; // Gas savings, must be defined here since totalSupply can update in `_mintFee`.
        amount0 = liquidity * balance0 / _totalSupply; // Using balances ensures pro-rata distribution.
        amount1 = liquidity * balance1 / _totalSupply; // Using balances ensures pro-rata distribution.
        if (amount0 == 0 || amount1 == 0) revert InsufficientLiquidityBurned();
        _burn(address(this), liquidity, 0);
        pool.token0.safeTransfer(to, amount0);
        pool.token1.safeTransfer(to, amount1);
        balance0 = pool.token0.balanceOf(address(this));
        balance1 = pool.token1.balanceOf(address(this));

        _update(id, balance0, balance1, pool.reserve0, pool.reserve1);
        prices[id].kLast = uint256(pool.reserve0) * (pool.reserve1); // `reserve0` and `reserve1` are up-to-date.
    }

    /// ============================ SWAP ============================ ///

    /// @dev This low-level function should be called from a contract which performs important safety checks.
    function swap(
        uint256 id,
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) public payable nonReentrant {
        Pool storage pool = pools[id];

        if (!(to != pool.token0 && to != pool.token1)) revert InvalidTo();
        if (!(amount0Out != 0 || amount1Out != 0)) revert InsufficientOutputAmount();
        if (!(amount0Out < pool.reserve0 && amount1Out < pool.reserve1)) {
            revert InsufficientLiquidity();
        }

        if (amount0Out != 0) pool.token0.safeTransfer(to, amount0Out); // Optimistically transfer tokens.
        if (amount1Out != 0) pool.token1.safeTransfer(to, amount1Out); // Optimistically transfer tokens.
        if (data.length != 0) {
            ICall(to).call(msg.sender, amount0Out, amount1Out, data);
        }

        uint256 balance0 = pool.token0.balanceOf(address(this));
        uint256 balance1 = pool.token1.balanceOf(address(this));

        uint256 amount0In =
            balance0 > pool.reserve0 - amount0Out ? balance0 - (pool.reserve0 - amount0Out) : 0;
        uint256 amount1In =
            balance1 > pool.reserve1 - amount1Out ? balance1 - (pool.reserve1 - amount1Out) : 0;
        if (!(amount0In != 0 || amount1In != 0)) revert InsufficientInputAmount();
        uint256 balance0Adjusted = balance0 * 1000 - amount0In * 3;
        uint256 balance1Adjusted = balance1 * 1000 - amount1In * 3;
        if (
            !(
                balance0Adjusted * balance1Adjusted
                    >= uint256(pool.reserve0 * pool.reserve1 * 1000 ** 2)
            )
        ) revert K();
        _update(id, balance0, balance1, pool.reserve0, pool.reserve1);
        emit Swap(id, msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    /// @dev Force balances to match reserves.
    function skim(uint256 id, address to) public payable nonReentrant {
        Pool storage pool = pools[id];
        pool.token0.safeTransfer(to, pool.token0.balanceOf(address(this)) - pool.reserve0);
        pool.token1.safeTransfer(to, pool.token1.balanceOf(address(this)) - pool.reserve1);
    }

    /// @dev Force reserves to match balances.
    function sync(uint256 id) public payable nonReentrant {
        Pool storage pool = pools[id];
        _update(
            id,
            pool.token0.balanceOf(address(this)),
            pool.token1.balanceOf(address(this)),
            pool.reserve0,
            pool.reserve1
        );
    }

    /// ========================== INTERNAL ========================== ///

    /// @dev Update reserves and, on the first call per block, price accumulators.
    function _update(
        uint256 id,
        uint256 balance0,
        uint256 balance1,
        uint112 _reserve0,
        uint112 _reserve1
    ) internal {
        Pool storage pool = pools[id];
        Price storage price = prices[id];

        if (!(balance0 <= type(uint112).max && balance1 <= type(uint112).max)) revert Overflow();
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        unchecked {
            uint32 timeElapsed = blockTimestamp - pool.blockTimestampLast; // Overflow is desired.
            if (timeElapsed != 0) {
                if (_reserve0 != 0) {
                    if (_reserve1 != 0) {
                        // * Never overflows, and + overflow is desired.
                        price.price0CumulativeLast +=
                            uint256(Math2.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
                        price.price1CumulativeLast +=
                            uint256(Math2.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
                    }
                }
            }
        }
        pool.reserve0 = uint112(balance0);
        pool.reserve1 = uint112(balance1);
        pool.blockTimestampLast = blockTimestamp;
        emit Sync(id, pool.reserve0, pool.reserve1);
    }

    /// @dev Mint liquidity equivalent to 1/6th of the growth in sqrt(k).
    function _mintFee(uint256 id, uint112 reserve0, uint112 reserve1) internal {
        Price storage price = prices[id];
        if (price.kLast != 0) {
            uint256 rootK = Math2.sqrt(uint256(reserve0) * reserve1);
            uint256 rootKLast = Math2.sqrt(price.kLast);
            if (rootK > rootKLast) {
                uint256 numerator = totalSupply[id] * (rootK - rootKLast);
                uint256 denominator = rootK * 5 + rootKLast;
                uint256 liquidity = numerator / denominator;
                if (liquidity != 0) _mint(DAO, id, liquidity);
            }
        }
    }
}

/// @dev Simple external call interface for swaps.
/// @author Modified from Uniswap V2
/// (https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Callee.sol)
interface ICall {
    function call(address sender, uint256 amount0, uint256 amount1, bytes calldata data)
        external
        payable;
}

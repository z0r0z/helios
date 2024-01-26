# 𖤓 Helios
[![CI][ci-shield]][ci-url]
[![Solidity][solidity-shield]][solidity-ci-url]
> ERC-6909 Singleton Exchange

LPs are tracked under the [minimal multi-token interface](https://eips.ethereum.org/EIPS/eip-6909).

Swapping uses the Uniswap V2 *xyk* curve and some Sushiswap updates to the classic constant product pool.

Such as allowing single-sided LP. Otherwise, Helios also allows for swaps in ERC-1155 and ERC-6909 tokens.

[ci-shield]: https://img.shields.io/github/actions/workflow/status/z0r0z/helios/ci.yml?branch=main&label=build
[ci-url]: https://github.com/z0r0z/helios/actions/workflows/ci.yml

[solidity-shield]: https://img.shields.io/badge/solidity-%20%3C=0.8.24-black
[solidity-ci-url]: https://github.com/z0r0z/helios/actions/workflows/ci-all-via-ir.yml
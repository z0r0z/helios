// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.4;

/// @notice Babylonian method for computing square roots.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/utils/FixedPointMathLib.sol)
library SqrtMath {
    function sqrt(uint256 x) internal pure returns (uint256 z) {
        assembly {
            // start off with z at 1
            z := 1

            // used below to help find a nearby power of 2
            let y := x

            // find the lowest power of 2 that is at least sqrt(x)
            if iszero(lt(y, 0x100000000000000000000000000000000)) {
                y := shr(128, y) // like dividing by 2 ** 128
                z := shl(64, z)
            }
            if iszero(lt(y, 0x10000000000000000)) {
                y := shr(64, y) // like dividing by 2 ** 64
                z := shl(32, z)
            }
            if iszero(lt(y, 0x100000000)) {
                y := shr(32, y) // like dividing by 2 ** 32
                z := shl(16, z)
            }
            if iszero(lt(y, 0x10000)) {
                y := shr(16, y) // like dividing by 2 ** 16
                z := shl(8, z)
            }
            if iszero(lt(y, 0x100)) {
                y := shr(8, y) // like dividing by 2 ** 8
                z := shl(4, z)
            }
            if iszero(lt(y, 0x10)) {
                y := shr(4, y) // like dividing by 2 ** 4
                z := shl(2, z)
            }
            if iszero(lt(y, 0x8)) {
                // equivalent to 2 ** z
                z := shl(1, z)
            }

            // shifting right by 1 is like dividing by 2
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))

            // compute a rounded down version of z
            let zRoundDown := div(x, z)

            // if zRoundDown is smaller, use it
            if lt(zRoundDown, z) {
                z := zRoundDown
            }
        }
    }
}

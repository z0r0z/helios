// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.4;

/// @notice Babylonian method for computing square roots.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/utils/FixedPointMathLib.sol)
library SqrtMath {
    function sqrt(uint256 x) internal pure returns (uint256 result) {
        assembly {
            // if x is zero, just return 0
            if iszero(iszero(x)) {
                // start off with a result of 1
                result := 1

                // used below to help find a nearby power of 2
                let x2 := x

                // find the closest power of 2 that is at most x
                if iszero(lt(x2, 0x100000000000000000000000000000000)) {
                    x2 := shr(128, x2) // like dividing by 2^128
                    result := shl(64, result)
                }
                if iszero(lt(x2, 0x10000000000000000)) {
                    x2 := shr(64, x2) // like dividing by 2^64
                    result := shl(32, result)
                }
                if iszero(lt(x2, 0x100000000)) {
                    x2 := shr(32, x2) // like dividing by 2^32
                    result := shl(16, result)
                }
                if iszero(lt(x2, 0x10000)) {
                    x2 := shr(16, x2) // like dividing by 2^16
                    result := shl(8, result)
                }
                if iszero(lt(x2, 0x100)) {
                    x2 := shr(8, x2) // like dividing by 2^8
                    result := shl(4, result)
                }
                if iszero(lt(x2, 0x10)) {
                    x2 := shr(4, x2) // like dividing by 2^4
                    result := shl(2, result)
                }
                if iszero(lt(x2, 0x8)) {
                    result := shl(1, result)
                }

                // shifting right by 1 is like dividing by 2
                result := shr(1, add(result, div(x, result)))
                result := shr(1, add(result, div(x, result)))
                result := shr(1, add(result, div(x, result)))
                result := shr(1, add(result, div(x, result)))
                result := shr(1, add(result, div(x, result)))
                result := shr(1, add(result, div(x, result)))
                result := shr(1, add(result, div(x, result)))

                // compute a rounded down version of the result
                let roundedDownResult := div(x, result)

                // if the rounded down result is smaller, use it
                if gt(result, roundedDownResult) {
                    result := roundedDownResult
                }
            }
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.4;

/// @notice Babylonian method for computing square roots.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/utils/FixedPointMathLib.sol)
library SqrtMath {
    function sqrt(uint256 x) internal pure returns (uint256 result) {
        // square root of 0 is zero
        if (x == 0) return 0;

        // start off with a result of 1
        result = 1;

        // used below to help find a nearby power of 2
        uint256 x2 = x;

        // find the closest power of 2 that is at most x
        if (x2 >= 0x100000000000000000000000000000000) {
            x2 >>= 128; // like dividing by 2^128

            result <<= 64;
        }
        if (x2 >= 0x10000000000000000) {
            x2 >>= 64; // like dividing by 2^64

            result <<= 32;
        }
        if (x2 >= 0x100000000) {
            x2 >>= 32; // like dividing by 2^32

            result <<= 16;
        }
        if (x2 >= 0x10000) {
            x2 >>= 16; // like dividing by 2^16

            result <<= 8;
        }
        if (x2 >= 0x100) {
            x2 >>= 8; // like dividing by 2^8

            result <<= 4;
        }
        if (x2 >= 0x10) {
            x2 >>= 4; // like dividing by 2^4

            result <<= 2;
        }
        if (x2 >= 0x8) result <<= 1;

        unchecked {
            // shifting right by 1 is like dividing by 2
            result = (result + x / result) >> 1;

            result = (result + x / result) >> 1;

            result = (result + x / result) >> 1;

            result = (result + x / result) >> 1;

            result = (result + x / result) >> 1;

            result = (result + x / result) >> 1;
            
            result = (result + x / result) >> 1;

            // compute a rounded down version of the result
            uint256 roundedDownResult = x / result;

            // if the rounded down result is smaller, use it as the result
            if (result > roundedDownResult) result = roundedDownResult;
        }
    }
}

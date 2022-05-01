// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4;

/// @notice Gas optimized reentrancy protection for smart contracts
/// @author Modified from Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/utils/ReentrancyGuard.sol)
/// License-Identifier: AGPL-3.0-only
abstract contract ReentrancyGuard {
    error Reentrancy();
    
    uint256 private locked = 1;

    modifier nonReentrant() {
        if (locked != 1) revert Reentrancy();
        locked = 2;
        _;
        locked = 1;
    }
}

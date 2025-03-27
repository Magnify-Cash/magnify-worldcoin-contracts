// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract MockMagnifyWorldV3 {
    function getTotalBorrows() external pure returns (uint256) {
        return 1000;
    }

    function liquidity() external pure returns (uint256) {
        return 2000;
    }

    function getTotalDefaults() external pure returns (uint256) {
        return 100;
    }
}
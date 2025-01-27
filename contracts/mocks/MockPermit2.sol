// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MockPermit2 {
    function permitTransferFrom(
        bytes calldata /* permit */,
        bytes calldata /* transferDetails */,
        address /* owner */,
        bytes calldata /* signature */
    ) external pure {}
} 
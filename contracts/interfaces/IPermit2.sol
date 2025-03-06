// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ISignatureTransfer} from "./ISignatureTransfer.sol";

interface IPermit2 {
    function permitTransferFrom(
        ISignatureTransfer.PermitTransferFrom calldata permit,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes calldata signature
    ) external;
}

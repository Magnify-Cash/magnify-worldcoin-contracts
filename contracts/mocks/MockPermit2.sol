// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {IPermit2} from "../interfaces/IPermit2.sol";
import {ISignatureTransfer} from "../interfaces/ISignatureTransfer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockPermit2 is IPermit2 {
    function permitTransferFrom(
        ISignatureTransfer.PermitTransferFrom calldata permit,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes calldata
    ) external {
        IERC20(permit.permitted.token).transferFrom(
            owner,
            transferDetails.to,
            transferDetails.requestedAmount
        );
    }
}

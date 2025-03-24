// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library Errors {
    
    // Tier errors
    error TierExists();
    error TierNotExists();
    error TierInsufficient();

    // Loan Errors
    error LoanActive();
    error NoLoanActive();
    error NoLoanDefault();
    error LoanIdNotFound();
    error DefaultDetected();
    error InsufficientLiquidity();
    error LoanExpired();

    // Repay Error
    error PermitInvalidToken();
    error PermitInvalidAmount();
    error TransferInvalidAmount();
    error TransferInvalidAddress();

    // Pool Period Errors
    error PoolNotActive();
    error NoWithdrawWhenActive();


    // NFT Errors
    error NoMagnifyNFT();
    error AlreadyOwnedNFT();
    error TokenIdInvalid(uint256 tokenId);
    error SoulboundTransferNotAllowed();

    // Generic Error
    error OutOfBoundsArray();
    error CallerNotAdmin();
    error InputZero();
    error AlreadySetup();

}
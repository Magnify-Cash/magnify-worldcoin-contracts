// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMagnifyWorldV3 {
    struct LoanData {
        bytes32 loanID;
        uint256 tokenId;
        uint256 loanAmount;
        uint256 loanTimestamp;
        uint256 duration;
        uint256 repaymentTimestamp;
        address borrower;
        uint16 interestRate;
        uint8 tier;
        bool isDefault;
        bool isActive;
    }

    /**
     * @dev Tier structure defining loan parameters for each tier
     * @param loanAmount The amount that can be borrowed in this tier
     * @param interestRate Interest rate in basis points (1/100th of a percent)
     * @param loanPeriod Duration of the loan in seconds
     */
    struct Tier {
        uint256 loanAmount;
        uint256 loanPeriod;
        uint16 originationFee;
        uint16 interestRate;
    }
}
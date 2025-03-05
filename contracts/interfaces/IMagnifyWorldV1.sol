// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;


interface IMagnifyWorldV1 {
    /**
     * @dev Tier structure defining loan parameters for each tier
     * @param loanAmount The amount that can be borrowed in this tier
     * @param interestRate Interest rate in basis points (1/100th of a percent)
     * @param loanPeriod Duration of the loan in seconds
     */
    struct Tier {
        uint256 loanAmount;
        uint256 interestRate;
        uint256 loanPeriod;
    }

    /**
     * @dev Loan structure containing active loan details
     * @param amount The borrowed amount
     * @param startTime Timestamp when the loan was initiated
     * @param isActive Whether the loan is currently active
     * @param interestRate Interest rate for this specific loan
     * @param loanPeriod Duration of this specific loan
     */
    struct Loan {
        uint256 amount;
        uint256 startTime;
        bool isActive;
        uint256 interestRate;
        uint256 loanPeriod;
    }
}
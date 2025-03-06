// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMagnifyWorldSoulboundNFT {

    /**
     * @dev Tier structure defining loan parameters for each tier
     * @param loanAmount The max amount that can be borrowed in this tier
     * @param interestRate Interest rate in basis points (1/100th of a percent)
     * @param loanPeriod Max duration of the loan in seconds
     */
    struct Tier {
        uint256 loanAmount;
        uint256 interestRate;
        uint256 loanPeriod;
    }

    /**
     * @dev Tier structure defining loan parameters for each tier
     * @param loansRepaid Number of repaid loans
     * @param interestRate Total interest paid
     * @param loansDefaulted Number of defaulted loans
     */
    struct RepaymentHistory {
        uint256 loansRepaid;
        uint256 interestPaid;
        uint256 loansDefaulted;
    }
}

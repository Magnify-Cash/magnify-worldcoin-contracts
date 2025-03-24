// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMagnifyWorldV3 {
    struct LoanData {
        bytes32 loanID;
        uint256 tokenId;
        uint256 loanTimestamp;
        uint256 repaymentTimestamp;
        address borrower;
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
        uint16 interestRate;
    }

    function getLoan(address, uint256) external view returns (LoanData memory);

    /// @notice Emitted when a loan is requested
    /// @param loanId The unique identifier of the loan
    /// @param amount The amount of the loan requested
    /// @param borrower The address of the borrower
    event LoanRequested(
        bytes32 indexed loanId,
        uint256 amount,
        address indexed borrower
    );

    /// @notice Emitted when a loan is repaid
    /// @param loanId The unique identifier of the loan
    /// @param amount The total amount repaid (principal + interest)
    /// @param borrower The address of the borrower
    event LoanRepaid(
        bytes32 indexed loanId,
        uint256 amount,
        address indexed borrower
    );

    /// @notice Emitted when a loan is defaulted
    /// @param loanId The unique identifier of the loan
    /// @param amount The amount of the loan that defaulted
    /// @param borrower The address of the borrower
    event LoanDefaulted(
        bytes32 indexed loanId,
        uint256 amount,
        address indexed borrower
    );
}

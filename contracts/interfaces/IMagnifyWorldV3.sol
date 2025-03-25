// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import {ISignatureTransfer} from "./ISignatureTransfer.sol";

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

    function requestLoan() external;

    function repayLoanWithPermit2(
        ISignatureTransfer.PermitTransferFrom calldata permitTransferFrom,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        bytes calldata signature
    ) external;

    function repayDefaultedLoanWithPermit2(
        uint256 _index,
        ISignatureTransfer.PermitTransferFrom calldata permitTransferFrom,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        bytes calldata signature
    ) external;

    function processOutdatedLoans() external;

    function hasActiveLoan(address _user) external view returns (bool);

    function getActiveLoan(
        address _user
    ) external view returns (LoanData memory loan);

    function getLoan(
        address _user,
        uint256 _index
    ) external view returns (LoanData memory loan);

    function getLoanHistory(
        address _user
    ) external view returns (LoanData[] memory loanHistory);

    function getAllActiveLoans()
        external
        view
        returns (LoanData[] memory allActiveLoans);

    function getTotalBorrows() external view returns (uint256);

    function getTotalDefaults() external view returns (uint256);

    function isActive() external view returns (bool);

    function isExpired() external view returns (bool);

    function isWarmup() external view returns (bool);

    function isCooldown() external view returns (bool);

    /// @notice Emitted when a loan is requested
    /// @param loanId The unique identifier of the loan
    /// @param borrower The address of the borrower
    /// @param index The index of the loan in the users list
    event LoanRequested(
        bytes32 indexed loanId,
        address indexed borrower,
        uint256 index
    );

    /// @notice Emitted when a loan is repaid
    /// @param loanId The unique identifier of the loan
    /// @param borrower The address of the borrower
    /// @param index The index of the loan in the users list
    event LoanRepaid(
        bytes32 indexed loanId,
        address indexed borrower,
        uint256 index
    );

    /// @notice Emitted when a loan is defaulted
    /// @param loanId The unique identifier of the loan
    /// @param borrower The address of the borrower
    /// @param index The index of the loan in the users list
    event LoanDefaulted(
        bytes32 indexed loanId,
        address indexed borrower,
        uint256 index
    );

    /// @notice Emitted when a loan is defaulted
    /// @param loanId The unique identifier of the loan
    /// @param borrower The address of the borrower
    /// @param index The index of the loan in the users list
    event LoanDefaultRepaid(
        bytes32 indexed loanId,
        address indexed borrower,
        uint256 index
    );
}

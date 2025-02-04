// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// Interface for interacting with MagnifyWorldV1
interface IMagnifyWorldV1 {
    function loans(uint256 tokenId) external view returns (
        uint256 amount,
        uint256 startTime,
        bool isActive,
        uint256 interestRate,
        uint256 loanPeriod
    );
    function userNFT(address user) external view returns (uint256 tokenId);
    function nftToTier(uint256 tokenId) external view returns (uint256 tierId);
    function tiers(uint256 tierId) external view returns (
        uint256 loanAmount,
        uint256 interestRate,
        uint256 loanPeriod
    );
    function loanToken() external view returns (address tokenAddress);
    function PERMIT2() external view returns (address permit2Address);
    function tierCount() external view returns (uint256 count);
    function repayLoanWithPermit2(
        ISignatureTransfer.PermitTransferFrom calldata permitTransferFrom,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        bytes calldata signature
    ) external;
}

// Interface for Signature-based token transfer
interface ISignatureTransfer {
    struct TokenPermissions {
        address token;
        uint256 amount;
    }

    struct PermitTransferFrom {
        TokenPermissions permitted;
        uint256 nonce;
        uint256 deadline;
    }

    struct SignatureTransferDetails {
        address to;
        uint256 requestedAmount;
    }
}

// Interface for the PERMIT2 functionality
interface IPermit2 {
    function permitTransferFrom(
        ISignatureTransfer.PermitTransferFrom calldata permit,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes calldata signature
    ) external;
}

// @title MagnifyWorldV2 Contract
// @dev A contract to manage loans and NFT-based interactions for the MagnifyWorld ecosystem, extending functionalities from V1.
contract MagnifyWorldV2 is Ownable, ReentrancyGuard {
    // State variables
    IMagnifyWorldV1 public immutable v1;
    IERC20 public immutable loanToken;
    IPermit2 public immutable PERMIT2;

    // Mappings
    mapping(address => Loan) public v2Loans;

    // Structs
    /**
     * @dev Loan structure containing active loan details
     * @param amount The borrowed amount
     * @param startTime Timestamp when the loan was initiated
     * @param isActive Whether the loan is currently active
     * @param interestRate Interest rate for this specific loan
     * @param loanPeriod Duration of this specific loan
     */
    struct Loan {
        uint256 amount;         // Loan amount in the specified token
        uint256 startTime;      // Timestamp when the loan was issued
        bool isActive;          // Status of the loan
        uint256 interestRate;   // Interest rate applied on the loan
        uint256 loanPeriod;     // Duration of the loan
    }

    // Events
    event LoanRequested(address indexed borrower, uint256 amount);
    event LoanRepaid(address indexed borrower, uint256 amount);
    event LoanWithdrawn(uint256 amount);

    /**
     * @dev Constructor initializes the contract by setting the V1 contract, loan token, and PERMIT2 interface
     * @param _v1 Address of the MagnifyWorldV1 contract
     */
    constructor(address _v1) Ownable(msg.sender) {
        v1 = IMagnifyWorldV1(_v1);
        loanToken = IERC20(v1.loanToken());
        PERMIT2 = IPermit2(v1.PERMIT2());
    }

    /**
     * @notice Retrieves loan details for a given NFT token ID.
     * @param tokenId The ID of the NFT associated with the loan.
     * @return amount The loan amount.
     * @return startTime The timestamp when the loan was initiated.
     * @return isActive Boolean indicating if the loan is currently active.
     * @return interestRate The interest rate applied to the loan.
     * @return loanPeriod The duration of the loan.
     */
    function loans(uint256 tokenId) external view returns (
        uint256 amount,
        uint256 startTime,
        bool isActive,
        uint256 interestRate,
        uint256 loanPeriod
    ) {
        return v1.loans(tokenId);
    }

    /**
     * @notice Retrieves the NFT token ID owned by a specific user.
     * @param user The address of the user.
     * @return tokenId The NFT token ID owned by the user.
     */
    function userNFT(address user) external view returns (uint256 tokenId) {
        return v1.userNFT(user);
    }

    /**
     * @notice Fetches the tier ID associated with a specific NFT token.
     * @param tokenId The ID of the NFT.
     * @return tierId The tier ID linked to the given NFT token.
     */
    function nftToTier(uint256 tokenId) external view returns (uint256 tierId) {
        return v1.nftToTier(tokenId);
    }

    /**
     * @notice Retrieves the details of a specific tier.
     * @param tierId The ID of the tier.
     * @return loanAmount The maximum loan amount allowed for this tier.
     * @return interestRate The interest rate applicable to this tier.
     * @return loanPeriod The duration of loans in this tier.
     */
    function tiers(uint256 tierId) external view returns (
        uint256 loanAmount,
        uint256 interestRate,
        uint256 loanPeriod
    ) {
        return v1.tiers(tierId);
    }

    /**
     * @notice Returns the address of the loan token used in the system.
     * @return tokenAddress The address of the ERC20 token used for loans.
     */
    function loanToken() external view returns (address tokenAddress) {
        return v1.loanToken();
    }

    /**
     * @notice Returns the address of the PERMIT2 contract.
     * @return permit2Address The address of the PERMIT2 contract.
     */
    function PERMIT2() external view returns (address permit2Address) {
        return v1.PERMIT2();
    }

    /**
     * @notice Retrieves the total number of tiers available in the system.
     * @return count The total number of loan tiers.
     */
    function tierCount() external view returns (uint256 count) {
        return v1.tierCount();
    }


    /**
     * @dev Allows a user to request a loan if certain conditions are met
     * @param amount The loan amount requested
     * @param interestRate The interest rate for the loan
     * @param loanPeriod The duration of the loan
     */
    function requestLoan(uint256 amount, uint256 interestRate, uint256 loanPeriod) external nonReentrant {
        // Check if user has an active loan in V1 or V2
        uint256 token_id = v1.userNFT(msg.sender);
        ( , , bool activeOnV1, , ) = v1.loans(token_id);
        require(!activeOnV1, "Active loan on V1");
        require(!v2Loans[msg.sender].isActive, "Active loan on V2");

        // Ensure sufficient balance to issue loan
        require(loanToken.balanceOf(address(this)) >= amount, "Insufficient contract balance");

        // Issue loan
        v2Loans[msg.sender] = Loan(amount, block.timestamp, true, interestRate, loanPeriod);
        require(loanToken.transfer(msg.sender, amount), "Transfer failed");
        emit LoanRequested(msg.sender, amount);
    }

    /**
     * @dev Allows a user to repay their loan using Permit2 functionality
     * @param permitTransferFrom The permit data for the transfer
     * @param transferDetails The transfer details including the recipient and amount
     * @param signature The signature authorizing the transfer
     */
    function repayLoanWithPermit2(
        ISignatureTransfer.PermitTransferFrom calldata permitTransferFrom,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        bytes calldata signature
    ) external nonReentrant {
        // Check if user has an active loan in V1
        uint256 token_id = v1.userNFT(msg.sender);
        ( , , bool activeOnV1, , ) = v1.loans(token_id);
        if (activeOnV1) {
            try v1.repayLoanWithPermit2(permitTransferFrom, transferDetails, signature) {
                emit LoanRepaid(msg.sender, transferDetails.requestedAmount);
                return;
            } catch {
                revert("V1 repayment failed");
            }
        }

        // Check if user has an active loan in V2
        Loan storage loan = v2Loans[msg.sender];
        if (loan.isActive) {
            uint256 interest = (loan.amount * loan.interestRate) / 10000;
            uint256 totalDue = loan.amount + interest;
            require(transferDetails.requestedAmount >= totalDue, "Insufficient repayment amount");
            PERMIT2.permitTransferFrom(permitTransferFrom, transferDetails, msg.sender, signature);
            loan.isActive = false;
            emit LoanRepaid(msg.sender, totalDue);
            return;
        }

        revert("No active loan in V1 or V2");
    }

    /**
     * @dev Fetches the loan details of the caller from either V1 or V2
     * @return A tuple containing a boolean indicating if a loan is active and the loan details
     */
    function fetchLoanByAddress() external view returns (bool, Loan memory) {
        // Check V1
        uint256 tokenId = v1.userNFT(msg.sender);
        (uint256 amount, uint256 startTime, bool isActive, uint256 interestRate, uint256 loanPeriod) = v1.loans(tokenId);
        if (isActive) {
            return (true, Loan(amount, startTime, isActive, interestRate, loanPeriod));
        }

        // Check V2
        Loan memory v2Loan = v2Loans[msg.sender];
        if (v2Loan.isActive) {
            return (true, v2Loan);
        }

        // No active loan in V1 or V2
        return (false, Loan(0, 0, false, 0, 0));
    }

    /**
     * @dev Allows the contract owner to withdraw loan tokens from the contract
     */
    function withdrawLoanToken() external onlyOwner {
        uint256 balanceV2 = loanToken.balanceOf(address(this));
        if (balanceV2 > 0) {
            require(loanToken.transfer(msg.sender, balanceV2), "Transfer failed");
            emit LoanWithdrawn(balanceV2);
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMagnifyWorldSoulboundNFT {
    /**
     * @dev Tier structure defining loan parameters for each tier
     * @param loansRepaid Number of repaid loans
     * @param interestRate Total interest paid
     * @param loansDefaulted Number of defaulted loans
     * @param owner Owner of the NFT
     * @param tier tier of the NFT 1 - device, 2 - passport, 3 - orb
     */
    struct NFTData {
        uint256 loansRepaid;
        uint256 interestPaid;
        uint256 loansDefaulted;
        address owner;
        uint8 tier;
        bool ongoingLoan;
    }

    /**
     * @dev Tier structure defining loan parameters for each tier
     * @param loansRepaid Number of repaid loans
     * @param interestRate Total interest paid
     * @param loansDefaulted Number of defaulted loans
     * @param owner Owner of the NFT
     * @param tier tier of the NFT 1 - device, 2 - passport, 3 - orb
     */
    struct Loan {
        address loanAddress;
        uint256 loanIndex;
    }

    function increaseloanRepayment(
        uint256 _tokenId,
        uint256 _interestPaid
    ) external;

    function increaseLoanDefault(uint256 _tokenId, uint256 _amount) external;

    function decreaseLoanDefault(uint256 _tokenId, uint256 _amount) external;

    function userToId(address _user) external view returns (uint256);

    function mintNFT(address _to, uint8 _tier) external;

    function getNFTData(uint256 _tokenId) external view returns (NFTData memory);
}

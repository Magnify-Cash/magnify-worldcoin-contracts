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

    function mintNFT(address _to, uint8 _tier) external;

    function upgradeTier(uint256 _tokenId, uint8 _newTier) external;

    function setOngoingLoan(uint256 _tokenId) external;

    function removeOngoingLoan(uint256 _tokenId) external;

    function increaseloanRepayment(
        uint256 _tokenId,
        uint256 _interestPaid
    ) external;

    function increaseLoanDefault(uint256 _tokenId, uint256 _amount) external;

    function decreaseLoanDefault(uint256 _tokenId, uint256 _amount) external;

    function userToId(address _user) external view returns (uint256);

    function getNFTData(
        uint256 _tokenId
    ) external view returns (NFTData memory);

    function addNewLoan(uint256 _tokenId, uint256 _index) external;
}

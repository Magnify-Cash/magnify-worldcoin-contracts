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
    }
}

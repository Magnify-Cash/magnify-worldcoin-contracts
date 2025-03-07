// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IMagnifyWorldSoulboundNFT} from "./interfaces/IMagnifyWorldSoulboundNFT.sol";

contract MagnifyWorldSoulboundNFT is
    ERC721Upgradeable,
    OwnableUpgradeable,
    IMagnifyWorldSoulboundNFT
{
    uint256 internal tokenCount;
    mapping(uint256 => NFTData) public nftData;
    mapping(address => uint256) public userToId;
    mapping(address => bool) public admins;
    uint256[50] __gap;

    error AlreadyOwnedNFT();

    modifier onlyAdmin() {
        require(admins[msg.sender], "admin: called is not an admin");
        _;
    }

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __ERC721_init("Magnify World NFT", "MAGNFT");
    }

    function mintNFT(address _to, uint8 _tier) public onlyAdmin {
        if (userToId[_to] != 0) {
            revert AlreadyOwnedNFT(); 
        }
        tokenCount++;
        _safeMint(_to, tokenCount);
        nftData[tokenCount] = NFTData(0, 0, 0, _to, _tier);
    }

    function upgradeTier(uint256 _tokenId, uint8 _newTier) public onlyAdmin {
        _requireOwned(_tokenId);
        nftData[_tokenId].tier = _newTier;
    }

    function updateloanRepayment(uint256 _tokenId, uint256 _interestPaid) external onlyAdmin {
        nftData[_tokenId].loansRepaid++;
        nftData[_tokenId].interestPaid += _interestPaid;
    }

    function updateLoanDefault(uint256 _tokenId, uint256 _defaultAmount) external onlyAdmin {
        nftData[_tokenId].loansDefaulted+= _defaultAmount;
    }

    // Set multiple admin wallets
    function setAdmin(address _address, bool _allow) external onlyOwner {
        admins[_address] = _allow;
    }
}

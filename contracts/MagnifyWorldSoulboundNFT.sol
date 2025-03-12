// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Errors} from "./errors/Errors.sol";
import {IMagnifyWorldSoulboundNFT} from "./interfaces/IMagnifyWorldSoulboundNFT.sol";

contract MagnifyWorldSoulboundNFT is
    ERC721Upgradeable,
    OwnableUpgradeable,
    IMagnifyWorldSoulboundNFT
{
    uint256 public tokenCount;
    mapping(uint256 => NFTData) public nftData;
    mapping(address => uint256) public userToId;
    mapping(address => bool) public admins;
    uint256[50] __gap;

    modifier onlyAdmin() {
        if (admins[msg.sender]) {
            revert Errors.CallerNotAdmin();
        }
        _;
    }

    function initialize(string calldata _name, string calldata _symbol) public initializer {
        __ERC721_init(_name, _symbol);
        __Ownable_init(msg.sender);
    }

    function mintNFT(address _to, uint8 _tier) public onlyAdmin {
        if (userToId[_to] != 0) {
            revert Errors.AlreadyOwnedNFT();
        }
        tokenCount++;
        _safeMint(_to, tokenCount);
        nftData[tokenCount] = NFTData(0, 0, 0, _to, _tier);
    }

    function upgradeTier(uint256 _tokenId, uint8 _newTier) public onlyAdmin {
        checkNFTExists(_tokenId);
        nftData[_tokenId].tier = _newTier;
    }

    function increaseloanRepayment(
        uint256 _tokenId,
        uint256 _interestPaid
    ) external onlyAdmin {
        checkNFTExists(_tokenId);
        nftData[_tokenId].loansRepaid++;
        nftData[_tokenId].interestPaid += _interestPaid;
    }

    function increaseLoanDefault(
        uint256 _tokenId,
        uint256 _amount
    ) external onlyAdmin {
        checkNFTExists(_tokenId);
        nftData[_tokenId].loansDefaulted += _amount;
    }

    function decreaseLoanDefault(
        uint256 _tokenId,
        uint256 _amount
    ) external onlyAdmin {
        checkNFTExists(_tokenId);
        nftData[_tokenId].loansDefaulted -= _amount;
    }

    function checkNFTExists(uint256 _tokenId) internal view {
        if (nftData[_tokenId].owner == address(0)) {
            revert Errors.TokenIdInvalid(_tokenId);
        }
    }

    function getNFTData(uint256 _tokenId) external view returns (NFTData memory) {
        return nftData[_tokenId];
    }

    // Set multiple admin wallets
    function setAdmin(address _address, bool _allow) external onlyOwner {
        admins[_address] = _allow;
    }
}

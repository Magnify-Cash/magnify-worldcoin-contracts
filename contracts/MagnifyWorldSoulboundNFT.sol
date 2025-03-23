// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Errors} from "./errors/Errors.sol";
import {IMagnifyWorldSoulboundNFT} from "./interfaces/IMagnifyWorldSoulboundNFT.sol";
import {IMagnifyWorldV3} from "./interfaces/IMagnifyWorldV3.sol";

contract MagnifyWorldSoulboundNFT is
    ERC721Upgradeable,
    OwnableUpgradeable,
    IMagnifyWorldSoulboundNFT
{
    string public baseURI;
    uint256 public tokenCount;
    IMagnifyWorldV3[] public magnifyPools;
    mapping(uint256 => Loan[]) public loanHistory;
    mapping(uint256 => NFTData) public nftData;
    mapping(address => uint256) public userToId;
    mapping(address => bool) public admins;
    uint256[50] __gap;

    modifier onlyAdmin() {
        if (!admins[msg.sender]) {
            revert Errors.CallerNotAdmin();
        }
        _;
    }

    function initialize(
        string calldata _name,
        string calldata _symbol
    ) public initializer {
        __ERC721_init(_name, _symbol);
        __Ownable_init(msg.sender);
        admins[msg.sender] = true;
    }

    function mintNFT(address _to, uint8 _tier) public onlyAdmin {
        if (userToId[_to] != 0) {
            revert Errors.AlreadyOwnedNFT();
        }
        tokenCount++;
        _safeMint(_to, tokenCount);
        nftData[tokenCount] = NFTData(0, 0, 0, _to, _tier, false);
    }

    function upgradeTier(uint256 _tokenId, uint8 _newTier) public onlyAdmin {
        checkNFTExists(_tokenId);
        nftData[_tokenId].tier = _newTier;
    }

    function setOngoingLoan(
        uint256 _tokenId
    ) external onlyAdmin {
        checkNFTExists(_tokenId);
        nftData[_tokenId].ongoingLoan = true;
    }

    function removeOngoingLoan(
        uint256 _tokenId
    ) external onlyAdmin {
        checkNFTExists(_tokenId);
        nftData[_tokenId].ongoingLoan = false;
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

    function setBaseURI(string calldata _newBaseURI) external onlyAdmin {
        baseURI = _newBaseURI;
    }

    function checkNFTExists(uint256 _tokenId) internal view {
        if (nftData[_tokenId].owner == address(0)) {
            revert Errors.TokenIdInvalid(_tokenId);
        }
    }

    function getNFTData(
        uint256 _tokenId
    ) external view returns (NFTData memory) {
        return nftData[_tokenId];
    }

    function getLoanHistory(uint256 _tokenId) external view returns (Loan[] memory) {
        return loanHistory[_tokenId];
    }

    function getLoanHistoryData(uint256 _tokenId) external view returns (IMagnifyWorldV3.LoanData[] memory) {
        IMagnifyWorldV3.LoanData[] memory data = new IMagnifyWorldV3.LoanData[](loanHistory[_tokenId].length);
        address user = _ownerOf(_tokenId);
        for (uint256 i = 0; i < loanHistory[_tokenId].length; i++) {
            IMagnifyWorldV3 v3 = IMagnifyWorldV3(loanHistory[_tokenId][i].loanAddress); 
            data[i] = v3.getLoan(user, loanHistory[_tokenId][i].loanIndex);
        }
        return data;
    }

    // Set multiple admin wallets
    function setAdmin(address _address, bool _allow) external onlyOwner {
        admins[_address] = _allow;
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721Upgradeable)
        returns (address)
    {
        address from = _ownerOf(tokenId);
        if (from != address(0)) {
            revert Errors.SoulboundTransferNotAllowed();
        }

        return super._update(to, tokenId, auth);
    }

    function addMagnifyPool(IMagnifyWorldV3 _newPool) external onlyAdmin {
        magnifyPools.push(_newPool);
        admins[address(_newPool)] = true;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }
}

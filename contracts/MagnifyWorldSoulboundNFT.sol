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
    mapping(uint256 => NFTData) public repaymentInfo;
    mapping(address => bool) public admins;
    uint256[50] __gap;

    modifier onlyAdmin() {
        require(admins[msg.sender], "admin: called is not an admin");
        _;
    }

    function initialize() public initializer {}

    function mintNFT() public onlyAdmin {}

    // Set multiple admin wallets
    function setAdmin(address _address, bool _allow) external onlyOwner {
        admins[_address] = _allow;
    }
}

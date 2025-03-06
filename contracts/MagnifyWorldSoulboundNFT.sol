// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IMagnifyWorldSoulboundNFT} from "./interfaces/IMagnifyWorldSoulboundNFT.sol";

contract MagnifyWorldSoulboundNFT is ERC721Upgradeable, OwnableUpgradeable, IMagnifyWorldSoulboundNFT {

    mapping(uint256 => Tier) public tiers;
    mapping(uint256 => RepaymentHistory) public repaymentInfo;
    mapping(uint256 => uint256) public nftToTier;
    mapping(address => bool) public admins;
    uint256[50] __gap;

    function initialize() public initializer {
    }

    function addTier() external onlyOwner {
    }

    function updateTier() external onlyOwner {
    }


}

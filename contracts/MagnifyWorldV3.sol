// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMagnifyWorldV3} from "./interfaces/IMagnifyWorldV3.sol";
import {IMagnifyWorldSoulboundNFT} from "./interfaces/IMagnifyWorldSoulboundNFT.sol";

contract MagnifyWorldV3 is
    IMagnifyWorldV3,
    ERC4626Upgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    IMagnifyWorldSoulboundNFT public soulboundNFT;
    uint256 public totalLoanAmount;
    address public treasury;
    uint16 public treasuryFee;
    LoanData[] public activeLoans;

    mapping(address => LoanData[]) public v3loans;
    mapping(uint8 => Tier) public tiers;

    uint256[50] __gap;

    function initialize(
        string calldata _name,
        string calldata _symbol,
        IERC20 _asset
    ) external initializer {
        __Ownable_init(msg.sender);
        __ERC20_init(_name, _symbol);
        __ERC4626_init(_asset);
        __ReentrancyGuard_init();
    }

    /*//////////////////////////////////////////////////////////////
                          TIERS LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Adds a new tier with specified parameters
     * @param _loanAmount Amount that can be borrowed in this tier
     * @param _interestRate Interest rate in basis points
     * @param _loanPeriod Loan duration in seconds
     */
    function addTier(
        uint8 _tier,
        uint256 _loanAmount,
        uint256 _interestRate,
        uint256 _loanPeriod
    ) external onlyOwner {
        if (tiers[_tier].loanAmount != 0) {
            revert("Tier exists");
        }
        if (_loanAmount == 0 || _interestRate == 0 || _loanPeriod == 0)
            revert("Invalid tier parameters");

        tiers[_tier] = Tier(_loanAmount, _interestRate, _loanPeriod);

        // emit TierAdded(tierCount, loanAmount, interestRate, loanPeriod);
    }

    /**
     * @dev Updates an existing tier's parameters
     * @param _tierId ID of the tier to update
     * @param _newLoanAmount New loan amount
     * @param _newInterestRate New interest rate
     * @param _newLoanPeriod New loan period
     */
    function updateTier(
        uint8 _tierId,
        uint256 _newLoanAmount,
        uint256 _newInterestRate,
        uint256 _newLoanPeriod
    ) external onlyOwner {
        if (tiers[_tierId].loanAmount == 0) {
            revert("Tier does not exists");
        }
        if (_newLoanAmount == 0 || _newInterestRate == 0 || _newLoanPeriod == 0)
            revert("Invalid tier parameters");

        tiers[_tierId] = Tier(_newLoanAmount, _newInterestRate, _newLoanPeriod);

        // emit TierUpdated(tierId, newLoanAmount, newInterestRate, newLoanPeriod);
    }

    /*//////////////////////////////////////////////////////////////
                          LOANS LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Allows NFT owner to request a loan based on their tier
     * @notice This function automatically uses the NFT associated with the msg.sender
     */
    function requestLoan() external nonReentrant {

        uint256 tokenId = soulboundNFT.userToId(msg.sender);

        if (tokenId == 0) {
            // check V1 if yes mint soulbound, if no throw error
        }
        // get tier and NFT data

        // Check if user has existing active loan


        // Check if enough assets

        // Issue loan

        // Add to active loans

        // emit LoanRequested(tokenId, loanAmount, msg.sender);
        return;
    }

    /**
     * @dev Allows borrower to repay their loan
     * @notice This function automatically uses the NFT associated with the msg.sender
     */
    function repayLoan() external nonReentrant {
        return;
    }

    /**
     * @notice Repays an active loan using Permit2 for token approval
     * @dev Uses Uniswap's Permit2 for gas-efficient token approvals in a single transaction
     * @dev The loan must be active and not expired, and the caller must be the NFT owner
     */
    function repayLoanWithPermit2() external nonReentrant {
        return;
    }

    function processOutdatedLoans() external nonReentrant {
        LoanData memory oldestLoan = activeLoans[activeLoans.length - 1];
        while(oldestLoan.loanTimestamp + oldestLoan.duration < block.timestamp) {
            defaultLastLoan(oldestLoan);
            oldestLoan = activeLoans[activeLoans.length - 1];
        }
        return;
    }

    function getActiveLoan(address _user) external view returns (LoanData memory loan) {
        uint256 length = v3loans[_user].length;
        // return empty if length is 0
        LoanData memory latestLoan = v3loans[_user][length - 1];

        if (latestLoan.isActive) {
            return latestLoan;
        } else {
            LoanData memory emptyLoan;
            return emptyLoan;
        }
    }

    function getAllActiveLoans() external view returns (LoanData[] memory allActiveLoans) {
        return activeLoans;
    }

    function getLoanHistory(address _user) external view returns (LoanData[] memory loanHistory) {
        return v3loans[_user];
    }

    function deleteActiveLoan(uint256 _index) internal {
        activeLoans[_index] = activeLoans[activeLoans.length - 1];
        activeLoans.pop();
    }

    function defaultLastLoan(LoanData memory oldestLoan) internal {
        totalLoanAmount -= oldestLoan.loanAmount;
        soulboundNFT.increaseLoanDefault(oldestLoan.tokenId, oldestLoan.loanAmount);
        v3loans[oldestLoan.borrower][v3loans[oldestLoan.borrower].length -1].isDefault = true;
        activeLoans.pop();
    }
}

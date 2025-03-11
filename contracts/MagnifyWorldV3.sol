// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMagnifyWorldV1} from "./interfaces/IMagnifyWorldV1.sol";
import {IMagnifyWorldV3} from "./interfaces/IMagnifyWorldV3.sol";
import {IMagnifyWorldSoulboundNFT} from "./interfaces/IMagnifyWorldSoulboundNFT.sol";
import {IPermit2} from "./interfaces/IPermit2.sol";
import {ISignatureTransfer} from "./interfaces/ISignatureTransfer.sol";

contract MagnifyWorldV3 is
    IMagnifyWorldV3,
    ERC4626Upgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    IMagnifyWorldSoulboundNFT public soulboundNFT;
    IMagnifyWorldV1 public v1;
    IPermit2 public permit2;
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
        uint16 _loanPeriod
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
        uint16 _newLoanPeriod
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
    function requestLoan(uint8 _tier) external nonReentrant {
        Tier memory tierInfo = tiers[_tier];
        if (tierInfo.loanAmount == 0) {
            revert("Tier does not exists");
        }
        if (hasActiveLoan(msg.sender)) {
            revert("Error has active loan");
        }
        uint256 tokenId = soulboundNFT.userToId(msg.sender);

        if (tokenId == 0) {
            uint256 v1TokenId = v1.userNFT(msg.sender);
            if (v1TokenId == 0) {
                revert("No NFT");
            }
            uint256 userTierId = v1.nftToTier(tokenId);
            soulboundNFT.mintNFT(msg.sender, uint8(userTierId));
            tokenId = soulboundNFT.userToId(msg.sender);
        }
        // get tier and NFT data
        IMagnifyWorldSoulboundNFT.NFTData memory data = soulboundNFT.getNFTData(
            tokenId
        );

        if (data.tier < _tier) {
            revert("NFT Tier lower than requested loan tier");
        }

        if (data.loansDefaulted > 0) {
            revert("Existing loan defaulted");
        }

        IERC20 usdc = IERC20(asset());
        uint256 bal = usdc.balanceOf(address(this));
        if (bal < tierInfo.loanAmount) {
            revert("Insufficient liquidity to serve loan");
        }
        uint256 userLoanHistoryLength = v3loans[msg.sender].length;
        // Issue loan
        LoanData memory newLoan = LoanData(
            keccak256(abi.encode(msg.sender, userLoanHistoryLength)),
            tokenId,
            tierInfo.loanAmount,
            block.timestamp,
            tierInfo.loanPeriod,
            0,
            msg.sender,
            tierInfo.interestRate,
            _tier,
            false,
            true
        );

        v3loans[msg.sender].push(newLoan);
        addNewActiveLoan(newLoan);

        usdc.safeTransfer(msg.sender, tierInfo.loanAmount);
        // emit LoanRequested(tokenId, loanAmount, msg.sender);
        return;
    }

    /**
     * @notice Repays an active loan using Permit2 for token approval
     * @dev Uses Uniswap's Permit2 for gas-efficient token approvals in a single transaction
     * @dev The loan must be active and not expired, and the caller must be the NFT owner
     */
    function repayLoanWithPermit2(
        ISignatureTransfer.PermitTransferFrom calldata permitTransferFrom,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        bytes calldata signature
    ) external nonReentrant {
        // V2 repayment
        LoanData storage loan = v3loans[msg.sender][
            v3loans[msg.sender].length - 1
        ];
        if (!loan.isActive) {
            revert("No active loan");
        }

        loan.isActive = false;
        loan.repaymentTimestamp = block.timestamp;

        uint256 interest = (loan.loanAmount * loan.interestRate) / 10000;
        uint256 totalDue = loan.loanAmount + interest;
        require(
            block.timestamp <= loan.loanTimestamp + loan.duration,
            "Loan is expired"
        );
        if (permitTransferFrom.permitted.token != asset())
            revert("Invalid token");
        if (permitTransferFrom.permitted.amount < totalDue)
            revert("Insufficient permit amount");
        if (transferDetails.requestedAmount != totalDue)
            revert("Invalid requested amount");
        if (transferDetails.to != address(this))
            revert("Invalid transfer recipient");

        permit2.permitTransferFrom(
            permitTransferFrom,
            transferDetails,
            msg.sender,
            signature
        );
        // emit LoanRepaid(tokenId, totalDue, msg.sender);
        return;
    }

    function processOutdatedLoans() external nonReentrant {
        LoanData memory oldestLoan = activeLoans[activeLoans.length - 1];
        while (
            oldestLoan.loanTimestamp + oldestLoan.duration < block.timestamp
        ) {
            defaultLastLoan(oldestLoan);
            oldestLoan = activeLoans[activeLoans.length - 1];
        }
        return;
    }

    function hasActiveLoan(address _user) public view returns (bool) {
        uint256 length = v3loans[_user].length;
        if (length == 0) return false;

        LoanData memory latestLoan = v3loans[_user][length - 1];

        return latestLoan.isActive;
    }

    function getActiveLoan(
        address _user
    ) external view returns (LoanData memory loan) {
        if (hasActiveLoan(_user)) {
            return v3loans[_user][v3loans[_user].length - 1];
        } else {
            LoanData memory emptyLoan;
            return emptyLoan;
        }
    }

    function getAllActiveLoans()
        external
        view
        returns (LoanData[] memory allActiveLoans)
    {
        return activeLoans;
    }

    function getLoanHistory(
        address _user
    ) external view returns (LoanData[] memory loanHistory) {
        return v3loans[_user];
    }

    function addNewActiveLoan(LoanData memory newLoan) internal {
        LoanData memory emptyLoan;
        activeLoans.push(emptyLoan);
        for (uint256 i = 0; i < activeLoans.length - 1; i++) {
            activeLoans[i] = activeLoans[i + 1];
        }
        activeLoans[0] = newLoan;
    }

    function findActiveLoan(bytes32 id) internal view returns (uint256 index) {
        for (uint256 i = 0; i < activeLoans.length - 1; i++) {
            if (activeLoans[i].loanID == id) {
                return i;
            }
        }
        revert("could not find id");
    }

    function defaultLastLoan(LoanData memory oldestLoan) internal {
        totalLoanAmount -= oldestLoan.loanAmount;
        soulboundNFT.increaseLoanDefault(
            oldestLoan.tokenId,
            oldestLoan.loanAmount
        );
        v3loans[oldestLoan.borrower][v3loans[oldestLoan.borrower].length - 1]
            .isDefault = true;
        activeLoans.pop();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Errors} from "./errors/Errors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMagnifyWorldV1} from "./interfaces/IMagnifyWorldV1.sol";
import {IMagnifyWorldV3} from "./interfaces/IMagnifyWorldV3.sol";
import {IMagnifyWorldSoulboundNFT} from "./interfaces/IMagnifyWorldSoulboundNFT.sol";
import {IPermit2} from "./interfaces/IPermit2.sol";
import {ISignatureTransfer} from "./interfaces/ISignatureTransfer.sol";


/// @title Magnify World V3
/// @author Jolly-Walker
/// @notice Uncolleteralized USDC loans for World Id users, users can also provide loan liquidity to earn from loan fees
/// @dev Inherits ERC4626 for vault logic
contract MagnifyWorldV3 is
    IMagnifyWorldV3,
    ERC4626Upgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using Math for uint256;
    using SafeERC20 for IERC20;

    IMagnifyWorldSoulboundNFT public soulboundNFT;
    IMagnifyWorldV1 public v1;
    IPermit2 public permit2;
    uint256 public totalLoanAmount;
    uint256 public totalDefaults;
    address public treasury;
    uint16 public treasuryFee;
    uint16 public defaultPenalty;
    uint16 public originationFee;
    LoanData[] public activeLoans;

    mapping(address => LoanData[]) public v3loans;
    mapping(uint8 => Tier) public tiers;

    uint256[50] __gap;


    /// Initilize function
    /// @param _name Name of liquidity token
    /// @param _symbol Symbol of liquidity token
    /// @param _asset USDC address
    /// @param _permit2 Permit2 address
    /// @param _soulboundNFT MagnifySoulboundNFT address
    /// @param _v1 MagnifyWorld V1 address
    /// @param _treasury Treasury address
    function initialize(
        string calldata _name,
        string calldata _symbol,
        IERC20 _asset,
        IPermit2 _permit2,
        IMagnifyWorldSoulboundNFT _soulboundNFT,
        IMagnifyWorldV1 _v1,
        address _treasury
    ) external initializer {
        __ERC20_init(_name, _symbol);
        __ERC4626_init(_asset);
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        permit2 = _permit2;
        soulboundNFT = _soulboundNFT;
        v1 = _v1;
        treasury = _treasury;
        treasuryFee = 2000;
        defaultPenalty = 1000;
        originationFee = 1000;
    }

    /*//////////////////////////////////////////////////////////////
                          TIERS LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Adds a new tier with specified parameters
     * @param _loanAmount Amount that can be borrowed in this tier
     * @param _loanPeriod Loan duration in seconds
     * @param _interestRate Interest rate in basis points
     */
    function addTier(
        uint8 _tier,
        uint256 _loanAmount,
        uint256 _loanPeriod,
        uint16 _interestRate
    ) external onlyOwner {
        if (tiers[_tier].loanAmount != 0) {
            revert Errors.TierExists();
        }
        if (_loanAmount == 0 || _interestRate == 0 || _loanPeriod == 0)
            revert Errors.InputZero();

        tiers[_tier] = Tier(_loanAmount, _loanPeriod, _interestRate);

        // emit TierAdded(tierCount, loanAmount, interestRate, loanPeriod);
    }

    /**
     * @dev Updates an existing tier's parameters
     * @param _tierId ID of the tier to update
     * @param _newLoanAmount New loan amount
     * @param _newLoanPeriod New loan period
     * @param _newInterestRate New interest rate
     */
    function updateTier(
        uint8 _tierId,
        uint256 _newLoanAmount,
        uint256 _newLoanPeriod,
        uint16 _newInterestRate
    ) external onlyOwner {
        if (tiers[_tierId].loanAmount == 0) {
            revert Errors.TierNotExists();
        }
        if (_newLoanAmount == 0 || _newInterestRate == 0 || _newLoanPeriod == 0)
            revert Errors.InputZero();

        tiers[_tierId] = Tier(_newLoanAmount, _newLoanPeriod, _newInterestRate);

        // emit TierUpdated(tierId, newLoanAmount, newInterestRate, newLoanPeriod);
    }

    /*//////////////////////////////////////////////////////////////
                          LOANS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Request for uncolleteralized and receive USDC
    /// @param _tier tier of loan to request
    /// @dev Checks msg.sender's NFT status, if they have an eligible tier and no defaults
    /// @dev Checks msg.sender if they have a V1 NFT to mint a soulbound NFT for them
    function requestLoan(uint8 _tier) external nonReentrant {
        Tier memory tierInfo = tiers[_tier];
        if (tierInfo.loanAmount == 0) {
            revert Errors.TierNotExists();
        }
        if (hasActiveLoan(msg.sender)) {
            revert Errors.LoanActive();
        }
        uint256 tokenId = soulboundNFT.userToId(msg.sender);

        if (tokenId == 0) {
            uint256 v1TokenId = v1.userNFT(msg.sender);
            if (v1TokenId == 0) {
                revert Errors.NoMagnifyNFT();
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
            revert Errors.TierInsufficient();
        }

        if (data.loansDefaulted > 0) {
            revert Errors.DefaultDetected();
        }

        IERC20 usdc = IERC20(asset());
        uint256 bal = usdc.balanceOf(address(this));
        if (bal < tierInfo.loanAmount) {
            revert Errors.InsufficientLiquidity();
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
        addActiveLoan(newLoan);
        totalLoanAmount += tierInfo.loanAmount;

        uint256 loanOriginationFee = tierInfo.loanAmount * originationFee;

        usdc.safeTransfer(msg.sender, tierInfo.loanAmount - loanOriginationFee);
        usdc.safeTransfer(
            msg.sender,
            loanOriginationFee.mulDiv(treasuryFee, 10000)
        );

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
            revert Errors.NoLoanActive();
        }
        IERC20 usdc = IERC20(asset());
        loan.isActive = false;
        loan.repaymentTimestamp = block.timestamp;

        uint256 interest = loan.loanAmount.mulDiv(loan.interestRate, 10000);
        uint256 totalDue = loan.loanAmount + interest;
        if (block.timestamp <= loan.loanTimestamp + loan.duration) {
            revert Errors.LoanExpired();
        }
        if (permitTransferFrom.permitted.token != address(usdc))
            revert Errors.PermitInvalidToken();
        if (permitTransferFrom.permitted.amount < totalDue)
            revert Errors.PermitInvalidAmount();
        if (transferDetails.requestedAmount != totalDue)
            revert Errors.TransferInvalidAmount();
        if (transferDetails.to != address(this))
            revert Errors.TransferInvalidAddress();
        totalLoanAmount -= loan.loanAmount;
        removeActiveLoan(findActiveLoan(loan.loanID));

        permit2.permitTransferFrom(
            permitTransferFrom,
            transferDetails,
            msg.sender,
            signature
        );

        usdc.safeTransfer(treasury, interest.mulDiv(treasuryFee, 10000));

        // set soulbound info
        soulboundNFT.increaseloanRepayment(loan.tokenId, interest);
        // emit LoanRepaid(tokenId, totalDue, msg.sender);
    }

    /**
     * @notice Repays an active loan using Permit2 for token approval
     * @dev Uses Uniswap's Permit2 for gas-efficient token approvals in a single transaction
     * @dev The loan must be active and not expired, and the caller must be the NFT owner
     */
    function repayDefaultedLoanWithPermit2(
        uint256 _index,
        ISignatureTransfer.PermitTransferFrom calldata permitTransferFrom,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        bytes calldata signature
    ) external nonReentrant {
        // V2 repayment
        LoanData storage loan = v3loans[msg.sender][_index];
        if (!loan.isDefault) {
            revert Errors.NoLoanDefault();
        }
        IERC20 usdc = IERC20(asset());
        loan.isDefault = true;

        uint256 interest = loan.loanAmount.mulDiv(loan.interestRate, 10000);
        uint256 penalty = loan.loanAmount.mulDiv(defaultPenalty, 10000);
        uint256 totalDue = loan.loanAmount + interest + penalty;

        if (permitTransferFrom.permitted.token != address(usdc))
            revert Errors.PermitInvalidToken();
        if (permitTransferFrom.permitted.amount < totalDue)
            revert Errors.PermitInvalidAmount();
        if (transferDetails.requestedAmount != totalDue)
            revert Errors.TransferInvalidAmount();
        if (transferDetails.to != address(this))
            revert Errors.TransferInvalidAddress();

        permit2.permitTransferFrom(
            permitTransferFrom,
            transferDetails,
            msg.sender,
            signature
        );
        usdc.safeTransfer(
            treasury,
            (interest + penalty).mulDiv(treasuryFee, 10000)
        );
        totalDefaults -= loan.loanAmount;
        soulboundNFT.decreaseLoanDefault(loan.tokenId, loan.loanAmount);

        // emit LoanRepaid(tokenId, totalDue, msg.sender);
    }

    function processOutdatedLoans() public nonReentrant {
        if (activeLoans.length == 0) return;
        LoanData memory oldestLoan = activeLoans[activeLoans.length - 1];
        while (
            oldestLoan.loanTimestamp + oldestLoan.duration < block.timestamp
        ) {
            defaultLastLoan(oldestLoan);
            oldestLoan = activeLoans[activeLoans.length - 1];
        }
        return;
    }

    function addActiveLoan(LoanData memory newLoan) internal {
        LoanData memory emptyLoan;
        activeLoans.push(emptyLoan);
        for (uint256 i = activeLoans.length - 1; i > 0; i--) {
            activeLoans[i] = activeLoans[i - 1];
        }
        activeLoans[0] = newLoan;
    }

    function removeActiveLoan(uint256 _index) internal {
        require(_index < activeLoans.length, "index out of bound");

        for (uint256 i = _index; i < activeLoans.length - 1; i++) {
            activeLoans[i] = activeLoans[i + 1];
        }
        activeLoans.pop();
    }

    function defaultLastLoan(LoanData memory oldestLoan) internal {
        totalLoanAmount -= oldestLoan.loanAmount;
        totalDefaults += oldestLoan.loanAmount;

        soulboundNFT.increaseLoanDefault(
            oldestLoan.tokenId,
            oldestLoan.loanAmount
        );
        v3loans[oldestLoan.borrower][v3loans[oldestLoan.borrower].length - 1]
            .isDefault = true;
        v3loans[oldestLoan.borrower][v3loans[oldestLoan.borrower].length - 1]
            .isActive = false;
        activeLoans.pop();
    }

    function findActiveLoan(bytes32 id) internal view returns (uint256 index) {
        for (uint256 i = 0; i < activeLoans.length - 1; i++) {
            if (activeLoans[i].loanID == id) {
                return i;
            }
        }
        revert Errors.LoanIdNotFound();
    }

    function getAllActiveLoans()
        external
        view
        returns (LoanData[] memory allActiveLoans)
    {
        return activeLoans;
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

    function getLoanHistory(
        address _user
    ) external view returns (LoanData[] memory loanHistory) {
        return v3loans[_user];
    }

    /*//////////////////////////////////////////////////////////////
                          VAULT LOGIC
    //////////////////////////////////////////////////////////////*/

    function depositWithPermit2(
        uint256 amount,
        address receiver,
        ISignatureTransfer.PermitTransferFrom calldata permitTransferFrom,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        bytes calldata signature
    ) external returns (uint256) {
        processOutdatedLoans();
        uint256 maxAssets = maxDeposit(receiver);
        if (amount > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, amount, maxAssets);
        }
        IERC20 usdc = IERC20(asset());
        if (permitTransferFrom.permitted.token != address(usdc))
            revert Errors.PermitInvalidToken();
        if (permitTransferFrom.permitted.amount < amount)
            revert Errors.PermitInvalidAmount();
        if (transferDetails.requestedAmount != amount)
            revert Errors.TransferInvalidAmount();
        if (transferDetails.to != address(this))
            revert Errors.TransferInvalidAddress();

        uint256 shares = previewDeposit(amount);

        permit2.permitTransferFrom(
            permitTransferFrom,
            transferDetails,
            msg.sender,
            signature
        );
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, amount, shares);

        return shares;
    }

    /// @inheritdoc ERC4626Upgradeable
    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        processOutdatedLoans();
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        uint256 shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);

        return shares;
    }

    /// @inheritdoc ERC4626Upgradeable
    function mint(uint256 shares, address receiver) public override returns (uint256) {
        processOutdatedLoans();
        uint256 maxShares = maxMint(receiver);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxMint(receiver, shares, maxShares);
        }

        uint256 assets = previewMint(shares);
        _deposit(_msgSender(), receiver, assets, shares);

        return assets;
    }

    /// @inheritdoc ERC4626Upgradeable
    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
        processOutdatedLoans();
        uint256 maxAssets = maxWithdraw(owner);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        }

        uint256 shares = previewWithdraw(assets);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return shares;
    }

    /// @inheritdoc ERC4626Upgradeable
    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {
        processOutdatedLoans();
        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        }

        uint256 assets = previewRedeem(shares);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return assets;
    }


    /// @inheritdoc ERC4626Upgradeable
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) + totalLoanAmount;
    }
}

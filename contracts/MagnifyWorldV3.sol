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
    IPermit2 public permit2;
    uint256 internal totalLoanAmount;
    uint256 internal totalDefaults;
    uint256 public loanAmount;
    uint256 public loanPeriod;
    uint256 public startTimestamp;
    uint256 public endTimestamp;
    address public treasury;
    uint16 public treasuryFee;
    uint16 public originationFee;
    uint16 public loanInterestRate;
    uint16 public defaultPenalty;
    uint16 public earlyExitFee;
    uint8 public tier;
    LoanData[] public activeLoans;
    mapping(address => LoanData[]) public loans;

    /// Initilize function
    /// @param _name Name of liquidity token
    /// @param _symbol Symbol of liquidity token
    /// @param _asset USDC address
    /// @param _permit2 Permit2 address
    /// @param _soulboundNFT MagnifySoulboundNFT address
    /// @param _treasury Treasury address
    function initialize(
        string calldata _name,
        string calldata _symbol,
        IERC20 _asset,
        IPermit2 _permit2,
        IMagnifyWorldSoulboundNFT _soulboundNFT,
        address _treasury
    ) external initializer {
        __ERC20_init(_name, _symbol);
        __ERC4626_init(_asset);
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        permit2 = _permit2;
        soulboundNFT = _soulboundNFT;
        treasury = _treasury;
        treasuryFee = 2000;
        defaultPenalty = 1000;
        originationFee = 1000;
        earlyExitFee = 100;
    }

    function setup(
        uint256 _startTimestamp,
        uint256 _endTimestamp,
        uint256 _loanAmount,
        uint256 _loanPeriod,
        uint16 _loanInterest,
        uint8 _tier
    ) external onlyOwner {
        if (loanAmount != 0) revert Errors.AlreadySetup();
        if (_startTimestamp < block.timestamp) revert Errors.InvalidStartTime();
        if (_endTimestamp <= _startTimestamp) revert Errors.InvalidEndTime();
        if (_loanAmount == 0) revert Errors.InputZero();
        if (_loanPeriod == 0) revert Errors.InputZero();
        if (_loanInterest > 10000) revert Errors.InvalidPercentage();
        startTimestamp = _startTimestamp;
        endTimestamp = _endTimestamp;
        loanAmount = _loanAmount;
        loanPeriod = _loanPeriod;
        loanInterestRate = _loanInterest;
        tier = _tier;
    }

    /*//////////////////////////////////////////////////////////////
                          LOANS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Request for uncolleteralized and receive USDC
    /// @dev Checks msg.sender's NFT status, if they have an eligible tier and no defaults
    /// @dev Checks msg.sender if they have a V1 NFT to mint a soulbound NFT for them
    function requestLoan() external nonReentrant {
        if (
            block.timestamp < startTimestamp ||
            block.timestamp >= endTimestamp - loanPeriod
        ) {
            revert Errors.PoolNotActive();
        }
        if (hasActiveLoan(msg.sender)) revert Errors.LoanActive();
        uint256 tokenId = soulboundNFT.userToId(msg.sender);
        if (tokenId == 0) {
            revert Errors.NoMagnifyNFT();
        }
        checkNFTValid(tokenId);
        IERC20 usdc = IERC20(asset());
        uint256 bal = usdc.balanceOf(address(this));
        if (bal < loanAmount) {
            revert Errors.InsufficientLiquidity();
        }
        uint256 userLoanHistoryLength = loans[msg.sender].length;
        // Issue loan
        LoanData memory newLoan = LoanData(
            keccak256(abi.encode(msg.sender, userLoanHistoryLength)),
            tokenId,
            block.timestamp,
            0,
            msg.sender,
            false,
            true
        );

        loans[msg.sender].push(newLoan);
        addActiveLoan(newLoan);
        totalLoanAmount += loanAmount;
        soulboundNFT.addNewLoan(tokenId, userLoanHistoryLength);

        uint256 loanOriginationFee = loanAmount * originationFee;

        usdc.safeTransfer(msg.sender, loanAmount - loanOriginationFee);
        usdc.safeTransfer(
            treasury,
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
        LoanData memory loan = loans[msg.sender][loans[msg.sender].length - 1];
        if (!loan.isActive) {
            revert Errors.NoLoanActive();
        }
        if (block.timestamp <= loan.loanTimestamp + loanPeriod) {
            revert Errors.LoanExpired();
        }
        IERC20 usdc = IERC20(asset());
        uint256 interest = loanAmount.mulDiv(loanInterestRate, 10000);
        uint256 totalDue = loanAmount + interest;
        checkPermitDataValid(permitTransferFrom, transferDetails, totalDue);

        totalLoanAmount -= loanAmount;
        removeActiveLoan(findActiveLoan(loan.loanID));
        loan.isActive = false;
        loan.repaymentTimestamp = block.timestamp;
        loans[msg.sender][loans[msg.sender].length - 1] = loan;
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
        LoanData storage loan = loans[msg.sender][_index];
        if (!loan.isDefault) {
            revert Errors.NoLoanDefault();
        }
        IERC20 usdc = IERC20(asset());
        loan.isDefault = true;

        uint256 interest = loanAmount.mulDiv(loanInterestRate, 10000);
        uint256 penalty = loanAmount.mulDiv(defaultPenalty, 10000);
        uint256 totalDue = loanAmount + interest + penalty;

        checkPermitDataValid(permitTransferFrom, transferDetails, totalDue);

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
        totalDefaults -= loanAmount;
        soulboundNFT.decreaseLoanDefault(loan.tokenId, loanAmount);

        // emit LoanRepaid(tokenId, totalDue, msg.sender);
    }

    function processOutdatedLoans() public nonReentrant {
        if (activeLoans.length == 0) return;
        LoanData memory oldestLoan = activeLoans[activeLoans.length - 1];
        while (oldestLoan.loanTimestamp + loanPeriod < block.timestamp) {
            defaultLastLoan(oldestLoan);
            oldestLoan = activeLoans[activeLoans.length - 1];
        }
        return;
    }

    // internal

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
        totalLoanAmount -= loanAmount;
        totalDefaults += loanAmount;

        soulboundNFT.increaseLoanDefault(oldestLoan.tokenId, loanAmount);
        loans[oldestLoan.borrower][loans[oldestLoan.borrower].length - 1]
            .isDefault = true;
        loans[oldestLoan.borrower][loans[oldestLoan.borrower].length - 1]
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

    function checkNFTValid(uint256 tokenId) internal view {
        // get tier and NFT data
        IMagnifyWorldSoulboundNFT.NFTData memory data = soulboundNFT.getNFTData(
            tokenId
        );

        if (data.ongoingLoan) {
            revert Errors.LoanActive();
        }

        if (data.tier < tier) {
            revert Errors.TierInsufficient();
        }

        if (data.loansDefaulted > 0) {
            revert Errors.DefaultDetected();
        }
    }

    function checkPermitDataValid(
        ISignatureTransfer.PermitTransferFrom calldata permitTransferFrom,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        uint256 amount
    ) internal view {
        if (permitTransferFrom.permitted.token != asset())
            revert Errors.PermitInvalidToken();
        if (permitTransferFrom.permitted.amount < amount)
            revert Errors.PermitInvalidAmount();
        if (transferDetails.requestedAmount != amount)
            revert Errors.TransferInvalidAmount();
        if (transferDetails.to != address(this))
            revert Errors.TransferInvalidAddress();
    }

    // external view

    function getAllActiveLoans()
        external
        view
        returns (LoanData[] memory allActiveLoans)
    {
        return activeLoans;
    }

    function hasActiveLoan(address _user) public view returns (bool) {
        uint256 length = loans[_user].length;
        if (length == 0) return false;

        LoanData memory latestLoan = loans[_user][length - 1];

        return latestLoan.isActive;
    }

    function getActiveLoan(
        address _user
    ) external view returns (LoanData memory loan) {
        if (hasActiveLoan(_user)) {
            return loans[_user][loans[_user].length - 1];
        } else {
            LoanData memory emptyLoan;
            return emptyLoan;
        }
    }

    function getLoan(
        address _user,
        uint256 _index
    ) external view returns (LoanData memory loan) {
        if (_index >= loans[_user].length) {
            revert Errors.OutOfBoundsArray();
        }
        return loans[_user][_index];
    }

    function getLoanHistory(
        address _user
    ) external view returns (LoanData[] memory loanHistory) {
        return loans[_user];
    }

    /*//////////////////////////////////////////////////////////////
                          DURATION LOGIC
    //////////////////////////////////////////////////////////////*/

    modifier onlyValidDepositTime() {
        if (block.timestamp >= endTimestamp - loanPeriod) {
            revert Errors.PoolNotActive();
        }
        _;
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
    ) external onlyValidDepositTime returns (uint256) {
        processOutdatedLoans();
        uint256 maxAssets = maxDeposit(receiver);
        if (amount > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, amount, maxAssets);
        }
        checkPermitDataValid(permitTransferFrom, transferDetails, amount);

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
    function deposit(
        uint256 assets,
        address receiver
    ) public override onlyValidDepositTime returns (uint256) {
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
    function mint(
        uint256 shares,
        address receiver
    ) public override onlyValidDepositTime returns (uint256) {
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
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256) {
        processOutdatedLoans();
        uint256 maxAssets = maxWithdraw(owner);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        }

        uint256 shares = previewWithdraw(assets);

        if (block.timestamp > endTimestamp) {
            _withdraw(_msgSender(), receiver, owner, assets, shares);
        } else if (block.timestamp < startTimestamp) {
            _earlyWithdraw(_msgSender(), receiver, owner, assets, shares);
        } else {
            revert Errors.NoWithdrawWhenActive();
        }

        return shares;
    }

    /// @inheritdoc ERC4626Upgradeable
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256) {
        processOutdatedLoans();
        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        }

        uint256 assets = previewRedeem(shares);
        if (block.timestamp > endTimestamp) {
            _withdraw(_msgSender(), receiver, owner, assets, shares);
        } else if (block.timestamp < startTimestamp) {
            _earlyWithdraw(_msgSender(), receiver, owner, assets, shares);
        } else {
            revert Errors.NoWithdrawWhenActive();
        }

        return assets;
    }

    function _earlyWithdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal {
        uint256 fee = assets.mulDiv(earlyExitFee, 10000);

        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }
        _burn(owner, shares);
        IERC20(asset()).safeTransfer(receiver, assets - fee);
        IERC20(asset()).safeTransfer(treasury, fee);

        emit Withdraw(caller, receiver, owner, assets - fee, shares);
    }

    /// @inheritdoc ERC4626Upgradeable
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) + totalLoanAmount;
    }

    function getTotalBorrows() external view returns (uint256) {
        return totalLoanAmount;
    }

    function getTotalDefaults() external view returns (uint256) {
        return totalDefaults;
    }

    /*//////////////////////////////////////////////////////////////
                          Owner setters
    //////////////////////////////////////////////////////////////*/

    function setLoanAmount(uint256 _loanAmount) external onlyOwner {
        if (_loanAmount == 0) revert Errors.InputZero();
        loanAmount = _loanAmount;
    }

    function setLoanPeriod(uint256 _loanPeriod) external onlyOwner {
        if (_loanPeriod == 0) revert Errors.InputZero();
        loanPeriod = _loanPeriod;
    }

    function setStartTimestamp(uint256 _startTimestamp) external onlyOwner {
        if (_startTimestamp < block.timestamp) revert Errors.InvalidStartTime();
        startTimestamp = _startTimestamp;
    }

    function setEndTimestamp(uint256 _endTimestamp) external onlyOwner {
        if (_endTimestamp <= startTimestamp) revert Errors.InvalidEndTime();
        endTimestamp = _endTimestamp;
    }

    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert Errors.InputZero();
        treasury = _treasury;
    }

    function setTreasuryFee(uint16 _treasuryFee) external onlyOwner {
        if (_treasuryFee > 10000) revert Errors.InvalidPercentage();
        treasuryFee = _treasuryFee;
    }

    function setOriginationFee(uint16 _originationFee) external onlyOwner {
        if (_originationFee > 10000) revert Errors.InvalidPercentage();
        originationFee = _originationFee;
    }

    function setLoanInterestRate(uint16 _loanInterestRate) external onlyOwner {
        if (_loanInterestRate > 10000) revert Errors.InvalidPercentage();
        if (block.timestamp >= startTimestamp && block.timestamp < endTimestamp)
            revert Errors.PoolActive();

        loanInterestRate = _loanInterestRate;
    }

    function setDefaultPenalty(uint16 _defaultPenalty) external onlyOwner {
        if (_defaultPenalty > 10000) revert Errors.InvalidPercentage();
        defaultPenalty = _defaultPenalty;
    }

    function setEarlyExitFee(uint16 _earlyExitFee) external onlyOwner {
        if (_earlyExitFee > 10000) revert Errors.InvalidPercentage();
        earlyExitFee = _earlyExitFee;
    }

    function setTier(uint8 _tier) external onlyOwner {
        tier = _tier;
    }
}

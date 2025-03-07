// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMagnifyWorldV3} from "./interfaces/IMagnifyWorldV3.sol";
import {IMagnifyWorldSoulboundNFT} from "./interfaces/IMagnifyWorldSoulboundNFT.sol";

contract MagnifyWorldV3 is
    IMagnifyWorldV3,
    ERC20Upgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for ERC20Upgradeable;
    using Math for uint256;

    ERC20Upgradeable public asset;
    IMagnifyWorldSoulboundNFT public soulboundNFT;
    uint256 public totalLoanAmount;
    address public treasury;
    uint16 public treasuryFee;
    uint8 public tierCount;

    mapping(address => LoanData[]) public V3loans;
    mapping(uint8 => Tier) public tiers;

    uint256[50] __gap;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposit(
        address indexed caller,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    /*//////////////////////////////////////////////////////////////
                               Initializer
    //////////////////////////////////////////////////////////////*/

    function initialize(
        string calldata _name,
        string calldata _symbol
    ) external initializer {
        __Ownable_init(msg.sender);
        __ERC20_init(_name, _symbol);
        __ReentrancyGuard_init();
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function deposit(
        uint256 assets,
        address receiver
    ) public virtual returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    function mint(
        uint256 shares,
        address receiver
    ) public virtual returns (uint256 assets) {
        assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual returns (uint256 shares) {
        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares); // Saves gas for limited approvals.
        }

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual returns (uint256 assets) {
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares); // Saves gas for limited approvals.
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view virtual returns (uint256) {
        return 1;
    }

    function convertToShares(
        uint256 assets
    ) public view virtual returns (uint256) {
        uint256 supply = totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : assets.mulDiv(supply, totalAssets());
    }

    function convertToAssets(
        uint256 shares
    ) public view virtual returns (uint256) {
        uint256 supply = totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : shares.mulDiv(totalAssets(), supply);
    }

    function previewDeposit(
        uint256 assets
    ) public view virtual returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view virtual returns (uint256) {
        uint256 supply = totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        return
            supply == 0
                ? shares
                : shares.mulDiv(totalAssets(), supply, Math.Rounding.Ceil);
    }

    function previewWithdraw(
        uint256 assets
    ) public view virtual returns (uint256) {
        uint256 supply = totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        return
            supply == 0
                ? assets
                : assets.mulDiv(supply, totalAssets(), Math.Rounding.Ceil);
    }

    function previewRedeem(
        uint256 shares
    ) public view virtual returns (uint256) {
        return convertToAssets(shares);
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function maxDeposit(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view virtual returns (uint256) {
        return convertToAssets(balanceOf(owner));
    }

    function maxRedeem(address owner) public view virtual returns (uint256) {
        return balanceOf(owner);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function beforeWithdraw(uint256 assets, uint256 shares) internal virtual {
        return;
    }

    function afterDeposit(uint256 assets, uint256 shares) internal virtual {
        return;
    }

    /*//////////////////////////////////////////////////////////////
                          TIERS LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Adds a new tier with specified parameters
     * @param loanAmount Amount that can be borrowed in this tier
     * @param interestRate Interest rate in basis points
     * @param loanPeriod Loan duration in seconds
     */
    function addTier(
        uint256 loanAmount,
        uint256 interestRate,
        uint256 loanPeriod
    ) external onlyOwner {
        if (loanAmount == 0 || interestRate == 0 || loanPeriod == 0)
            revert("Invalid tier parameters");

        tierCount++;
        tiers[tierCount] = Tier(loanAmount, interestRate, loanPeriod);

        // emit TierAdded(tierCount, loanAmount, interestRate, loanPeriod);
    }

    /**
     * @dev Updates an existing tier's parameters
     * @param tierId ID of the tier to update
     * @param newLoanAmount New loan amount
     * @param newInterestRate New interest rate
     * @param newLoanPeriod New loan period
     */
    function updateTier(
        uint8 tierId,
        uint256 newLoanAmount,
        uint256 newInterestRate,
        uint256 newLoanPeriod
    ) external onlyOwner {
        if (tierId > tierCount) revert("Tier does not exist");
        if (newLoanAmount == 0 || newInterestRate == 0 || newLoanPeriod == 0)
            revert("Invalid tier parameters");

        tiers[tierId] = Tier(newLoanAmount, newInterestRate, newLoanPeriod);

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
        return;
    }

    function getActiveLoan() external {
        return;
    }

    function getLoanHistory() external {
        return;
    }
}

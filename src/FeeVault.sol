// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Auth, Authority} from "superlib/auth/Auth.sol";
import {ERC20} from "superlib/core/ERC20.sol";
import {ERC4626} from "superlib/core/ERC4626.sol";
import {ReentrancyGuard} from "superlib/security/ReentrancyLib.sol";
import {SafeTransferLib} from "superlib/transfer/SafeTransferLib.sol";
import {MathLib} from "superlib/utils/MathLib.sol";

/// @title FeeVault
/// @notice ERC4626 tokenized vault with fee collection and rewards distribution
/// @dev Uses Superlib Auth for role-based access, inflation attack protection via dead shares
contract FeeVault is ERC4626, Auth, ReentrancyGuard {

    using SafeTransferLib for address;
    using MathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MAX_FEE = 1000;
    uint256 public constant FEE_DENOMINATOR = 10_000;
    uint256 public constant MINIMUM_SHARES = 1000;
    uint256 public constant MINIMUM_DEPOSIT = 1000;
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 public depositFee;
    uint256 public withdrawFee;
    uint256 public performanceFee;
    address public feeRecipient;

    uint256 public rewardRate;
    uint256 public rewardReserves;
    uint256 public lastRewardTime;
    uint256 public rewardPerShareStored;
    mapping(address => uint256) public userRewardPerSharePaid;
    mapping(address => uint256) public rewards;

    uint256 public totalDeposited;
    uint256 public totalWithdrawn;

    bool public paused;
    bool public deadSharesInitialized;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event DepositFeeUpdated(uint256 oldFee, uint256 newFee);
    event WithdrawFeeUpdated(uint256 oldFee, uint256 newFee);
    event PerformanceFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event FeesCollected(address indexed recipient, uint256 amount);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);
    event RewardsClaimed(address indexed user, uint256 amount);
    event RewardsAdded(uint256 amount);
    event Paused(address account);
    event Unpaused(address account);
    event EmergencyWithdraw(address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error FeeExceedsMax(uint256 fee, uint256 maxFee);
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientRewards();
    error DepositTooSmall(uint256 amount, uint256 minimum);
    error InsufficientRewardReserves(uint256 requested, uint256 available);
    error ContractPaused();
    error AlreadyInitialized();
    error NotInitialized();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        address _feeRecipient,
        address _owner,
        Authority _authority
    ) ERC4626(_asset, _name, _symbol) Auth(_owner, _authority) {
        if (_feeRecipient == address(0)) revert ZeroAddress();

        feeRecipient = _feeRecipient;
        lastRewardTime = block.timestamp;

        // Inflation attack protection: mint dead shares
        // Note: Deployer must deposit MINIMUM_SHARES worth of assets after deployment
        // or use a factory that atomically deposits
        _mint(DEAD_ADDRESS, MINIMUM_SHARES);
    }

    /// @notice Initialize vault with dead share assets (call after deployment)
    /// @dev SECURITY: One-time only, owner-restricted to prevent front-running
    function initializeDeadShares() external requiresAuth {
        if (deadSharesInitialized) revert AlreadyInitialized();
        if (totalAssets() != 0) revert AlreadyInitialized();

        deadSharesInitialized = true;
        address(asset).safeTransferFrom(msg.sender, address(this), MINIMUM_SHARES);
    }

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    function _requireNotPaused() internal view {
        if (paused) revert ContractPaused();
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT/WITHDRAW
    //////////////////////////////////////////////////////////////*/

    function deposit(
        uint256 assets,
        address receiver
    ) public virtual override nonReentrant whenNotPaused returns (uint256 shares) {
        if (assets < MINIMUM_DEPOSIT) revert DepositTooSmall(assets, MINIMUM_DEPOSIT);

        _updateReward(receiver);

        uint256 fee = (assets * depositFee) / FEE_DENOMINATOR;
        uint256 assetsAfterFee = assets - fee;

        shares = previewDeposit(assetsAfterFee);
        if (shares == 0) revert ZeroAmount();

        address(asset).safeTransferFrom(msg.sender, address(this), assets);

        if (fee > 0) {
            address(asset).safeTransfer(feeRecipient, fee);
            emit FeesCollected(feeRecipient, fee);
        }

        _mint(receiver, shares);
        totalDeposited += assetsAfterFee;

        emit Deposit(msg.sender, receiver, assetsAfterFee, shares);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address _owner
    ) public virtual override nonReentrant whenNotPaused requiresAuth returns (uint256 shares) {
        _updateReward(_owner);

        shares = previewWithdraw(assets);

        if (msg.sender != _owner) {
            uint256 allowed = allowance[_owner][msg.sender];
            if (allowed != type(uint256).max) allowance[_owner][msg.sender] = allowed - shares;
        }

        _burn(_owner, shares);

        uint256 fee = (assets * withdrawFee) / FEE_DENOMINATOR;
        uint256 assetsAfterFee = assets - fee;

        if (fee > 0) {
            address(asset).safeTransfer(feeRecipient, fee);
            emit FeesCollected(feeRecipient, fee);
        }

        address(asset).safeTransfer(receiver, assetsAfterFee);
        totalWithdrawn += assets;

        emit Withdraw(msg.sender, receiver, _owner, assets, shares);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address _owner
    ) public virtual override nonReentrant whenNotPaused requiresAuth returns (uint256 assets) {
        _updateReward(_owner);

        if (msg.sender != _owner) {
            uint256 allowed = allowance[_owner][msg.sender];
            if (allowed != type(uint256).max) allowance[_owner][msg.sender] = allowed - shares;
        }

        assets = previewRedeem(shares);
        if (assets == 0) revert ZeroAmount();

        _burn(_owner, shares);

        uint256 fee = (assets * withdrawFee) / FEE_DENOMINATOR;
        uint256 assetsAfterFee = assets - fee;

        if (fee > 0) {
            address(asset).safeTransfer(feeRecipient, fee);
            emit FeesCollected(feeRecipient, fee);
        }

        address(asset).safeTransfer(receiver, assetsAfterFee);
        totalWithdrawn += assets;

        emit Withdraw(msg.sender, receiver, _owner, assets, shares);
    }

    /*//////////////////////////////////////////////////////////////
                             REWARDS LOGIC
    //////////////////////////////////////////////////////////////*/

    function claimRewards() external nonReentrant whenNotPaused returns (uint256 reward) {
        _updateReward(msg.sender);
        reward = rewards[msg.sender];

        if (reward == 0) revert InsufficientRewards();
        if (reward > rewardReserves) revert InsufficientRewardReserves(reward, rewardReserves);

        rewards[msg.sender] = 0;
        rewardReserves -= reward;

        address(asset).safeTransfer(msg.sender, reward);
        emit RewardsClaimed(msg.sender, reward);
    }

    function addRewards(
        uint256 amount
    ) external requiresAuth {
        if (amount == 0) revert ZeroAmount();
        address(asset).safeTransferFrom(msg.sender, address(this), amount);
        rewardReserves += amount;
        emit RewardsAdded(amount);
    }

    function earned(
        address account
    ) public view returns (uint256) {
        return (balanceOf[account] * (rewardPerShare() - userRewardPerSharePaid[account])) / 1e18 + rewards[account];
    }

    function rewardPerShare() public view returns (uint256) {
        if (totalSupply == 0) return rewardPerShareStored;
        return rewardPerShareStored + ((block.timestamp - lastRewardTime) * rewardRate * 1e18) / totalSupply;
    }

    function _updateReward(
        address account
    ) internal {
        // G-2: Short-circuit when rewards disabled and no supply
        if (rewardRate == 0 && totalSupply == 0) return;

        rewardPerShareStored = rewardPerShare();
        lastRewardTime = block.timestamp;
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerSharePaid[account] = rewardPerShareStored;
        }
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setDepositFee(
        uint256 newFee
    ) external requiresAuth {
        if (newFee > MAX_FEE) revert FeeExceedsMax(newFee, MAX_FEE);
        emit DepositFeeUpdated(depositFee, newFee);
        depositFee = newFee;
    }

    function setWithdrawFee(
        uint256 newFee
    ) external requiresAuth {
        if (newFee > MAX_FEE) revert FeeExceedsMax(newFee, MAX_FEE);
        emit WithdrawFeeUpdated(withdrawFee, newFee);
        withdrawFee = newFee;
    }

    function setPerformanceFee(
        uint256 newFee
    ) external requiresAuth {
        if (newFee > MAX_FEE) revert FeeExceedsMax(newFee, MAX_FEE);
        emit PerformanceFeeUpdated(performanceFee, newFee);
        performanceFee = newFee;
    }

    function setFeeRecipient(
        address newRecipient
    ) external requiresAuth {
        if (newRecipient == address(0)) revert ZeroAddress();
        emit FeeRecipientUpdated(feeRecipient, newRecipient);
        feeRecipient = newRecipient;
    }

    function setRewardRate(
        uint256 newRate
    ) external requiresAuth {
        _updateReward(address(0));
        emit RewardRateUpdated(rewardRate, newRate);
        rewardRate = newRate;
    }

    function pause() external requiresAuth {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external requiresAuth {
        paused = false;
        emit Unpaused(msg.sender);
    }

    function emergencyWithdraw(
        address to,
        uint256 amount
    ) external requiresAuth {
        if (to == address(0)) revert ZeroAddress();
        address(asset).safeTransfer(to, amount);
        emit EmergencyWithdraw(to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view virtual override returns (uint256) {
        return SafeTransferLib.balanceOf(address(asset), address(this)) - rewardReserves;
    }

}

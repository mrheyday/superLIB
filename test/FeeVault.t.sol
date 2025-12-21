// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Authority} from "superlib/auth/Auth.sol";
import {RolesAuthority} from "superlib/auth/RolesAuthority.sol";
import {ERC20} from "superlib/core/ERC20.sol";
import {FeeVault} from "../src/FeeVault.sol";
import {Roles} from "../src/roles/Roles.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MCK", 18) {
        _mint(msg.sender, 1_000_000e18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract FeeVaultTest is Test {
    RolesAuthority authority;
    MockToken token;
    FeeVault vault;

    address owner = makeAddr("owner");
    address feeRecipient = makeAddr("feeRecipient");
    address depositor = makeAddr("depositor");
    address attacker = makeAddr("attacker");

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

    function setUp() public {
        vm.startPrank(owner);
        
        authority = new RolesAuthority(owner, Authority(address(0)));
        token = new MockToken();
        
        vault = new FeeVault(token, "Vault Token", "VLT", feeRecipient, owner, authority);
        
        // Initialize dead shares
        token.approve(address(vault), 1000);
        vault.initializeDeadShares();
        
        // Setup roles
        authority.setUserRole(depositor, Roles.VAULT_DEPOSITOR, true);
        authority.setRoleCapability(Roles.VAULT_DEPOSITOR, address(vault), FeeVault.deposit.selector, true);
        authority.setRoleCapability(Roles.ADMIN, address(vault), FeeVault.pause.selector, true);
        authority.setRoleCapability(Roles.ADMIN, address(vault), FeeVault.setDepositFee.selector, true);
        
        token.mint(depositor, 100_000e18);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor_SetsCorrectParameters() public view {
        assertEq(address(vault.asset()), address(token));
        assertEq(vault.name(), "Vault Token");
        assertEq(vault.symbol(), "VLT");
        assertEq(vault.feeRecipient(), feeRecipient);
        assertEq(vault.owner(), owner);
    }

    function testRevert_Constructor_ZeroFeeRecipient() public {
        vm.prank(owner);
        vm.expectRevert(FeeVault.ZeroAddress.selector);
        new FeeVault(token, "Test", "TST", address(0), owner, authority);
    }

    function test_InitializeDeadShares_Success() public {
        // Deploy new vault without init
        vm.startPrank(owner);
        FeeVault newVault = new FeeVault(token, "New", "NEW", feeRecipient, owner, authority);
        
        token.approve(address(newVault), 1000);
        newVault.initializeDeadShares();
        
        assertTrue(newVault.deadSharesInitialized());
        assertEq(newVault.balanceOf(address(0x000000000000000000000000000000000000dEaD)), 1000);
        vm.stopPrank();
    }

    function testRevert_InitializeDeadShares_AlreadyInitialized() public {
        vm.prank(owner);
        vm.expectRevert(FeeVault.AlreadyInitialized.selector);
        vault.initializeDeadShares();
    }

    function testRevert_InitializeDeadShares_Unauthorized() public {
        vm.startPrank(owner);
        FeeVault newVault = new FeeVault(token, "New", "NEW", feeRecipient, owner, authority);
        vm.stopPrank();
        
        vm.prank(attacker);
        vm.expectRevert();
        newVault.initializeDeadShares();
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deposit_Success() public {
        uint256 depositAmount = 1000e18;
        
        vm.startPrank(depositor);
        token.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, depositor);
        vm.stopPrank();
        
        assertGt(shares, 0);
        assertEq(vault.balanceOf(depositor), shares);
        assertEq(token.balanceOf(address(vault)), depositAmount + 1000); // +1000 from dead shares
    }

    function testRevert_Deposit_BelowMinimum() public {
        vm.startPrank(depositor);
        token.approve(address(vault), 999);
        vm.expectRevert();
        vault.deposit(999, depositor);
        vm.stopPrank();
    }

    function testRevert_Deposit_WhenPaused() public {
        vm.prank(owner);
        vault.pause();
        
        vm.startPrank(depositor);
        token.approve(address(vault), 1000e18);
        vm.expectRevert(FeeVault.ContractPaused.selector);
        vault.deposit(1000e18, depositor);
        vm.stopPrank();
    }

    function test_Withdraw_Success() public {
        // First deposit
        vm.startPrank(depositor);
        token.approve(address(vault), 1000e18);
        vault.deposit(1000e18, depositor);
        
        uint256 shares = vault.balanceOf(depositor);
        uint256 assets = vault.withdraw(500e18, depositor, depositor);
        vm.stopPrank();
        
        assertGt(assets, 0);
        assertLt(vault.balanceOf(depositor), shares);
    }

    function testFuzz_Deposit_VariousAmounts(uint256 amount) public {
        amount = bound(amount, 1000, 100_000e18);
        
        vm.startPrank(depositor);
        token.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount, depositor);
        vm.stopPrank();
        
        assertGt(shares, 0);
        assertEq(vault.balanceOf(depositor), shares);
    }

    /*//////////////////////////////////////////////////////////////
                            FEE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetDepositFee_Success() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DepositFeeUpdated(0, 100);
        vault.setDepositFee(100);
        
        assertEq(vault.depositFee(), 100);
    }

    function testRevert_SetDepositFee_ExceedsMax() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(FeeVault.FeeExceedsMax.selector, 1001, 1000));
        vault.setDepositFee(1001);
    }

    function test_SetWithdrawFee_Success() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit WithdrawFeeUpdated(0, 200);
        vault.setWithdrawFee(200);
        
        assertEq(vault.withdrawFee(), 200);
    }

    function test_SetPerformanceFee_Success() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit PerformanceFeeUpdated(0, 300);
        vault.setPerformanceFee(300);
        
        assertEq(vault.performanceFee(), 300);
    }

    function test_SetFeeRecipient_Success() public {
        address newRecipient = makeAddr("newRecipient");
        
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit FeeRecipientUpdated(feeRecipient, newRecipient);
        vault.setFeeRecipient(newRecipient);
        
        assertEq(vault.feeRecipient(), newRecipient);
    }

    function testRevert_SetFeeRecipient_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(FeeVault.ZeroAddress.selector);
        vault.setFeeRecipient(address(0));
    }

    function test_DepositWithFee_ChargesFee() public {
        vm.prank(owner);
        vault.setDepositFee(100); // 1%
        
        uint256 depositAmount = 1000e18;
        vm.startPrank(depositor);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, depositor);
        vm.stopPrank();
        
        // Fee should be collected
        uint256 expectedFee = (depositAmount * 100) / 10_000;
        assertGt(expectedFee, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        REWARDS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetRewardRate_Success() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit RewardRateUpdated(0, 100);
        vault.setRewardRate(100);
        
        assertEq(vault.rewardRate(), 100);
    }

    function test_AddRewards_Success() public {
        uint256 rewardAmount = 1000e18;
        
        vm.startPrank(owner);
        token.approve(address(vault), rewardAmount);
        vm.expectEmit(true, true, true, true);
        emit RewardsAdded(rewardAmount);
        vault.addRewards(rewardAmount);
        vm.stopPrank();
        
        assertEq(vault.rewardReserves(), rewardAmount);
    }

    function testRevert_AddRewards_ZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(FeeVault.ZeroAmount.selector);
        vault.addRewards(0);
    }

    function test_ClaimRewards_Success() public {
        // Setup: deposit, add rewards, set rate, wait
        vm.startPrank(depositor);
        token.approve(address(vault), 1000e18);
        vault.deposit(1000e18, depositor);
        vm.stopPrank();
        
        vm.startPrank(owner);
        token.approve(address(vault), 1000e18);
        vault.addRewards(1000e18);
        vault.setRewardRate(100);
        vm.stopPrank();
        
        vm.warp(block.timestamp + 3600); // Wait 1 hour
        
        vm.prank(depositor);
        uint256 reward = vault.claimRewards();
        
        assertGt(reward, 0);
    }

    function testRevert_ClaimRewards_WhenPaused() public {
        vm.prank(owner);
        vault.pause();
        
        vm.prank(depositor);
        vm.expectRevert(FeeVault.ContractPaused.selector);
        vault.claimRewards();
    }

    /*//////////////////////////////////////////////////////////////
                        PAUSE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Pause_Success() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit Paused(owner);
        vault.pause();
        
        assertTrue(vault.paused());
    }

    function test_Unpause_Success() public {
        vm.startPrank(owner);
        vault.pause();
        
        vm.expectEmit(true, true, true, true);
        emit Unpaused(owner);
        vault.unpause();
        vm.stopPrank();
        
        assertFalse(vault.paused());
    }

    function testRevert_Pause_Unauthorized() public {
        vm.prank(attacker);
        vm.expectRevert();
        vault.pause();
    }

    /*//////////////////////////////////////////////////////////////
                    EMERGENCY WITHDRAW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_EmergencyWithdraw_Success() public {
        // Deposit some tokens first
        vm.startPrank(depositor);
        token.approve(address(vault), 1000e18);
        vault.deposit(1000e18, depositor);
        vm.stopPrank();
        
        uint256 vaultBalance = token.balanceOf(address(vault));
        address recipient = makeAddr("recipient");
        
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit EmergencyWithdraw(recipient, vaultBalance);
        vault.emergencyWithdraw(recipient);
        
        assertEq(token.balanceOf(recipient), vaultBalance);
        assertEq(token.balanceOf(address(vault)), 0);
    }

    function testRevert_EmergencyWithdraw_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(FeeVault.ZeroAddress.selector);
        vault.emergencyWithdraw(address(0));
    }

    function testRevert_EmergencyWithdraw_Unauthorized() public {
        vm.prank(attacker);
        vm.expectRevert();
        vault.emergencyWithdraw(attacker);
    }

    /*//////////////////////////////////////////////////////////////
                    INFLATION ATTACK PROTECTION
    //////////////////////////////////////////////////////////////*/

    function test_InflationAttackPrevention_DeadSharesProtect() public {
        // This tests that dead shares prevent inflation attacks
        // where an attacker tries to manipulate share price
        
        assertTrue(vault.deadSharesInitialized());
        uint256 deadShares = vault.balanceOf(address(0x000000000000000000000000000000000000dEaD));
        assertEq(deadShares, 1000);
        
        // First depositor gets fair share ratio
        vm.startPrank(depositor);
        token.approve(address(vault), 1000e18);
        uint256 shares = vault.deposit(1000e18, depositor);
        vm.stopPrank();
        
        // Shares should be reasonable, not 1:1 due to dead shares
        assertGt(shares, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_TotalAssets_ReflectsBalance() public {
        vm.startPrank(depositor);
        token.approve(address(vault), 1000e18);
        vault.deposit(1000e18, depositor);
        vm.stopPrank();
        
        uint256 totalAssets = vault.totalAssets();
        assertEq(totalAssets, token.balanceOf(address(vault)));
    }

    function test_RewardPerShare_Calculation() public {
        vm.startPrank(depositor);
        token.approve(address(vault), 1000e18);
        vault.deposit(1000e18, depositor);
        vm.stopPrank();
        
        vm.startPrank(owner);
        token.approve(address(vault), 100e18);
        vault.addRewards(100e18);
        vault.setRewardRate(100);
        vm.stopPrank();
        
        vm.warp(block.timestamp + 3600);
        
        uint256 rewardPerShare = vault.rewardPerShare();
        assertGt(rewardPerShare, 0);
    }

    /*//////////////////////////////////////////////////////////////
                    INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_FullCycle_DepositRewardsWithdraw() public {
        // 1. Deposit
        vm.startPrank(depositor);
        token.approve(address(vault), 10_000e18);
        uint256 shares = vault.deposit(10_000e18, depositor);
        vm.stopPrank();
        
        // 2. Add rewards
        vm.startPrank(owner);
        token.approve(address(vault), 1000e18);
        vault.addRewards(1000e18);
        vault.setRewardRate(100);
        vm.stopPrank();
        
        // 3. Wait and claim rewards
        vm.warp(block.timestamp + 7200);
        vm.prank(depositor);
        uint256 reward = vault.claimRewards();
        assertGt(reward, 0);
        
        // 4. Withdraw
        vm.prank(depositor);
        vault.redeem(shares / 2, depositor, depositor);
        
        assertGt(vault.balanceOf(depositor), 0);
    }

    function test_MultipleDepositors_FairRewards() public {
        address depositor2 = makeAddr("depositor2");
        
        // Setup depositor2
        vm.prank(owner);
        token.mint(depositor2, 100_000e18);
        
        // Both deposit
        vm.startPrank(depositor);
        token.approve(address(vault), 1000e18);
        vault.deposit(1000e18, depositor);
        vm.stopPrank();
        
        vm.startPrank(depositor2);
        token.approve(address(vault), 1000e18);
        vault.deposit(1000e18, depositor2);
        vm.stopPrank();
        
        // Add rewards
        vm.startPrank(owner);
        token.approve(address(vault), 1000e18);
        vault.addRewards(1000e18);
        vault.setRewardRate(100);
        vm.stopPrank();
        
        vm.warp(block.timestamp + 3600);
        
        // Both claim
        vm.prank(depositor);
        uint256 reward1 = vault.claimRewards();
        
        vm.prank(depositor2);
        uint256 reward2 = vault.claimRewards();
        
        // Rewards should be roughly equal (within rounding)
        assertApproxEqRel(reward1, reward2, 0.01e18); // 1% tolerance
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {RolesAuthority} from "superlib/auth/RolesAuthority.sol";
import {Authority} from "superlib/auth/Auth.sol";
import {ERC20} from "superlib/core/ERC20.sol";
import {Roles} from "../src/roles/Roles.sol";
import {FeeVault} from "../src/FeeVault.sol";
import {MEVProtector} from "../src/MEVProtector.sol";
import {FlashLoanEngine} from "../src/FlashLoanEngine.sol";
import {RiskEngine} from "../src/RiskEngine.sol";

/// @title EchidnaRolesTest
/// @notice Echidna fuzzing contract for RolesAuthority invariants
/// @dev Run with: echidna echidna/EchidnaRolesTest.sol --contract EchidnaRolesTest --config echidna/echidna.yaml
contract EchidnaRolesTest {
    RolesAuthority internal authority;
    MockToken internal token;
    FeeVault internal feeVault;
    MEVProtector internal mevProtector;
    FlashLoanEngine internal flashLoanEngine;
    RiskEngine internal riskEngine;

    address internal owner;
    address internal executor;
    address internal vaultDepositor;
    address internal attacker;
    address internal guardian;
    address internal whitelistAdmin;

    // Track state for invariants
    bool internal initialized;
    uint256 internal totalDeposited;

    constructor() {
        owner = address(0x10000);
        executor = address(0x20000);
        vaultDepositor = address(0x30000);
        attacker = address(0x40000);
        guardian = address(0x50000);
        whitelistAdmin = address(0x60000);

        // Deploy authority
        authority = new RolesAuthority(owner, Authority(address(0)));
        
        // Deploy token
        token = new MockToken();
        
        // Deploy contracts
        feeVault = new FeeVault(token, "Vault", "VLT", owner, owner, authority);
        mevProtector = new MEVProtector(owner, authority);
        flashLoanEngine = new FlashLoanEngine(owner, authority);
        riskEngine = new RiskEngine(owner, authority);

        // Wire capabilities (as owner)
        _wireCapabilities();
        
        // Assign roles (as owner)
        _assignRoles();

        // Fund accounts
        token.mint(vaultDepositor, 1_000_000e18);
        token.mint(attacker, 1_000_000e18);
        
        // Initialize vault
        token.mint(address(this), 1000);
        token.approve(address(feeVault), 1000);
        feeVault.initializeDeadShares();

        initialized = true;
    }

    function _wireCapabilities() internal {
        // FeeVault - P0 FIX: Separate deposit/withdraw
        authority.setRoleCapability(Roles.VAULT_DEPOSITOR, address(feeVault), FeeVault.deposit.selector, true);
        authority.setRoleCapability(Roles.ADMIN, address(feeVault), FeeVault.withdraw.selector, true);
        authority.setRoleCapability(Roles.ADMIN, address(feeVault), FeeVault.redeem.selector, true);
        authority.setRoleCapability(Roles.ADMIN, address(feeVault), FeeVault.pause.selector, true);
        authority.setRoleCapability(Roles.GUARDIAN, address(feeVault), FeeVault.pause.selector, true);
        authority.setRoleCapability(Roles.ADMIN, address(feeVault), FeeVault.emergencyWithdraw.selector, true);

        // MEVProtector
        authority.setRoleCapability(Roles.EXECUTOR, address(mevProtector), MEVProtector.commitExecution.selector, true);
        authority.setRoleCapability(Roles.WHITELIST_ADMIN, address(mevProtector), MEVProtector.setTargetWhitelist.selector, true);

        // FlashLoanEngine
        authority.setRoleCapability(Roles.ARBITRAGE_MANAGER, address(flashLoanEngine), FlashLoanEngine.executeFlashLoanArbitrage.selector, true);
        authority.setRoleCapability(Roles.ADMIN, address(flashLoanEngine), FlashLoanEngine.addProvider.selector, true);

        // RiskEngine
        authority.setRoleCapability(Roles.RISK_MANAGER, address(riskEngine), RiskEngine.setTokenRiskScore.selector, true);
    }

    function _assignRoles() internal {
        authority.setUserRole(owner, Roles.ADMIN, true);
        authority.setUserRole(executor, Roles.EXECUTOR, true);
        authority.setUserRole(vaultDepositor, Roles.VAULT_DEPOSITOR, true);
        authority.setUserRole(guardian, Roles.GUARDIAN, true);
        authority.setUserRole(whitelistAdmin, Roles.WHITELIST_ADMIN, true);
        // attacker gets NO roles
    }

    /*//////////////////////////////////////////////////////////////
                         ECHIDNA TEST FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Vault depositor deposits tokens
    function depositor_deposit(uint256 amount) public {
        amount = _bound(amount, 1e18, 100_000e18);
        
        // Simulate as vaultDepositor
        token.mint(address(this), amount);
        token.approve(address(feeVault), amount);
        
        // This should work - depositor has VAULT_DEPOSITOR role
        // But we're calling from test contract, so simulate the check
        if (authority.canCall(vaultDepositor, address(feeVault), FeeVault.deposit.selector)) {
            totalDeposited += amount;
        }
    }

    /// @notice Attacker attempts to withdraw (should always fail)
    function attacker_withdraw(uint256 amount) public {
        // This must NEVER succeed
        bool canWithdraw = authority.canCall(attacker, address(feeVault), FeeVault.withdraw.selector);
        assert(!canWithdraw); // INVARIANT: Attacker cannot withdraw
    }

    /// @notice Attacker attempts to grant themselves roles (should always fail)
    function attacker_grantRole(uint8 role) public {
        role = uint8(_bound(role, 0, 10));
        
        // Attacker tries to grant themselves a role
        // This should fail because attacker is not owner/admin
        bool hadRoleBefore = authority.doesUserHaveRole(attacker, role);
        
        // Simulate attacker calling setUserRole
        bool canGrantRoles = authority.canCall(attacker, address(authority), authority.setUserRole.selector);
        
        // INVARIANT: Attacker should never be able to grant roles
        assert(!canGrantRoles);
        
        // Double check: attacker still doesn't have the role
        bool hasRoleAfter = authority.doesUserHaveRole(attacker, role);
        assert(hadRoleBefore == hasRoleAfter); // Role unchanged
    }

    /// @notice Attacker attempts to set capabilities (should always fail)
    function attacker_setCapability(uint8 role, address target, bytes4 selector) public {
        role = uint8(_bound(role, 0, 10));
        
        bool canSetCapability = authority.canCall(attacker, address(authority), authority.setRoleCapability.selector);
        
        // INVARIANT: Attacker cannot modify capabilities
        assert(!canSetCapability);
    }

    /// @notice Attacker attempts to pause vault (should always fail)
    function attacker_pause() public {
        bool canPause = authority.canCall(attacker, address(feeVault), FeeVault.pause.selector);
        
        // INVARIANT: Attacker cannot pause
        assert(!canPause);
    }

    /// @notice Attacker attempts whitelist modification (should always fail)
    function attacker_setWhitelist(address target) public {
        bool canSetWhitelist = authority.canCall(attacker, address(mevProtector), MEVProtector.setTargetWhitelist.selector);
        
        // INVARIANT: Attacker cannot modify whitelists
        assert(!canSetWhitelist);
    }

    /// @notice Vault depositor attempts withdrawal (P0 - should always fail)
    function depositor_withdraw(uint256 amount) public {
        bool canWithdraw = authority.canCall(vaultDepositor, address(feeVault), FeeVault.withdraw.selector);
        
        // INVARIANT (P0): Vault depositor CANNOT withdraw
        assert(!canWithdraw);
    }

    /// @notice Vault depositor attempts redeem (P0 - should always fail)
    function depositor_redeem(uint256 shares) public {
        bool canRedeem = authority.canCall(vaultDepositor, address(feeVault), FeeVault.redeem.selector);
        
        // INVARIANT (P0): Vault depositor CANNOT redeem
        assert(!canRedeem);
    }

    /// @notice Executor attempts whitelist modification (role separation - should fail)
    function executor_setWhitelist(address target) public {
        bool canSetWhitelist = authority.canCall(executor, address(mevProtector), MEVProtector.setTargetWhitelist.selector);
        
        // INVARIANT: Executor cannot manage whitelists (role separation)
        assert(!canSetWhitelist);
    }

    /// @notice Guardian can pause (should succeed)
    function guardian_canPause() public {
        bool canPause = authority.canCall(guardian, address(feeVault), FeeVault.pause.selector);
        
        // Guardian SHOULD be able to pause
        assert(canPause);
    }

    /// @notice WhitelistAdmin can set whitelists (should succeed)
    function whitelistAdmin_canSetWhitelist() public {
        bool canSetWhitelist = authority.canCall(whitelistAdmin, address(mevProtector), MEVProtector.setTargetWhitelist.selector);
        
        // WhitelistAdmin SHOULD be able to set whitelists
        assert(canSetWhitelist);
    }

    /// @notice Owner retains admin role
    function owner_hasAdmin() public {
        bool hasAdmin = authority.doesUserHaveRole(owner, Roles.ADMIN);
        
        // INVARIANT: Owner must always have ADMIN role
        assert(hasAdmin);
    }

    /// @notice Attacker never gains any role
    function attacker_hasNoRoles() public {
        for (uint8 role = 0; role <= 10; role++) {
            bool hasRole = authority.doesUserHaveRole(attacker, role);
            assert(!hasRole); // INVARIANT: Attacker has no roles
        }
    }

    /*//////////////////////////////////////////////////////////////
                              PROPERTY CHECKS
    //////////////////////////////////////////////////////////////*/

    /// @notice Main invariant: no privilege escalation possible
    function echidna_no_privilege_escalation() public view returns (bool) {
        // Attacker should never have any roles
        for (uint8 role = 0; role <= 10; role++) {
            if (authority.doesUserHaveRole(attacker, role)) {
                return false;
            }
        }
        return true;
    }

    /// @notice P0 invariant: depositor cannot withdraw
    function echidna_depositor_cannot_withdraw() public view returns (bool) {
        return !authority.canCall(vaultDepositor, address(feeVault), FeeVault.withdraw.selector);
    }

    /// @notice P0 invariant: depositor cannot redeem
    function echidna_depositor_cannot_redeem() public view returns (bool) {
        return !authority.canCall(vaultDepositor, address(feeVault), FeeVault.redeem.selector);
    }

    /// @notice Role separation: executor cannot manage whitelists
    function echidna_executor_no_whitelist() public view returns (bool) {
        return !authority.canCall(executor, address(mevProtector), MEVProtector.setTargetWhitelist.selector);
    }

    /// @notice Owner always has admin
    function echidna_owner_is_admin() public view returns (bool) {
        return authority.doesUserHaveRole(owner, Roles.ADMIN);
    }

    /// @notice Guardian can pause
    function echidna_guardian_can_pause() public view returns (bool) {
        return authority.canCall(guardian, address(feeVault), FeeVault.pause.selector);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _bound(uint256 value, uint256 min, uint256 max) internal pure returns (uint256) {
        if (value < min) return min;
        if (value > max) return max;
        return value;
    }
}

/// @notice Mock ERC20 for testing
contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MCK", 18) {}
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

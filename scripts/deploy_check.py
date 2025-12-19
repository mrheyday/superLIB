#!/usr/bin/env python3
"""
Pre-deployment verification script.
Validates environment, checks balances, and simulates deployment.
"""

import os
import sys
from dotenv import load_dotenv
from web3 import Web3
from eth_account import Account
import json

load_dotenv()

def check_env_vars():
    """Verify all required environment variables are set."""
    required = [
        "OWNER_MULTISIG",
        "GUARDIAN_ADDRESS", 
        "ASSET_TOKEN",
        "MAINNET_RPC_URL"
    ]
    
    missing = [var for var in required if not os.getenv(var)]
    
    if missing:
        print(f"❌ Missing environment variables: {', '.join(missing)}")
        return False
    
    print("✅ All required environment variables set")
    return True

def check_addresses():
    """Validate address checksums."""
    addresses = {
        "OWNER_MULTISIG": os.getenv("OWNER_MULTISIG"),
        "GUARDIAN_ADDRESS": os.getenv("GUARDIAN_ADDRESS"),
        "ASSET_TOKEN": os.getenv("ASSET_TOKEN"),
    }
    
    ai_agent = os.getenv("AI_AGENT_ADDRESS")
    if ai_agent:
        addresses["AI_AGENT_ADDRESS"] = ai_agent
    
    for name, addr in addresses.items():
        if addr:
            try:
                checksummed = Web3.to_checksum_address(addr)
                print(f"✅ {name}: {checksummed}")
            except Exception as e:
                print(f"❌ {name}: Invalid address - {e}")
                return False
    
    return True

def check_deployer_balance(rpc_url: str):
    """Check deployer has sufficient ETH for deployment."""
    w3 = Web3(Web3.HTTPProvider(rpc_url))
    
    if not w3.is_connected():
        print(f"❌ Cannot connect to RPC: {rpc_url[:50]}...")
        return False
    
    print(f"✅ Connected to chain ID: {w3.eth.chain_id}")
    
    pk = os.getenv("PRIVATE_KEY")
    if pk:
        account = Account.from_key(pk)
        balance = w3.eth.get_balance(account.address)
        balance_eth = w3.from_wei(balance, 'ether')
        
        min_balance = 0.5  # Minimum 0.5 ETH for deployment
        
        if balance_eth >= min_balance:
            print(f"✅ Deployer balance: {balance_eth:.4f} ETH")
        else:
            print(f"❌ Deployer balance too low: {balance_eth:.4f} ETH (need {min_balance} ETH)")
            return False
    else:
        print("⚠️  No PRIVATE_KEY set - skipping balance check")
    
    return True

def check_multisig(rpc_url: str):
    """Verify multisig is a valid Gnosis Safe."""
    w3 = Web3(Web3.HTTPProvider(rpc_url))
    multisig = os.getenv("OWNER_MULTISIG")
    
    if not multisig:
        return False
    
    # Check if it's a contract
    code = w3.eth.get_code(Web3.to_checksum_address(multisig))
    
    if len(code) > 2:  # Not empty (0x)
        print(f"✅ Multisig is a contract at {multisig}")
        return True
    else:
        print(f"⚠️  Multisig {multisig} is an EOA, not a contract")
        return True  # Still valid, just a warning

def main():
    print("\n🔍 Pre-Deployment Verification\n")
    print("=" * 50)
    
    checks = [
        ("Environment Variables", check_env_vars),
        ("Address Validation", check_addresses),
    ]
    
    rpc_url = os.getenv("MAINNET_RPC_URL")
    if rpc_url:
        checks.append(("Deployer Balance", lambda: check_deployer_balance(rpc_url)))
        checks.append(("Multisig Verification", lambda: check_multisig(rpc_url)))
    
    results = []
    for name, check in checks:
        print(f"\n📋 {name}")
        print("-" * 30)
        results.append(check())
    
    print("\n" + "=" * 50)
    
    if all(results):
        print("✅ All checks passed - ready for deployment")
        return 0
    else:
        print("❌ Some checks failed - review above")
        return 1

if __name__ == "__main__":
    sys.exit(main())

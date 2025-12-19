#!/usr/bin/env python3
"""
Protocol monitoring script.
Watches for events, tracks metrics, and alerts on anomalies.
"""

import os
import sys
import json
import asyncio
from datetime import datetime
from dotenv import load_dotenv
from web3 import Web3
from rich.console import Console
from rich.table import Table
from rich.live import Live

load_dotenv()
console = Console()

# Event signatures
EVENTS = {
    "UserRoleUpdated": "0x" + Web3.keccak(text="UserRoleUpdated(address,uint8,bool)").hex()[:8],
    "RoleCapabilityUpdated": "0x" + Web3.keccak(text="RoleCapabilityUpdated(uint8,address,bytes4,bool)").hex()[:8],
    "Paused": "0x" + Web3.keccak(text="Paused(address)").hex()[:8],
    "EmergencyWithdraw": "0x" + Web3.keccak(text="EmergencyWithdraw(address,uint256)").hex()[:8],
}

ROLES = {
    0: "ADMIN",
    1: "EXECUTOR", 
    2: "ARBITRAGE_MANAGER",
    3: "RISK_MANAGER",
    4: "CROSSCHAIN_OPERATOR",
    5: "STRATEGY_MANAGER",
    6: "UPDATER",
    7: "VAULT_DEPOSITOR",
    8: "GUARDIAN",
    9: "FEE_UPDATER",
    10: "WHITELIST_ADMIN",
}

class ProtocolMonitor:
    def __init__(self, rpc_url: str, addresses: dict):
        self.w3 = Web3(Web3.HTTPProvider(rpc_url))
        self.addresses = addresses
        self.events = []
        
    async def watch_events(self, from_block: int = None):
        """Watch for protocol events."""
        if from_block is None:
            from_block = self.w3.eth.block_number - 1000
        
        console.print(f"[cyan]Monitoring from block {from_block}...[/cyan]")
        
        while True:
            current_block = self.w3.eth.block_number
            
            for contract_name, address in self.addresses.items():
                if not address:
                    continue
                    
                logs = self.w3.eth.get_logs({
                    "fromBlock": from_block,
                    "toBlock": current_block,
                    "address": Web3.to_checksum_address(address),
                })
                
                for log in logs:
                    self._process_log(contract_name, log)
            
            from_block = current_block + 1
            await asyncio.sleep(12)  # ~1 block
    
    def _process_log(self, contract: str, log):
        """Process and display event log."""
        topic = log["topics"][0].hex() if log["topics"] else None
        
        event_name = "Unknown"
        for name, sig in EVENTS.items():
            if topic and topic.startswith(sig):
                event_name = name
                break
        
        event = {
            "time": datetime.now().isoformat(),
            "block": log["blockNumber"],
            "contract": contract,
            "event": event_name,
            "tx": log["transactionHash"].hex(),
        }
        
        self.events.append(event)
        
        # Alert on critical events
        if event_name in ["Paused", "EmergencyWithdraw", "UserRoleUpdated"]:
            console.print(f"[red]🚨 ALERT: {event_name} on {contract}[/red]")
            console.print(f"   TX: {event['tx']}")
    
    def get_stats_table(self) -> Table:
        """Generate stats table."""
        table = Table(title="Protocol Monitor")
        
        table.add_column("Metric", style="cyan")
        table.add_column("Value", style="green")
        
        table.add_row("Connected", "✅" if self.w3.is_connected() else "❌")
        table.add_row("Chain ID", str(self.w3.eth.chain_id))
        table.add_row("Block", str(self.w3.eth.block_number))
        table.add_row("Events Captured", str(len(self.events)))
        
        return table

async def main():
    rpc_url = os.getenv("MAINNET_RPC_URL")
    
    if not rpc_url:
        console.print("[red]Error: MAINNET_RPC_URL not set[/red]")
        return 1
    
    # Load deployed addresses
    addresses = {
        "authority": os.getenv("AUTHORITY_ADDRESS"),
        "feeVault": os.getenv("FEE_VAULT_ADDRESS"),
        "flashLoanEngine": os.getenv("FLASH_LOAN_ENGINE_ADDRESS"),
    }
    
    monitor = ProtocolMonitor(rpc_url, addresses)
    
    console.print("[green]Starting Protocol Monitor...[/green]")
    
    try:
        await monitor.watch_events()
    except KeyboardInterrupt:
        console.print("\n[yellow]Monitor stopped[/yellow]")
        return 0

if __name__ == "__main__":
    asyncio.run(main())

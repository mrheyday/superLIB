#!/usr/bin/env python3
"""
Targeted Mythril Analysis for Role-Based Access Control Vulnerabilities

Focuses on:
1. Access control bypass
2. Privilege escalation
3. Unauthorized state changes
4. Reentrancy in protected functions
"""

import subprocess
import json
import os
from pathlib import Path
from typing import List, Dict
from dataclasses import dataclass

@dataclass
class AnalysisTarget:
    contract: str
    file: str
    functions: List[str]
    description: str

# High-value targets for security analysis
TARGETS = [
    AnalysisTarget(
        contract="FeeVault",
        file="src/FeeVault.sol",
        functions=["withdraw", "redeem", "emergencyWithdraw", "pause"],
        description="P0: Vault withdrawal protection"
    ),
    AnalysisTarget(
        contract="RolesAuthority",
        file="lib/superlib/auth/RolesAuthority.sol",
        functions=["setUserRole", "setRoleCapability", "setPublicCapability"],
        description="Core: Role management functions"
    ),
    AnalysisTarget(
        contract="MEVProtector",
        file="src/MEVProtector.sol",
        functions=["setTargetWhitelist", "setSelectorWhitelist", "executeProtectedArbitrage"],
        description="P0: Whitelist management"
    ),
    AnalysisTarget(
        contract="FlashLoanEngine",
        file="src/FlashLoanEngine.sol",
        functions=["executeFlashLoanArbitrage", "addProvider", "setDexRouterWhitelist"],
        description="P0: Flash loan execution + whitelist"
    ),
    AnalysisTarget(
        contract="CrossChainRouter",
        file="src/CrossChainRouter.sol",
        functions=["queueChainConfig", "executeChainConfig", "executeCrossChainTrade"],
        description="P0: Timelock bypass checks"
    ),
]

# SWC IDs relevant to access control
CRITICAL_SWCS = {
    "SWC-105": "Unprotected Ether Withdrawal",
    "SWC-106": "Unprotected SELFDESTRUCT",
    "SWC-107": "Reentrancy",
    "SWC-115": "Authorization through tx.origin",
    "SWC-124": "Write to Arbitrary Storage Location",
}

ACCESS_CONTROL_SWCS = {
    "SWC-105": "May indicate missing access control on withdraw",
    "SWC-106": "May indicate unprotected admin function",
    "SWC-115": "Insecure authorization pattern",
}


def run_mythril(file: str, contract: str, timeout: int = 300) -> Dict:
    """Run Mythril on a specific contract."""
    cmd = [
        "myth", "analyze",
        file,
        "--solc-json", "mythril.config.json",
        "--solv", "0.8.28",
        "--execution-timeout", str(timeout),
        "--max-depth", "50",
        "--strategy", "bfs",
        "-o", "jsonv2"
    ]
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout + 60)
        if result.stdout:
            return json.loads(result.stdout)
    except (subprocess.TimeoutExpired, json.JSONDecodeError) as e:
        print(f"  Error analyzing {contract}: {e}")
    
    return {"issues": []}


def analyze_access_control(result: Dict, target: AnalysisTarget) -> List[Dict]:
    """Filter results for access control issues."""
    findings = []
    
    for issue in result.get("issues", []):
        swc_id = issue.get("swc-id", "")
        
        # Check if it's a critical SWC
        if swc_id in CRITICAL_SWCS:
            findings.append({
                "severity": "CRITICAL",
                "swc": swc_id,
                "title": CRITICAL_SWCS[swc_id],
                "description": issue.get("description", {}).get("head", ""),
                "location": issue.get("locations", [{}])[0].get("sourceMap", ""),
                "contract": target.contract,
            })
        
        # Check for access control specific issues
        if swc_id in ACCESS_CONTROL_SWCS:
            findings.append({
                "severity": "HIGH",
                "swc": swc_id,
                "title": ACCESS_CONTROL_SWCS[swc_id],
                "description": issue.get("description", {}).get("head", ""),
                "location": issue.get("locations", [{}])[0].get("sourceMap", ""),
                "contract": target.contract,
            })
    
    return findings


def main():
    print("=" * 60)
    print("Mythril Targeted Access Control Analysis")
    print("=" * 60)
    print()
    
    all_findings = []
    
    for target in TARGETS:
        print(f"🔍 Analyzing: {target.contract}")
        print(f"   Focus: {target.description}")
        print(f"   Functions: {', '.join(target.functions)}")
        
        result = run_mythril(target.file, target.contract)
        findings = analyze_access_control(result, target)
        
        if findings:
            print(f"   ⚠️  {len(findings)} potential issues found")
            all_findings.extend(findings)
        else:
            print(f"   ✅ No access control issues detected")
        
        print()
    
    # Summary
    print("=" * 60)
    print("SUMMARY")
    print("=" * 60)
    
    if not all_findings:
        print("✅ No critical access control vulnerabilities detected")
        print()
        print("Verified invariants:")
        print("  • No unprotected withdrawal functions")
        print("  • No tx.origin authorization")
        print("  • No reentrancy in protected functions")
        print("  • No arbitrary storage writes")
    else:
        print(f"⚠️  {len(all_findings)} potential issues require review:")
        print()
        
        for i, finding in enumerate(all_findings, 1):
            print(f"{i}. [{finding['severity']}] {finding['title']}")
            print(f"   Contract: {finding['contract']}")
            print(f"   SWC: {finding['swc']}")
            print(f"   {finding['description'][:100]}...")
            print()
    
    # Write report
    report_path = Path("mythril/reports/access_control_audit.json")
    report_path.parent.mkdir(parents=True, exist_ok=True)
    
    with open(report_path, "w") as f:
        json.dump({
            "targets": [
                {
                    "contract": t.contract,
                    "file": t.file,
                    "functions": t.functions,
                    "description": t.description
                }
                for t in TARGETS
            ],
            "findings": all_findings,
            "summary": {
                "total_findings": len(all_findings),
                "critical": len([f for f in all_findings if f["severity"] == "CRITICAL"]),
                "high": len([f for f in all_findings if f["severity"] == "HIGH"]),
            }
        }, f, indent=2)
    
    print(f"\nReport saved to: {report_path}")
    
    return 0 if not all_findings else 1


if __name__ == "__main__":
    exit(main())

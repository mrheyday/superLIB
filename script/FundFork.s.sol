// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

contract FundFork is Script {
    address constant DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // Anvil default

    function run() external {
        require(block.chainid == 31337, "Fork Only");
        vm.startBroadcast();
        vm.deal(DEPLOYER, 2 ether);
        vm.stopBroadcast();
        // Invariant check
        require(DEPLOYER.balance >= 2 ether, "Funding Failed");
    }
}

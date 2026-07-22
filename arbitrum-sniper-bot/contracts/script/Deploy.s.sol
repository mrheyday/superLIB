// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Script, console} from 'forge-std/Script.sol';
import {SniperSearcher} from '../src/SniperSearcher.sol';

contract Deploy is Script {
  // Uniswap V3 SwapRouter02 on Arbitrum
  address constant SWAP_ROUTER_ARBITRUM = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
  address constant SWAP_ROUTER_ARBITRUM_SEPOLIA = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

  function run() external {
    uint256 deployerKey = vm.envUint('PRIVATE_KEY');
    address swapRouter = block.chainid == 42161 ? SWAP_ROUTER_ARBITRUM : SWAP_ROUTER_ARBITRUM_SEPOLIA;

    vm.startBroadcast(deployerKey);
    SniperSearcher searcher = new SniperSearcher(swapRouter);
    vm.stopBroadcast();

    console.log('SniperSearcher deployed to:', address(searcher));
    console.log('SwapRouter:', swapRouter);
    console.log('ChainId:', block.chainid);
  }
}

#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

anvil --fork-url "${MAINNET_RPC_URL}" --fork-block-number 20000000 &

sleep 5

# Fund deployer
forge script script/FundFork.s.sol:FundFork \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast

kill %1

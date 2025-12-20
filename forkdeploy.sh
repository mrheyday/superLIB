#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Fork mainnet
anvil --fork-url "${MAINNET_RPC_URL}" --fork-block-number 20000000 &

# Wait for anvil
sleep 5

# Deploy on fork
forge script script/DeployWithRoles.s.sol:DeployWithRoles \
  --rpc-url http://127.0.0.1:8545 \
  --private-key "${FORK_PRIVATE_KEY}" \
  --broadcast

# Kill anvil post-sim
kill %1

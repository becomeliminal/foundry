#!/bin/bash
# Test that warmup_storage correctly preserves storage AND proxy functionality
# This verifies the fix for anvil_setCode marking addresses as "local"
# which breaks subsequent fork storage reads.

set -e

# Use DATA_ environment variables set by Please
STATE_FILE="${DATA_STATE}"
ANVIL="${DATA_ANVIL}"
CAST="${DATA_CAST}"

# Use unique port to avoid conflicts
PORT=19876
RPC_URL="http://127.0.0.1:${PORT}"

echo "Starting anvil with state file: ${STATE_FILE}"

# Start anvil with the state
$ANVIL --load-state "$STATE_FILE" --chain-id 8453 --port $PORT &
ANVIL_PID=$!
trap "kill $ANVIL_PID 2>/dev/null || true" EXIT

# Wait for anvil to be ready
echo "Waiting for anvil to start..."
for i in {1..30}; do
    if $CAST chain-id --rpc-url $RPC_URL 2>/dev/null; then
        echo "Anvil ready"
        break
    fi
    sleep 0.5
done

USDC="0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
FAILED=0

echo ""
echo "Testing USDC proxy functionality..."
echo "===================================="

# THE REAL TEST: Can we actually call functions on the USDC proxy?
# This will fail if the proxy admin/implementation slots are broken
echo "Calling balanceOf(0xdead)..."
BALANCE=$($CAST call $USDC "balanceOf(address)(uint256)" 0x000000000000000000000000000000000000dEaD --rpc-url $RPC_URL 2>&1) || {
    echo "FAIL: balanceOf() call failed: $BALANCE"
    FAILED=1
}

if [ $FAILED -eq 0 ]; then
    echo "PASS: balanceOf() returned: $BALANCE"
fi

# Also check name() to verify proxy delegates correctly
echo "Calling name()..."
NAME=$($CAST call $USDC "name()(string)" --rpc-url $RPC_URL 2>&1) || {
    echo "FAIL: name() call failed: $NAME"
    FAILED=1
}

if [ $FAILED -eq 0 ]; then
    echo "PASS: name() returned: $NAME"
fi

echo ""
if [ $FAILED -eq 0 ]; then
    echo "SUCCESS: USDC proxy is functional"
else
    echo "FAILURE: USDC proxy is broken - warmup_storage did not preserve critical slots"
fi

exit $FAILED

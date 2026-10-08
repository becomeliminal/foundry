#!/bin/bash
# Test that warmup_storage correctly preserves storage AND proxy functionality
# This verifies the fix for anvil_setCode marking addresses as "local"
# which breaks subsequent fork storage reads.

set -e

# Use DATA_ environment variables set by Please
STATE_FILE="${DATA_STATE}"
ANVIL="${DATA_ANVIL}"
CAST="${DATA_CAST}"


echo "Starting anvil with state file: ${STATE_FILE}"

# Start anvil with the state
# On a port Anvil picks itself (--port 0), read back from its log: tests run
# side by side without network isolation here, and two sharing a fixed port
# made one fail to bind.
ANVIL_LOG=$(mktemp)
$ANVIL --load-state "$STATE_FILE" --chain-id 8453 --port 0 > "$ANVIL_LOG" 2>&1 &
ANVIL_PID=$!
trap 'kill $ANVIL_PID 2>/dev/null || true; rm -f "$ANVIL_LOG"' EXIT

echo "Waiting for anvil to start..."
PORT=""
for i in {1..60}; do
    PORT=$(sed -n 's/^Listening on 127\.0\.0\.1:\([0-9][0-9]*\)$/\1/p' "$ANVIL_LOG")
    [ -n "$PORT" ] && break
    if ! kill -0 $ANVIL_PID 2>/dev/null; then
        echo "FAIL: Anvil exited before it was listening:"
        cat "$ANVIL_LOG"
        exit 1
    fi
    sleep 0.5
done
if [ -z "$PORT" ]; then
    echo "FAIL: Anvil did not report a port within 30s:"
    cat "$ANVIL_LOG"
    exit 1
fi
RPC_URL="http://127.0.0.1:${PORT}"
echo "Anvil ready on port $PORT"

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

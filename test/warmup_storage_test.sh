#!/bin/bash
# Test that warmup_storage correctly preserves storage slots
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

# Test USDC storage slots
USDC="0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
FAILED=0
ZERO="0x0000000000000000000000000000000000000000000000000000000000000000"

check_slot() {
    local slot=$1
    local desc=$2
    local val=$($CAST storage $USDC $slot --rpc-url $RPC_URL)
    if [ "$val" = "$ZERO" ]; then
        echo "FAIL: Slot $slot ($desc) is zero - warmup_storage did not preserve it"
        FAILED=1
    else
        echo "PASS: Slot $slot ($desc) = ${val:0:30}..."
    fi
}

echo ""
echo "Testing USDC storage slots..."
echo "=============================="

# These slots should have non-zero values from mainnet
check_slot "0x0" "owner"
check_slot "0x4" "name (USD Coin)"
check_slot "0x5" "symbol (USDC)"
check_slot "0x6" "decimals"
check_slot "0xf" "DOMAIN_SEPARATOR (critical for EIP-3009)"

echo ""
if [ $FAILED -eq 0 ]; then
    echo "SUCCESS: All storage slots were preserved correctly"
else
    echo "FAILURE: Some storage slots were not preserved"
fi

exit $FAILED

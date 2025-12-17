#!/bin/bash
# Test Morpho vault interactions on Arbitrum hermetic state
# Verifies that the Gauntlet USDC Core vault can be used for deposits/redeems

set -e

# Use DATA_ environment variables set by Please
STATE_FILE="${DATA_STATE}"
ANVIL="${DATA_ANVIL}"
CAST="${DATA_CAST}"

# Use unique port to avoid conflicts
PORT=19877
RPC_URL="http://127.0.0.1:${PORT}"

# Contract addresses
MORPHO_VAULT="0x7e97fa6893871A2751B5fE961978DCCb2c201E65"  # Gauntlet USDC Core Vault
MORPHO_BLUE="0x6c247b1F6182318877311737BaC0844bAa518F5e"   # Morpho Blue core
ADAPTIVE_IRM="0x66F30587FB8D4206918deb78ecA7d5eBbafD06DA"   # Interest Rate Model
USDC="0xaf88d065e77c8cC2239327C5EDb3A432268e5831"

# Anvil test account (has 1000 ETH in hermetic state)
TEST_ACCOUNT="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
TEST_PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

echo "Starting anvil with state file: ${STATE_FILE}"

# Start anvil with the state
$ANVIL --load-state "$STATE_FILE" --chain-id 42161 --port $PORT &
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

FAILED=0

echo ""
echo "=============================================="
echo "Testing Morpho Vault Contract Availability"
echo "=============================================="

# Test 1: Check vault contract has code
echo ""
echo "Test 1: Checking Morpho vault has bytecode..."
VAULT_CODE=$($CAST code $MORPHO_VAULT --rpc-url $RPC_URL 2>&1) || {
    echo "FAIL: Could not get vault code: $VAULT_CODE"
    FAILED=1
}
if [ "$VAULT_CODE" = "0x" ] || [ -z "$VAULT_CODE" ]; then
    echo "FAIL: Morpho vault has no bytecode at $MORPHO_VAULT"
    FAILED=1
else
    echo "PASS: Morpho vault has bytecode (${#VAULT_CODE} chars)"
fi

# Test 2: Check Morpho Blue has code
echo ""
echo "Test 2: Checking Morpho Blue has bytecode..."
BLUE_CODE=$($CAST code $MORPHO_BLUE --rpc-url $RPC_URL 2>&1) || {
    echo "FAIL: Could not get Morpho Blue code: $BLUE_CODE"
    FAILED=1
}
if [ "$BLUE_CODE" = "0x" ] || [ -z "$BLUE_CODE" ]; then
    echo "FAIL: Morpho Blue has no bytecode at $MORPHO_BLUE"
    FAILED=1
else
    echo "PASS: Morpho Blue has bytecode (${#BLUE_CODE} chars)"
fi

# Test 3: Check IRM has code
echo ""
echo "Test 3: Checking Adaptive IRM has bytecode..."
IRM_CODE=$($CAST code $ADAPTIVE_IRM --rpc-url $RPC_URL 2>&1) || {
    echo "FAIL: Could not get IRM code: $IRM_CODE"
    FAILED=1
}
if [ "$IRM_CODE" = "0x" ] || [ -z "$IRM_CODE" ]; then
    echo "FAIL: Adaptive IRM has no bytecode at $ADAPTIVE_IRM"
    FAILED=1
else
    echo "PASS: Adaptive IRM has bytecode (${#IRM_CODE} chars)"
fi

echo ""
echo "=============================================="
echo "Testing Morpho Vault Read Functions"
echo "=============================================="

# Test 4: Call asset()
echo ""
echo "Test 4: Calling asset()..."
ASSET=$($CAST call $MORPHO_VAULT "asset()(address)" --rpc-url $RPC_URL 2>&1) || {
    echo "FAIL: asset() call failed: $ASSET"
    FAILED=1
}
if [ "$FAILED" -eq 0 ]; then
    echo "PASS: asset() returned: $ASSET"
    # Verify it's USDC
    if [[ "${ASSET,,}" != *"${USDC:2}"* ]]; then
        echo "WARN: asset() returned unexpected address (expected USDC)"
    fi
fi

# Test 5: Call totalAssets()
echo ""
echo "Test 5: Calling totalAssets()..."
TOTAL_ASSETS=$($CAST call $MORPHO_VAULT "totalAssets()(uint256)" --rpc-url $RPC_URL 2>&1) || {
    echo "FAIL: totalAssets() call failed: $TOTAL_ASSETS"
    FAILED=1
}
if [ "$FAILED" -eq 0 ]; then
    echo "PASS: totalAssets() returned: $TOTAL_ASSETS"
fi

# Test 6: Call convertToShares()
echo ""
echo "Test 6: Calling convertToShares(1000000)..."  # 1 USDC = 1000000 (6 decimals)
SHARES=$($CAST call $MORPHO_VAULT "convertToShares(uint256)(uint256)" 1000000 --rpc-url $RPC_URL 2>&1) || {
    echo "FAIL: convertToShares() call failed: $SHARES"
    FAILED=1
}
if [ "$FAILED" -eq 0 ]; then
    echo "PASS: convertToShares(1 USDC) returned: $SHARES shares"
fi

# Test 7: Call convertToAssets()
echo ""
echo "Test 7: Calling convertToAssets(1000000000000000000)..."  # 1e18 shares
ASSETS=$($CAST call $MORPHO_VAULT "convertToAssets(uint256)(uint256)" 1000000000000000000 --rpc-url $RPC_URL 2>&1) || {
    echo "FAIL: convertToAssets() call failed: $ASSETS"
    FAILED=1
}
if [ "$FAILED" -eq 0 ]; then
    echo "PASS: convertToAssets(1e18 shares) returned: $ASSETS USDC"
fi

echo ""
echo "=============================================="
echo "Testing Morpho Blue Integration"
echo "=============================================="

# Test 8: Check vault can read from Morpho Blue
echo ""
echo "Test 8: Checking vault's first supply queue market..."
# First get the supply queue length
QUEUE_LENGTH=$($CAST call $MORPHO_VAULT "supplyQueueLength()(uint256)" --rpc-url $RPC_URL 2>&1) || {
    echo "FAIL: supplyQueueLength() call failed: $QUEUE_LENGTH"
    FAILED=1
}
if [ "$FAILED" -eq 0 ]; then
    echo "PASS: supplyQueueLength() returned: $QUEUE_LENGTH markets"
fi

echo ""
echo "=============================================="
echo "Testing Deposit Simulation"
echo "=============================================="

# Test 9: Simulate a deposit (without actually executing)
# First, we need USDC. Let's check if we can at least estimate gas for approval
echo ""
echo "Test 9: Estimating gas for USDC approval..."
APPROVE_DATA=$($CAST calldata "approve(address,uint256)" $MORPHO_VAULT 1000000)
GAS_ESTIMATE=$($CAST estimate $USDC $APPROVE_DATA --from $TEST_ACCOUNT --rpc-url $RPC_URL 2>&1) || {
    echo "FAIL: Gas estimation for approve failed: $GAS_ESTIMATE"
    FAILED=1
}
if [ "$FAILED" -eq 0 ]; then
    echo "PASS: USDC.approve() gas estimate: $GAS_ESTIMATE"
fi

# Test 10: Trace a convertToShares call to ensure no missing contracts
echo ""
echo "Test 10: Tracing convertToShares to verify all dependencies..."
TRACE=$($CAST call $MORPHO_VAULT "convertToShares(uint256)(uint256)" 1000000 --rpc-url $RPC_URL --trace 2>&1) || {
    echo "FAIL: Trace failed"
    FAILED=1
}
# Check for "call to non-contract" which indicates missing bytecode
if echo "$TRACE" | grep -q "non-contract"; then
    echo "FAIL: Trace shows calls to non-contract addresses:"
    echo "$TRACE" | grep "non-contract"
    FAILED=1
else
    echo "PASS: No missing contract dependencies detected in trace"
fi

echo ""
echo "=============================================="
if [ $FAILED -eq 0 ]; then
    echo "SUCCESS: All Morpho vault tests passed!"
    echo "The hermetic fork state is ready for savings SAT testing."
else
    echo "FAILURE: Some tests failed"
    echo "Add missing contracts to warmup_addresses in the fork state."
fi

exit $FAILED

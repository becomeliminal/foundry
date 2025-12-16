#!/bin/bash
# Test that EIP-3009 transferWithAuthorization works on the hermetic state
# This verifies USDC proxy, implementation, DOMAIN_SEPARATOR, and signature verification all work

set -e

STATE_FILE="${DATA_STATE}"
ANVIL="${DATA_ANVIL}"
CAST="${DATA_CAST}"

PORT=19877
RPC_URL="http://127.0.0.1:${PORT}"
USDC="0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"

# Anvil account #0 - used as the "from" address for authorization
SIGNER_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
SIGNER_ADDR="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"

# Random recipient address
RECIPIENT="0x1234567890123456789012345678901234567890"

echo "Starting anvil with state file: ${STATE_FILE}"

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

echo ""
echo "=== Testing USDC EIP-3009 transferWithAuthorization ==="
echo ""

# Step 1: Fund the signer with USDC
echo "1. Funding signer with USDC..."
# USDC balances mapping is at slot 9
# Storage slot = keccak256(abi.encode(address, 9))
BALANCE_SLOT=$($CAST keccak $(echo -n "0x000000000000000000000000${SIGNER_ADDR:2}0000000000000000000000000000000000000000000000000000000000000009" | tr -d '\n'))
AMOUNT="0x0000000000000000000000000000000000000000000000000000000000989680"  # 10 USDC (10000000)

echo "   Setting balance slot $BALANCE_SLOT to $AMOUNT"
$CAST rpc anvil_setStorageAt $USDC $BALANCE_SLOT $AMOUNT --rpc-url $RPC_URL > /dev/null

# Verify balance
BALANCE=$($CAST call $USDC "balanceOf(address)(uint256)" $SIGNER_ADDR --rpc-url $RPC_URL)
echo "   Signer balance: $BALANCE"

# Step 2: Check DOMAIN_SEPARATOR
echo ""
echo "2. Checking DOMAIN_SEPARATOR..."
DOMAIN_SEP=$($CAST call $USDC "DOMAIN_SEPARATOR()(bytes32)" --rpc-url $RPC_URL 2>&1) || {
    echo "   DOMAIN_SEPARATOR() call failed: $DOMAIN_SEP"
    echo "   Trying slot 0xf directly..."
    DOMAIN_SEP=$($CAST storage $USDC 0xf --rpc-url $RPC_URL)
}
echo "   DOMAIN_SEPARATOR: $DOMAIN_SEP"
EXPECTED_DOMAIN_SEP="0x02fa7265e7c5d81118673727957699e4d68f74cd74b7db77da710fe8a2c7834f"
if [ "$DOMAIN_SEP" = "$EXPECTED_DOMAIN_SEP" ]; then
    echo "   PASS: DOMAIN_SEPARATOR matches expected"
else
    echo "   FAIL: DOMAIN_SEPARATOR mismatch"
    echo "   Expected: $EXPECTED_DOMAIN_SEP"
    echo "   Got: $DOMAIN_SEP"
    exit 1
fi

# Step 3: Check if USDC is paused
echo ""
echo "3. Checking paused state..."
PAUSED=$($CAST call $USDC "paused()(bool)" --rpc-url $RPC_URL 2>&1) || true
echo "   Paused: $PAUSED"

# Step 4: Try a simple ERC20 transfer first (to verify USDC works)
echo ""
echo "4. Testing simple ERC20 transfer..."
TX=$($CAST send $USDC "transfer(address,uint256)(bool)" $RECIPIENT 1000000 \
    --private-key $SIGNER_KEY --rpc-url $RPC_URL 2>&1) || {
    echo "   FAIL: ERC20 transfer failed: $TX"
    exit 1
}
echo "   PASS: ERC20 transfer succeeded"

# Check recipient balance
RECIPIENT_BALANCE=$($CAST call $USDC "balanceOf(address)(uint256)" $RECIPIENT --rpc-url $RPC_URL)
echo "   Recipient balance: $RECIPIENT_BALANCE"

echo ""
echo "5. Testing EIP-3009 transferWithAuthorization..."
# This is the critical test - verifying the full EIP-3009 flow works
# Use Python for more reliable EIP-712 digest computation

# Generate a fresh recipient and nonce
RECIPIENT2="0x2222222222222222222222222222222222222222"
AMOUNT="1000000"  # 1 USDC
VALID_AFTER="0"
VALID_BEFORE="2000000000"  # Far future timestamp

# Use a fixed nonce for reproducibility
NONCE="0x0000000000000000000000000000000000000000000000000000000000000001"

echo "   From: $SIGNER_ADDR"
echo "   To: $RECIPIENT2"
echo "   Amount: $AMOUNT"
echo "   ValidBefore: $VALID_BEFORE"
echo "   Nonce: $NONCE"

# Compute EIP-712 struct hash using cast abi-encode for proper encoding
# TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)
TYPE_HASH="0x7c7c6cdb67a18743f49ec6fa9b35f50d52ed05cbed4cc592e13b44501c1a2267"

# Use cast to do proper ABI encoding
STRUCT_ENCODED=$($CAST abi-encode "f(bytes32,address,address,uint256,uint256,uint256,bytes32)" \
    "$TYPE_HASH" "$SIGNER_ADDR" "$RECIPIENT2" "$AMOUNT" "$VALID_AFTER" "$VALID_BEFORE" "$NONCE")
STRUCT_HASH=$($CAST keccak "$STRUCT_ENCODED")
echo "   Struct hash: $STRUCT_HASH"

# Compute EIP-712 digest: keccak256("\x19\x01" || domainSeparator || structHash)
DIGEST=$($CAST keccak "$(echo -n "0x1901${DOMAIN_SEP:2}${STRUCT_HASH:2}")")
echo "   EIP-712 digest: $DIGEST"

# Sign the digest using --no-hash to sign raw hash
SIG=$($CAST wallet sign --no-hash --private-key $SIGNER_KEY "$DIGEST" 2>&1)
echo "   Signature: ${SIG:0:42}..."

# Parse signature into r, s, v
R="0x${SIG:2:64}"
S="0x${SIG:66:64}"
V_HEX="${SIG:130:2}"
V_DEC=$((16#$V_HEX))
echo "   v=$V_DEC, r=${R:0:20}..., s=${S:0:20}..."

# Call transferWithAuthorization
echo ""
echo "   Calling transferWithAuthorization..."
TX_RESULT=$($CAST send $USDC \
    "transferWithAuthorization(address,address,uint256,uint256,uint256,bytes32,uint8,bytes32,bytes32)" \
    "$SIGNER_ADDR" "$RECIPIENT2" "$AMOUNT" "$VALID_AFTER" "$VALID_BEFORE" "$NONCE" "$V_DEC" "$R" "$S" \
    --private-key $SIGNER_KEY --rpc-url $RPC_URL 2>&1) || {
    echo "   FAIL: transferWithAuthorization failed"
    echo "   Error: $TX_RESULT"
    exit 1
}
echo "   PASS: transferWithAuthorization succeeded"

# Verify recipient received funds
RECIPIENT2_BALANCE=$($CAST call $USDC "balanceOf(address)(uint256)" $RECIPIENT2 --rpc-url $RPC_URL)
echo "   Recipient2 balance: $RECIPIENT2_BALANCE"

# Extract just the number (cast may return "1000000 [1e6]" format)
RECIPIENT2_BALANCE_NUM=$(echo "$RECIPIENT2_BALANCE" | awk '{print $1}')
if [ "$RECIPIENT2_BALANCE_NUM" = "1000000" ]; then
    echo "   PASS: Balance correct"
else
    echo "   FAIL: Expected 1000000, got $RECIPIENT2_BALANCE_NUM"
    exit 1
fi

echo ""
echo "=== Summary ==="
echo "USDC proxy: Working"
echo "DOMAIN_SEPARATOR: Correct"
echo "ERC20 transfer: Working"
echo "EIP-3009 transferWithAuthorization: Working"
echo ""
echo "SUCCESS: USDC hermetic state is fully functional"

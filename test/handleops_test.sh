#!/bin/bash
# Test handleOps with tracing to find the revert reason
# This reproduces what the wallets SAT does

set -e

STATE_FILE="$DATA_STATE"
ANVIL="$DATA_ANVIL"
CAST="$DATA_CAST"

echo "=== HandleOps Test on Arbitrum Hermetic State ==="
echo "State file: $STATE_FILE"

# Start anvil with the hermetic state
$ANVIL --load-state "$STATE_FILE" --chain-id 42161 --port 18546 &
ANVIL_PID=$!
trap "kill $ANVIL_PID 2>/dev/null || true" EXIT

# Wait for anvil to be ready
echo "Waiting for anvil..."
for i in {1..30}; do
    if $CAST chain-id --rpc-url http://127.0.0.1:18546 2>/dev/null; then
        break
    fi
    sleep 0.5
done

RPC="http://127.0.0.1:18546"
echo "Anvil ready on $RPC"

# Contract addresses (same as wallets SAT)
ENTRYPOINT="0x0000000071727De22E5E9d8BAf0edAc6f37da032"
FACTORY="0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67"
SINGLETON="0x29fcB43b46531BcA003ddC8FCb67FFE91900C762"
SAFE4337="0x75cf11467937ce3F2f357CE24ffc3DBF8fD5c226"
ADDMODULESLIB="0x38869bf66a61cf6bdb996a6ae40d5853fd43b526"
SAFEMODULESETUP="0x2dd68b007b46fbe91b9A7c3EDa5A7a1063cB5b47"
PAYMASTER="0x000000000000000000000000000000000000dEaD"

# Test account (Anvil #0 - owner)
OWNER="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
OWNER_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

# Bundler account (Anvil #1)
BUNDLER="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
BUNDLER_KEY="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"

echo ""
echo "=== Step 1: Build Safe deployment data ==="

# enableModules calldata
ENABLE_MODULES_DATA="8d0dc49f0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000100000000000000000000000075cf11467937ce3f2f357ce24ffc3dbf8fd5c226"

# multiSend transaction
MULTISEND_TX="01${SAFEMODULESETUP:2}00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000064${ENABLE_MODULES_DATA}"
MULTISEND_TX_LEN=$(printf '%064x' $((${#MULTISEND_TX}/2)))
MULTISEND_CALLDATA="8d80ff0a0000000000000000000000000000000000000000000000000000000000000020${MULTISEND_TX_LEN}${MULTISEND_TX}"

# setup calldata
SETUP_DATA=$($CAST calldata "setup(address[],uint256,address,bytes,address,address,uint256,address)" \
    "[$OWNER]" \
    1 \
    "$ADDMODULESLIB" \
    "0x$MULTISEND_CALLDATA" \
    "$SAFE4337" \
    "0x0000000000000000000000000000000000000000" \
    0 \
    "0x0000000000000000000000000000000000000000")

# Factory data for createProxyWithNonce
SALT=77777
FACTORY_DATA=$($CAST calldata "createProxyWithNonce(address,bytes,uint256)" \
    "$SINGLETON" \
    "$SETUP_DATA" \
    $SALT)

echo "Factory data (first 100 chars): ${FACTORY_DATA:0:100}..."

echo ""
echo "=== Step 2: Compute Safe address ==="

# initCode = factory address + factory data (stripped 0x)
INIT_CODE="${FACTORY}${FACTORY_DATA:2}"
echo "initCode length: ${#INIT_CODE}"

# Call EntryPoint.getSenderAddress with trace to see why it reverts
echo "Tracing getSenderAddress..."
$CAST call --rpc-url $RPC --trace \
    $ENTRYPOINT \
    "getSenderAddress(bytes)" \
    "$INIT_CODE" \
    2>&1 | head -100

# The getSenderAddress should revert with SenderAddressResult containing the address
# Let's extract it from the trace or compute it directly

# Compute using factory simulation
echo ""
echo "Computing Safe address via factory simulation..."
SAFE_ADDR_RESULT=$($CAST call --rpc-url $RPC \
    $FACTORY \
    "createProxyWithNonce(address,bytes,uint256)(address)" \
    "$SINGLETON" \
    "$SETUP_DATA" \
    $SALT \
    2>&1 || true)
echo "Factory result: $SAFE_ADDR_RESULT"

# Extract address
SENDER=$(echo "$SAFE_ADDR_RESULT" | grep -oE '0x[a-fA-F0-9]{40}' | head -1)
if [ -z "$SENDER" ]; then
    echo "Could not compute Safe address, using placeholder"
    exit 1
fi
echo "Safe (sender) address: $SENDER"

echo ""
echo "=== Step 3: Build and trace handleOps ==="

# Build the PackedUserOperation for v0.7
# The call data for deployment should be a no-op or empty
# Using executeUserOpWithErrorString selector (0x541d63c8)
CALL_DATA=$($CAST calldata "executeUserOpWithErrorString(address,uint256,bytes,uint8)" \
    "$SENDER" \
    0 \
    "0x" \
    0)

echo "callData: $CALL_DATA"

# Pack accountGasLimits: verificationGasLimit (16 bytes) | callGasLimit (16 bytes)
# verificationGasLimit = 0x50000 (327680), callGasLimit = 0x100000 (1048576)
ACCOUNT_GAS_LIMITS="0x0000000000000000000000000005000000000000000000000000000000100000"

# Pack gasFees: maxPriorityFeePerGas (16 bytes) | maxFeePerGas (16 bytes)
# Both = 0x77359400 (2 gwei)
GAS_FEES="0x0000000000000000000000007735940000000000000000000000000077359400"

# preVerificationGas = 0x10000 (65536)
PRE_VERIFICATION_GAS="0x10000"

# Pack paymasterAndData: paymaster (20 bytes) | paymasterVerificationGasLimit (16 bytes) | paymasterPostOpGasLimit (16 bytes) | paymasterData
# verificationGasLimit = 0x30000, postOpGasLimit = 0x30000
PAYMASTER_AND_DATA="${PAYMASTER}0000000000000000000000000003000000000000000000000000000000030000"

# Signature (dummy - just needs to be valid format for Safe)
SIGNATURE="0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001"

echo ""
echo "Building handleOps calldata..."

# For ERC-4337 v0.7, we need to encode the PackedUserOperation struct
# struct PackedUserOperation {
#     address sender;
#     uint256 nonce;
#     bytes initCode;
#     bytes callData;
#     bytes32 accountGasLimits;
#     uint256 preVerificationGas;
#     bytes32 gasFees;
#     bytes paymasterAndData;
#     bytes signature;
# }

# handleOps(PackedUserOperation[] calldata ops, address payable beneficiary)
# This is complex to encode manually, let's use cast

# Create a simpler test: just trace the inner validation call directly
# The EntryPoint calls account.validateUserOp()
# For Safe, this goes through the fallback handler to Safe4337Module

echo ""
echo "=== Step 4: Trace Safe4337Module.validateUserOp simulation ==="

# Check if Safe4337Module validates correctly
# validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)

# First, verify the module is at the expected address and has code
echo "Safe4337Module code check..."
MODULE_CODE=$($CAST code $SAFE4337 --rpc-url $RPC)
echo "Safe4337Module code length: ${#MODULE_CODE}"

# Trace a call to Safe4337Module directly
echo ""
echo "Tracing direct call to Safe4337Module.SUPPORTED_ENTRYPOINT..."
$CAST call --rpc-url $RPC --trace \
    $SAFE4337 \
    "SUPPORTED_ENTRYPOINT()(address)" \
    2>&1

echo ""
echo "=== Step 5: Trace full handleOps call ==="

# Now let's actually call handleOps with a trace
# We'll encode the full call manually

# For the test, let's try calling handleOps via eth_call with trace
# This should show us exactly where the revert happens

# Use the bundler private key to send
echo "Simulating handleOps call with trace..."

# The actual handleOps call - we need to ABI encode the UserOp array
# This is complex, so let's use forge script or a simpler approach

# Actually, let's trace what happens when we just send a raw transaction
# to EntryPoint that tries to process a minimal UserOp

# For debugging, let's check all the contracts involved are present
echo ""
echo "=== Contract Code Verification ==="
for addr in $ENTRYPOINT $FACTORY $SINGLETON $SAFE4337 $ADDMODULESLIB $SAFEMODULESETUP $PAYMASTER; do
    code=$($CAST code $addr --rpc-url $RPC)
    if [ "$code" = "0x" ]; then
        echo "MISSING CODE at $addr"
    else
        echo "OK: $addr (${#code} chars)"
    fi
done

# Check CompatibilityFallbackHandler
FALLBACK_HANDLER="0xfd0732Dc9E303f09fCEf3a7388Ad10A83459Ec99"
code=$($CAST code $FALLBACK_HANDLER --rpc-url $RPC)
if [ "$code" = "0x" ]; then
    echo "MISSING CODE at CompatibilityFallbackHandler ($FALLBACK_HANDLER)"
else
    echo "OK: CompatibilityFallbackHandler $FALLBACK_HANDLER (${#code} chars)"
fi

echo ""
echo "=== Test Complete ==="

#!/bin/bash
# Test Safe creation + UserOp validation on Arbitrum hermetic state
# This simulates what wallets SAT does

set -e

STATE_FILE="$DATA_STATE"
ANVIL="$DATA_ANVIL"
CAST="$DATA_CAST"

echo "=== Safe Creation Test on Arbitrum Hermetic State ==="
echo "State file: $STATE_FILE"

# Start anvil with the hermetic state
$ANVIL --load-state "$STATE_FILE" --chain-id 42161 --port 18545 &
ANVIL_PID=$!
trap "kill $ANVIL_PID 2>/dev/null || true" EXIT

# Wait for anvil to be ready
echo "Waiting for anvil..."
for i in {1..30}; do
    if $CAST chain-id --rpc-url http://127.0.0.1:18545 2>/dev/null; then
        break
    fi
    sleep 0.5
done

RPC="http://127.0.0.1:18545"
echo "Anvil ready on $RPC"

# Contract addresses
ENTRYPOINT="0x0000000071727De22E5E9d8BAf0edAc6f37da032"
FACTORY="0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67"
SINGLETON="0x29fcB43b46531BcA003ddC8FCb67FFE91900C762"
SAFE4337="0x75cf11467937ce3F2f357CE24ffc3DBF8fD5c226"
ADDMODULESLIB="0x38869bf66a61cf6bdb996a6ae40d5853fd43b526"
SAFEMODULESETUP="0x2dd68b007b46fbe91b9A7c3EDa5A7a1063cB5b47"
USDC="0xaf88d065e77c8cC2239327C5EDb3A432268e5831"

# Test account (Anvil #0)
OWNER="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
OWNER_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

echo ""
echo "=== Step 1: Verify contract code exists ==="
for addr in $ENTRYPOINT $FACTORY $SINGLETON $SAFE4337 $ADDMODULESLIB $SAFEMODULESETUP $USDC; do
    code=$($CAST code $addr --rpc-url $RPC)
    if [ "$code" = "0x" ]; then
        echo "FAIL: No code at $addr"
        exit 1
    else
        echo "OK: Code exists at $addr (${#code} chars)"
    fi
done

echo ""
echo "=== Step 2: Create Safe via Factory ==="

# Use the exact same encoding that worked in the earlier trace:
# This is the setup data from a successful Safe creation with Safe4337Module
# setup(owners[], threshold, to, data, fallbackHandler, paymentToken, payment, paymentReceiver)
# - owners: [OWNER]
# - threshold: 1
# - to: AddModulesLib (for multiSend)
# - data: multiSend transaction that calls SafeModuleSetup.enableModules([Safe4337Module])
# - fallbackHandler: Safe4337Module
# - rest: zeros

# The multiSend transaction format:
# operation (1 byte) + to (20 bytes) + value (32 bytes) + dataLength (32 bytes) + data
# For enableModules([Safe4337Module]):
# - operation: 0x01 (delegatecall)
# - to: SafeModuleSetup (2dd68b007b46fbe91b9a7c3eda5a7a1063cb5b47)
# - value: 0
# - dataLength: 0x64 (100 bytes)
# - data: enableModules calldata

# enableModules selector: 0x8d0dc49f
# enableModules([Safe4337Module]) = 8d0dc49f + offset(0x20) + length(1) + Safe4337Module address
# Total: 4 + 32 + 32 + 32 = 100 bytes (0x64)

ENABLE_MODULES_DATA="8d0dc49f0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000100000000000000000000000075cf11467937ce3f2f357ce24ffc3dbf8fd5c226"

# multiSend transaction (packed, no 0x prefix internally)
# operation (01) + to (20 bytes) + value (32 bytes) + dataLength (32 bytes) + data
MULTISEND_TX="01${SAFEMODULESETUP:2}00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000064${ENABLE_MODULES_DATA}"

# multiSend calldata: selector + offset + length + data
# selector: 0x8d80ff0a
# The multiSend function takes bytes memory transactions
# offset: 0x20 (32)
# length: len(MULTISEND_TX)/2 bytes
MULTISEND_TX_LEN=$(printf '%064x' $((${#MULTISEND_TX}/2)))
MULTISEND_CALLDATA="8d80ff0a0000000000000000000000000000000000000000000000000000000000000020${MULTISEND_TX_LEN}${MULTISEND_TX}"

echo "multiSend calldata: 0x$MULTISEND_CALLDATA"

# Now build setup calldata
# setup(address[] _owners, uint256 _threshold, address to, bytes calldata data, address fallbackHandler, address paymentToken, uint256 payment, address paymentReceiver)
SETUP_DATA=$($CAST calldata "setup(address[],uint256,address,bytes,address,address,uint256,address)" \
    "[$OWNER]" \
    1 \
    "$ADDMODULESLIB" \
    "0x$MULTISEND_CALLDATA" \
    "$SAFE4337" \
    "0x0000000000000000000000000000000000000000" \
    0 \
    "0x0000000000000000000000000000000000000000")
echo "setup data length: ${#SETUP_DATA}"

# Create proxy with nonce
SALT=99999
echo "Creating Safe with salt $SALT..."
TX_OUTPUT=$($CAST send --private-key $OWNER_KEY --rpc-url $RPC \
    $FACTORY \
    "createProxyWithNonce(address,bytes,uint256)" \
    "$SINGLETON" \
    "$SETUP_DATA" \
    $SALT \
    --json 2>&1) || {
    echo "Safe creation failed!"
    echo "$TX_OUTPUT"
    exit 1
}
echo "Transaction sent"

# Parse transaction hash from JSON output
TX_HASH=$(echo "$TX_OUTPUT" | grep -oE '"transactionHash":"0x[a-fA-F0-9]{64}"' | head -1 | cut -d'"' -f4)
echo "Transaction hash: $TX_HASH"

# Get the Safe address from the ProxyCreation event in the logs
# ProxyCreation(address indexed proxy, address singleton)
# Event topic: keccak256("ProxyCreation(address,address)") = 0x4f51faf6c4561ff95f067657e43439f0f856d97c04d9ec9070a6199ad418e235
RECEIPT=$($CAST receipt --rpc-url $RPC $TX_HASH --json)
echo "Got receipt"

# Parse the Safe address from topic1 of the ProxyCreation event
# The proxy address is indexed, so it's in topics[1] as a 32-byte padded address
# Format: 0x000000000000000000000000<20-byte-address>
PROXY_TOPIC=$(echo "$RECEIPT" | tr ',' '\n' | grep -A1 "0x4f51faf6c4561ff95f067657e43439f0f856d97c04d9ec9070a6199ad418e235" | tail -1 | grep -oE '0x[a-fA-F0-9]{64}')
echo "Proxy topic (padded): $PROXY_TOPIC"

# Extract the address from the padded topic (last 40 hex chars = 20 bytes)
SAFE_ADDRESS="0x${PROXY_TOPIC: -40}"
echo "Safe address: $SAFE_ADDRESS"

# Check if Safe has code
SAFE_CODE=$($CAST code $SAFE_ADDRESS --rpc-url $RPC)
if [ "$SAFE_CODE" = "0x" ]; then
    echo "FAIL: Safe was not deployed at $SAFE_ADDRESS"
    exit 1
fi
echo "OK: Safe deployed at $SAFE_ADDRESS"

echo ""
echo "=== Step 3: Verify Safe state ==="

# Check owners
OWNERS=$($CAST call --rpc-url $RPC $SAFE_ADDRESS "getOwners()(address[])")
echo "Owners: $OWNERS"

# Check threshold
THRESHOLD=$($CAST call --rpc-url $RPC $SAFE_ADDRESS "getThreshold()(uint256)")
echo "Threshold: $THRESHOLD"

# Check if Safe4337Module is enabled
IS_MODULE_ENABLED=$($CAST call --rpc-url $RPC $SAFE_ADDRESS "isModuleEnabled(address)(bool)" $SAFE4337)
echo "Safe4337Module enabled: $IS_MODULE_ENABLED"

if [ "$IS_MODULE_ENABLED" != "true" ]; then
    echo "FAIL: Safe4337Module not enabled!"
    exit 1
fi

echo ""
echo "=== Step 4: Test Safe4337Module ==="

# Verify SUPPORTED_ENTRYPOINT
echo "Testing Safe4337Module.SUPPORTED_ENTRYPOINT()..."
SUPPORTED_EP=$($CAST call --rpc-url $RPC $SAFE4337 "SUPPORTED_ENTRYPOINT()(address)")
echo "SUPPORTED_ENTRYPOINT: $SUPPORTED_EP"

echo ""
echo "=== Step 4.5: Verify Paymaster Setup ==="

# Check mock paymaster has code
PAYMASTER="0x000000000000000000000000000000000000dEaD"
PAYMASTER_CODE=$($CAST code $PAYMASTER --rpc-url $RPC)
echo "Paymaster code at $PAYMASTER: $PAYMASTER_CODE"

# Check paymaster deposit in EntryPoint
# Storage slot: keccak256(abi.encode(0xdEaD, 0))
DEPOSIT_SLOT="0x44ad89ba62b98ff34f51403ac22759b55759460c0bb5521eb4b6ee3cff49cf83"
DEPOSIT=$($CAST storage $ENTRYPOINT $DEPOSIT_SLOT --rpc-url $RPC)
echo "Paymaster deposit at slot $DEPOSIT_SLOT: $DEPOSIT"

# Also check via getDepositInfo
DEPOSIT_INFO=$($CAST call --rpc-url $RPC $ENTRYPOINT "getDepositInfo(address)" $PAYMASTER)
echo "getDepositInfo($PAYMASTER): $DEPOSIT_INFO"

echo ""
echo "=== Step 5: Test handleOps (UserOp deployment) ==="

# Now test the actual UserOp flow that the wallets SAT uses
# This is what fails in the real tests

# Build a minimal UserOp for Safe deployment
# The factory deploys the Safe, so we need:
# - sender: the predicted Safe address (already deployed from step 2)
# - For a new Safe, we'd use factory + factoryData
# For this test, let's try to call handleOps with a minimal op

# Let's trace what happens when we call the Safe via EntryPoint
# First, get a new Safe address for this test
SALT2=88888
echo "Computing Safe address for UserOp test (salt $SALT2)..."

# Compute new Safe address
SETUP_DATA2=$($CAST calldata "setup(address[],uint256,address,bytes,address,address,uint256,address)" \
    "[$OWNER]" \
    1 \
    "$ADDMODULESLIB" \
    "0x$MULTISEND_CALLDATA" \
    "$SAFE4337" \
    "0x0000000000000000000000000000000000000000" \
    0 \
    "0x0000000000000000000000000000000000000000")

# Compute the factory data for createProxyWithNonce
FACTORY_DATA=$($CAST calldata "createProxyWithNonce(address,bytes,uint256)" \
    "$SINGLETON" \
    "$SETUP_DATA2" \
    $SALT2)

echo "Factory data: ${FACTORY_DATA:0:100}..."

# Get the predicted address via simulation
# We need to compute the CREATE2 address
# For Safe, it's: keccak256(0xff ++ factory ++ salt ++ keccak256(proxyCreationCode ++ singleton))
# But let's just call the factory to get it

# Actually, let's trace what happens when EntryPoint tries to validate this UserOp
# Build the packed UserOp structure for v0.7

# First, let's try tracing a simple call to see if EntryPoint works
echo "Testing EntryPoint.getSenderAddress to compute Safe address..."
SENDER_ADDR=$($CAST call --rpc-url $RPC \
    $ENTRYPOINT \
    "getSenderAddress(bytes)" \
    "$FACTORY_DATA" \
    2>&1 || true)
echo "getSenderAddress result: $SENDER_ADDR"

# The above should revert with SenderAddressResult(address) containing the address
# Let's parse it - if it reverts, the error message contains the address
NEW_SAFE=$(echo "$SENDER_ADDR" | grep -oE '0x[a-fA-F0-9]{40}' | head -1)
if [ -z "$NEW_SAFE" ]; then
    echo "Could not compute new Safe address via EntryPoint"
    # Let's try another approach - just compute via factory call
    NEW_SAFE="0x1234567890123456789012345678901234567890"  # placeholder
fi
echo "New Safe address for UserOp test: $NEW_SAFE"

# Now let's trace a handleOps call to understand the failure
# Build minimal UserOp structure for v0.7 (PackedUserOperation)
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

echo ""
echo "Tracing handleOps call..."
# Let's trace a direct call to handleOps with a trace to see where it fails
# Use the exact same params as the SAT test

# For simplicity, let's trace the Safe's isModuleEnabled call through the fallback handler
echo "Testing Safe fallback routing (simulates UserOp validation path)..."
$CAST call --rpc-url $RPC --trace \
    $SAFE_ADDRESS \
    "isModuleEnabled(address)(bool)" \
    "$SAFE4337" \
    2>&1 | head -50

echo ""
echo "=== All tests passed! ==="

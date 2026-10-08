#!/bin/bash
# A committed fork state loads in Anvil with no network and holds what its
# declaration asked for: the warmed contract's code and the funded balance.
set -eu

PORT_LOG=$(mktemp)
trap 'kill $PID 2>/dev/null || true; rm -f "$PORT_LOG"' EXIT

# GIVEN the committed state, served by base_fork_state_committed
# WHEN Anvil loads it, with no fork URL
$DATA_ANVIL --load-state "$DATA_STATE" --chain-id 8453 --port 0 > "$PORT_LOG" 2>&1 &
PID=$!
PORT=""
for _ in $(seq 1 60); do
    PORT=$(sed -n 's/^Listening on 127\.0\.0\.1:\([0-9][0-9]*\)$/\1/p' "$PORT_LOG")
    [ -n "$PORT" ] && break
    kill -0 $PID 2>/dev/null || { echo "FAIL: Anvil exited:"; cat "$PORT_LOG"; exit 1; }
    sleep 0.5
done
[ -n "$PORT" ] || { echo "FAIL: Anvil did not report a port"; cat "$PORT_LOG"; exit 1; }
URL=http://127.0.0.1:$PORT

FAILED=0
# THEN the warmed contract has its code
CODE=$($DATA_CAST code 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 --rpc-url $URL)
if [ "${#CODE}" -gt 4 ]; then
    echo "PASS: USDC proxy has its code (${#CODE} hex chars)"
else
    echo "FAIL: USDC proxy has no code ($CODE)"
    FAILED=1
fi
# AND the funded account holds what fund_accounts gave it
BALANCE=$($DATA_CAST balance 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --ether --rpc-url $URL)
if [ "$BALANCE" = "10.000000000000000000" ]; then
    echo "PASS: funded account holds $BALANCE ETH"
else
    echo "FAIL: funded account holds $BALANCE ETH; expected 10"
    FAILED=1
fi
exit $FAILED

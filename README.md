# Foundry Please Plugin

A [Please](https://please.build) plugin that provides hermetic [Foundry](https://github.com/foundry-rs/foundry) binaries (anvil, forge, cast, chisel) and hermetic blockchain state generation for deterministic testing against real mainnet contracts.

## Installation

Add to your `plugins/BUILD`:

```python
plugin_repo(
    name = "foundry",
    owner = "becomeliminal",
    revision = "<commit-sha>",
)
```

Add to your `.plzconfig`:

```ini
[Plugin "foundry"]
Target = //plugins:foundry
```

## Usage

In your `third_party/binary/BUILD` (or wherever you want the binaries):

```python
subinclude("///foundry//build_defs:foundry")

foundry(
    name = "foundry",
    version = "1.5.0",
    visibility = ["PUBLIC"],
)
```

Access individual binaries:

- `//third_party/binary:foundry|anvil` - Local Ethereum node for testing
- `//third_party/binary:foundry|forge` - Smart contract testing framework
- `//third_party/binary:foundry|cast` - Ethereum RPC client
- `//third_party/binary:foundry|chisel` - Solidity REPL

## Supported Platforms

- `linux_amd64`
- `linux_arm64`
- `darwin_amd64`
- `darwin_arm64`

## Hermetic Fork States

The `anvil_fork_state()` rule generates offline blockchain state files from live networks. Network is required at build time, but tests run fully offline with deterministic results.

### What It Does Under the Hood

This is equivalent to manually running:

```bash
# 1. Start a fork
anvil --fork-url https://arb1.arbitrum.io/rpc --fork-block-number 280000000 --chain-id 42161

# 2. For each warmup_storage address, read slots BEFORE setCode (critical!)
SLOT_VALUE=$(cast storage 0xUSDC 0x0 --rpc-url http://localhost:8545)

# 3. For each warmup_addresses, fetch and set code
CODE=$(cast code 0xUSDC --rpc-url https://arb1.arbitrum.io/rpc)
cast rpc anvil_setCode 0xUSDC $CODE --rpc-url http://localhost:8545

# 4. Restore the storage we read earlier (setCode broke it)
cast rpc anvil_setStorageAt 0xUSDC 0x0 $SLOT_VALUE --rpc-url http://localhost:8545

# 5. Set any custom storage, deploy custom code, fund accounts...

# 6. Mine a block (required for offline loading)
cast rpc evm_mine --rpc-url http://localhost:8545

# 7. Dump state to file
cast rpc anvil_dumpState --rpc-url http://localhost:8545 | jq -r '.' | xxd -r -p | gunzip > state.json
```

The plugin automates all of this and produces a `.json` state file that can be included as a data dependency in any test. I primarily use this to include real mainnet contract state in Go tests without needing network access at test time.

```python
anvil_fork_state(
    name = "arbitrum_state",
    fork_url = "https://arb1.arbitrum.io/rpc",
    chain_id = 42161,
    block_number = 280000000,
    warmup_addresses = [
        "0x0000000071727De22E5E9d8BAf0edAc6f37da032",  # EntryPoint v0.7
        "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",  # USDC
    ],
    fund_accounts = {
        "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266": "100 ether",
    },
)
```

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | str | Rule name. Output will be `{name}.json` |
| `fork_url` | str | RPC URL to fork from |
| `chain_id` | int | Chain ID (42161=Arbitrum, 8453=Base, 1=Ethereum) |
| `block_number` | int | Block to fork at. **Pin this for determinism!** |
| `warmup_addresses` | list | Contract addresses to include in state |
| `warmup_storage` | dict | Storage slots to preserve: `{address: [slot, ...]}` |
| `set_storage` | dict | Custom storage values: `{address: {slot: value}}` |
| `deploy_code` | dict | Deploy custom bytecode: `{address: "0x..."}` |
| `fund_accounts` | dict | Fund accounts: `{address: "100 ether"}` |
| `foundry_tool` | str | Path to foundry rule (default: `//third_party/binary:foundry`) |
| `visibility` | list | Visibility declaration |

### Common Fork URLs

- Arbitrum: `https://arb1.arbitrum.io/rpc`
- Base: `https://mainnet.base.org`
- Ethereum: `https://eth.llamarpc.com`

## Using State Files in Tests

```python
gentest(
    name = "my_test",
    test_cmd = "bash $DATA_TEST_SCRIPT",
    data = {
        "STATE": [":my_fork_state"],
        "ANVIL": [":foundry|anvil"],
        "CAST": [":foundry|cast"],
        "TEST_SCRIPT": ["my_test.sh"],
    },
)
```

```bash
#!/bin/bash
set -e

$DATA_ANVIL --load-state "$DATA_STATE" --chain-id 42161 --port 8545 &
ANVIL_PID=$!
trap "kill $ANVIL_PID 2>/dev/null || true" EXIT

# Wait for anvil, then test
for i in {1..30}; do
    $DATA_CAST chain-id --rpc-url http://127.0.0.1:8545 2>/dev/null && break
    sleep 0.5
done

$DATA_CAST call 0x... "balanceOf(address)(uint256)" 0x... --rpc-url http://127.0.0.1:8545
```

## Gotchas & Debugging

### The setCode/Storage Problem

When Anvil's `setCode` is called on an address, it marks that address as "local", which causes subsequent storage reads from the fork to return empty values. This breaks proxy contracts.

**This is why `warmup_storage` exists.** The plugin reads storage BEFORE calling setCode, then restores it after. For any contract in `warmup_addresses` that uses storage (especially proxies), you must specify which slots to preserve.

### Proxy Contracts (ZeppelinOS/OpenZeppelin)

Proxy contracts store admin and implementation addresses in special storage slots. These MUST be in `warmup_storage` or the proxy will be broken:

```python
warmup_storage = {
    "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913": [  # USDC proxy
        "0x0", "0x1", "0x2", "0x3", "0x4", "0x5", "0x6", "0x7",
        "0x8", "0x9", "0xa", "0xb", "0xc", "0xd", "0xe", "0xf",
        # ZeppelinOS proxy admin slot
        "0x10d6a54a4754c8869d6886b5f5d7fbfa5b4522237ea5c60d11bc4e7a1ff9390b",
        # ZeppelinOS proxy implementation slot
        "0x7050c9e0f4ca769c69bd3a8ef740bc37934f8e2c036e5a723fd8ee048ed3f8c3",
    ],
}
```

### EIP-3009/EIP-712 Signature Verification

For contracts using EIP-712 signatures (like USDC's `transferWithAuthorization`), the `DOMAIN_SEPARATOR` must be preserved. For Circle's USDC, this is at slot `0xf`.

### Debugging "Call to non-contract" Errors

When a call reverts with empty data, use `cast call --trace` to see internal calls. If you see `call to non-contract address 0x...`, that address needs to be added to `warmup_addresses`.

Common culprits: proxy implementation contracts, signature verification libraries, external contracts called by your target.

## Storage Slot Reference

### Finding Slots

```bash
# Read slot 0 of USDC
cast storage 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 0x0 --rpc-url https://mainnet.base.org
```

### Computing Mapping Slots

For mappings like `balances[address]`, use keccak256:

```bash
# Balance slot for address in mapping at slot 9: keccak256(abi.encode(address, 9))
cast keccak "0x000000000000000000000000<address>0000000000000000000000000000000000000000000000000000000000000009"
```

### Setting Custom Storage

```python
set_storage = {
    # Set EntryPoint deposit for mock paymaster (100 ETH)
    "0x0000000071727De22E5E9d8BAf0edAc6f37da032": {
        "0x44ad89ba62b98ff34f51403ac22759b55759460c0bb5521eb4b6ee3cff49cf83": "0x0000000000000000000000000000000000000000000000056bc75e2d63100000",
    },
}
```

## Complete Example

```python
subinclude("///foundry//build_defs:foundry")

foundry(name = "foundry", version = "1.5.0", visibility = ["PUBLIC"])

anvil_fork_state(
    name = "base_fork_state",
    fork_url = "https://mainnet.base.org",
    chain_id = 8453,
    block_number = 23000000,
    warmup_addresses = [
        "0x0000000071727De22E5E9d8BAf0edAc6f37da032",  # EntryPoint v0.7
        "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",  # USDC proxy
        "0x2Ce6311ddAE708829bc0784C967b7d77D19FD779",  # USDC implementation
        "0x2D943E25e1859ED786AFe4AFB2B42e14EFAC691e",  # USDC SignatureChecker
    ],
    warmup_storage = {
        "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913": [
            "0x0", "0x1", "0x2", "0x3", "0x4", "0x5", "0x6", "0x7",
            "0x8", "0x9", "0xa", "0xb", "0xc", "0xd", "0xe", "0xf",
            "0x10d6a54a4754c8869d6886b5f5d7fbfa5b4522237ea5c60d11bc4e7a1ff9390b",
            "0x7050c9e0f4ca769c69bd3a8ef740bc37934f8e2c036e5a723fd8ee048ed3f8c3",
        ],
    },
    fund_accounts = {
        "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266": "1000 ether",
    },
    foundry_tool = ":foundry",
    visibility = ["PUBLIC"],
)

gentest(
    name = "usdc_test",
    test_cmd = "bash $DATA_TEST_SCRIPT",
    data = {
        "STATE": [":base_fork_state"],
        "ANVIL": [":foundry|anvil"],
        "CAST": [":foundry|cast"],
        "TEST_SCRIPT": ["usdc_test.sh"],
    },
)
```

## Future Work: Dynamic Storage Slot Discovery

Currently, `warmup_storage` requires manually specifying every storage slot you need. This is tedious and error-prone - you have to know the contract's storage layout, find all the relevant slots, and hope you didn't miss any.

I'd love to make this more dynamic. Some ideas:

**Option 1: Trace-based discovery.** Run a "warmup transaction" that exercises the code paths you care about, trace all `SLOAD` operations, and automatically capture those slots. Something like:

```python
warmup_storage_from_calls = {
    "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913": [
        "balanceOf(address)(uint256) 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
        "DOMAIN_SEPARATOR()(bytes32)",
    ],
}
```

The plugin would trace each call, find every storage slot touched, and preserve them.

**Option 2: Storage layout from verified source.** For verified contracts on Etherscan/Sourcify, we could fetch the storage layout JSON and automatically include all slots for a given variable name:

```python
warmup_storage_vars = {
    "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913": ["_balances", "_domainSeparator", "_implementation"],
}
```

**Option 3: Full storage dump for small contracts.** Just dump all non-zero storage slots. This could be expensive for contracts with lots of storage, but for most contracts it would "just work."

The tricky bit is doing this efficiently at build time without blowing up build times or state file sizes. PRs welcome if anyone has clever ideas.

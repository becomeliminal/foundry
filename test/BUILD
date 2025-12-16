subinclude("//build_defs:foundry")

foundry(
    name = "foundry",
    version = "1.5.0",
    visibility = ["PUBLIC"],
)

# =============================================================================
# ARBITRUM FORK STATE
# =============================================================================
# Hermetic Arbitrum mainnet state for ERC-4337 and token testing.
#
# Usage:
#   plz build //test:arbitrum_fork_state
#   anvil --load-state plz-out/gen/test/arbitrum_fork_state.json --chain-id 42161
#
# Contracts included:
#   - EntryPoint v0.7: ERC-4337 account abstraction
#   - USDC: Circle's USD stablecoin
# =============================================================================
anvil_fork_state(
    name = "arbitrum_fork_state",
    fork_url = "https://arb1.arbitrum.io/rpc",
    chain_id = 42161,
    block_number = 411260000,  # Pin to stable block for reproducibility
    warmup_addresses = [
        "0x0000000071727De22E5E9d8BAf0edAc6f37da032",  # EntryPoint v0.7
        "0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67",  # Safe Proxy Factory
        "0x29fcB43b46531BcA003ddC8FCb67FFE91900C762",  # Safe Singleton
        "0x75cf11467937ce3F2f357CE24ffc3DBF8fD5c226",  # Safe4337Module
        "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",  # USDC
        "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9",  # USDT
    ],
    fund_accounts = {
        "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266": "1000 ether",
    },
    foundry_tool = ":foundry",
    visibility = ["PUBLIC"],
)

# =============================================================================
# BASE FORK STATE
# =============================================================================
# Hermetic Base mainnet state for stablecoin and DeFi testing.
#
# Usage:
#   plz build //test:base_fork_state
#   anvil --load-state plz-out/gen/test/base_fork_state.json --chain-id 8453
#
# Contracts included:
#   - USDC: Native USDC on Base
#   - WETH: Wrapped ETH
# =============================================================================
anvil_fork_state(
    name = "base_fork_state",
    fork_url = "https://mainnet.base.org",
    chain_id = 8453,
    block_number = 23000000,  # Pin to stable block for reproducibility
    warmup_addresses = [
        "0x0000000071727De22E5E9d8BAf0edAc6f37da032",  # EntryPoint v0.7
        "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",  # USDC proxy on Base
        "0x2Ce6311ddAE708829bc0784C967b7d77D19FD779",  # USDC implementation (FiatTokenV2_2)
        "0x4200000000000000000000000000000000000006",  # WETH on Base
    ],
    # Test warmup_storage - preserve USDC storage slots when using setCode
    # Includes slot 0xf (DOMAIN_SEPARATOR) which is critical for EIP-3009
    warmup_storage = {
        "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913": [
            "0x0", "0x1", "0x2", "0x3", "0x4", "0x5", "0x6", "0x7",
            "0x8", "0x9", "0xa", "0xb", "0xc", "0xd", "0xe", "0xf",
            # ZeppelinOS proxy slots (keccak hash, NOT hash-1)
            "0x10d6a54a4754c8869d6886b5f5d7fbfa5b4522237ea5c60d11bc4e7a1ff9390b",  # Admin
            "0x7050c9e0f4ca769c69bd3a8ef740bc37934f8e2c036e5a723fd8ee048ed3f8c3",  # Implementation
        ],
    },
    deploy_code = {
        # Mock paymaster at 0xdEaD
        "0x000000000000000000000000000000000000dEaD": "0x60406000526000602052600060405260606000f3",
    },
    set_storage = {
        # Mock paymaster deposit in EntryPoint (100 ETH)
        "0x0000000071727De22E5E9d8BAf0edAc6f37da032": {
            "0x44ad89ba62b98ff34f51403ac22759b55759460c0bb5521eb4b6ee3cff49cf83": "0x0000000000000000000000000000000000000000000000056bc75e2d63100000",
        },
    },
    fund_accounts = {
        "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266": "1000 ether",
    },
    foundry_tool = ":foundry",
    visibility = ["PUBLIC"],
)

# Test that warmup_storage correctly preserves storage slots
gentest(
    name = "warmup_storage_test",
    test_cmd = "bash $DATA_TEST_SCRIPT",
    data = {
        "STATE": [":base_fork_state"],
        "ANVIL": [":foundry|anvil"],
        "CAST": [":foundry|cast"],
        "TEST_SCRIPT": ["warmup_storage_test.sh"],
    },
    no_test_output = True,
    labels = ["integration"],
)

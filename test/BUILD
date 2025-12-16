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
        "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",  # USDC on Base
        "0x4200000000000000000000000000000000000006",  # WETH on Base
    ],
    fund_accounts = {
        "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266": "1000 ether",
    },
    foundry_tool = ":foundry",
    visibility = ["PUBLIC"],
)

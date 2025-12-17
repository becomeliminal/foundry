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
# N.B. Debugging hermetic state issues:
#   When a call reverts with empty data, use `cast call --trace` to see the
#   internal calls. If you see "call to non-contract address 0x...", that
#   address needs to be added to warmup_addresses.
# =============================================================================
anvil_fork_state(
    name = "arbitrum_fork_state",
    fork_url = "https://arb1.arbitrum.io/rpc",
    chain_id = 42161,
    block_number = 411260000,  # Pin to stable block for reproducibility
    warmup_addresses = [
        # ERC-4337 Infrastructure
        "0x0000000071727De22E5E9d8BAf0edAc6f37da032",  # EntryPoint v0.7
        "0xEFC2c1444eBCC4Db75e7613d20C6a62fF67A167C",  # SenderCreator (used by EntryPoint for account deployment)
        # Safe Smart Account Infrastructure
        "0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67",  # Safe Proxy Factory
        "0x29fcB43b46531BcA003ddC8FCb67FFE91900C762",  # Safe Singleton
        "0x75cf11467937ce3F2f357CE24ffc3DBF8fD5c226",  # Safe4337Module
        "0x38869bf66a61cf6bdb996a6ae40d5853fd43b526",  # AddModulesLib
        "0x2dd68b007b46fbe91b9A7c3EDa5A7a1063cB5b47",  # SafeModuleSetup
        "0xfd0732Dc9E303f09fCEf3a7388Ad10A83459Ec99",  # CompatibilityFallbackHandler
        # USDC (Circle FiatTokenV2 proxy + implementation + dependencies)
        "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",  # USDC proxy
        "0x86E721b43d4ECFa71119Dd38c0f938A75Fdb57B3",  # USDC implementation (FiatTokenV2_2)
        "0x4e7D093EE4d74a01905Cf5CA92eB0bf154a53247",  # USDC SignatureChecker
        # Morpho Protocol (for savings/DeFi testing)
        "0x7e97fa6893871A2751B5fE961978DCCb2c201E65",  # Gauntlet USDC Core Vault (MetaMorpho)
        "0x6c247b1F6182318877311737BaC0844bAa518F5e",  # Morpho Blue core
        "0x66F30587FB8D4206918deb78ecA7d5eBbafD06DA",  # Adaptive Curve IRM (interest rate model)
    ],
    warmup_storage = {
        # USDC proxy storage (ZeppelinOS + FiatTokenV2)
        "0xaf88d065e77c8cC2239327C5EDb3A432268e5831": [
            "0x0", "0x1", "0x2", "0x3", "0x4", "0x5", "0x6", "0x7",
            "0x8", "0x9", "0xa", "0xb", "0xc", "0xd", "0xe", "0xf",
            # ZeppelinOS proxy slots
            "0x10d6a54a4754c8869d6886b5f5d7fbfa5b4522237ea5c60d11bc4e7a1ff9390b",  # Admin
            "0x7050c9e0f4ca769c69bd3a8ef740bc37934f8e2c036e5a723fd8ee048ed3f8c3",  # Implementation
        ],
    },
    deploy_code = {
        # Mock paymaster - minimal IPaymaster that returns valid for all UserOps
        "0x000000000000000000000000000000000000dEaD": "0x60406000526000602052600060405260606000f3",
    },
    set_storage = {
        # EntryPoint: Mock paymaster deposit (100 ETH)
        # deposits mapping at slot 0: keccak256(abi.encode(0xdEaD, 0))
        "0x0000000071727De22E5E9d8BAf0edAc6f37da032": {
            "0x44ad89ba62b98ff34f51403ac22759b55759460c0bb5521eb4b6ee3cff49cf83": "0x0000000000000000000000000000000000000000000000056bc75e2d63100000",
        },
    },
    fund_accounts = {
        # Anvil account #0 (test signer)
        "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266": "1000 ether",
        # Anvil account #1 (bundler signer)
        "0x70997970C51812dc3A010C7d01b50e0d17dc79C8": "1000 ether",
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
#
# N.B. Debugging hermetic state issues:
#   When a call reverts with empty data, use `cast call --trace` to see the
#   internal calls. If you see "call to non-contract address 0x...", that
#   address needs to be added to warmup_addresses.
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
        "0x2D943E25e1859ED786AFe4AFB2B42e14EFAC691e",  # USDC SignatureChecker (required for EIP-3009)
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

# Test EIP-3009 transferWithAuthorization functionality
# This verifies USDC proxy, implementation, DOMAIN_SEPARATOR, and transfers all work
gentest(
    name = "eip3009_test",
    test_cmd = "bash $DATA_TEST_SCRIPT",
    data = {
        "STATE": [":base_fork_state"],
        "ANVIL": [":foundry|anvil"],
        "CAST": [":foundry|cast"],
        "TEST_SCRIPT": ["eip3009_test.sh"],
    },
    no_test_output = True,
    labels = ["integration"],
)

# Test Safe creation on Arbitrum hermetic state
# Simulates what wallets SAT does - creates Safe, enables modules, validates UserOp
gentest(
    name = "safe_creation_test",
    test_cmd = "bash $DATA_TEST_SCRIPT",
    data = {
        "STATE": [":arbitrum_fork_state"],
        "ANVIL": [":foundry|anvil"],
        "CAST": [":foundry|cast"],
        "TEST_SCRIPT": ["safe_creation_test.sh"],
    },
    no_test_output = True,
    labels = ["integration"],
)

# Test handleOps with tracing to debug reverts
gentest(
    name = "handleops_test",
    test_cmd = "bash $DATA_TEST_SCRIPT",
    data = {
        "STATE": [":arbitrum_fork_state"],
        "ANVIL": [":foundry|anvil"],
        "CAST": [":foundry|cast"],
        "TEST_SCRIPT": ["handleops_test.sh"],
    },
    no_test_output = True,
    labels = ["integration"],
)

# Test Morpho vault interactions for savings SAT
gentest(
    name = "morpho_vault_test",
    test_cmd = "bash $DATA_TEST_SCRIPT",
    data = {
        "STATE": [":arbitrum_fork_state"],
        "ANVIL": [":foundry|anvil"],
        "CAST": [":foundry|cast"],
        "TEST_SCRIPT": ["morpho_vault_test.sh"],
    },
    no_test_output = True,
    labels = ["integration"],
)

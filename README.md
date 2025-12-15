# Foundry Please Plugin

A [Please](https://please.build) plugin that provides hermetic [Foundry](https://github.com/foundry-rs/foundry) binaries (anvil, forge, cast, chisel).

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

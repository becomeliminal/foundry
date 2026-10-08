#!/bin/bash
# Each fork state must hold its own chain: the block it was pinned to, plus the
# one the rule mines before dumping.
#
# Both states are data of this one test, so plz builds them at the same time.
# While every anvil_fork_state shared port 18545, that was exactly the case
# that went wrong on a machine without network namespaces: one build's Anvil
# failed to bind, its cast commands reached the other build's Anvil, and it
# dumped the other chain under its own name. The block number is what gives
# that away.
set -eu

FAILED=0
check() {
    local name="$1" state="$2" pinned="$3"
    local got
    # The state is one line of compact JSON; no jq, which a Mac before
    # macOS 15 has only from Homebrew.
    got=$(grep -o '"best_block_number":[0-9]*' "$state" | cut -d: -f2)
    if [ "$got" = "$((pinned + 1))" ]; then
        echo "PASS: $name is at block $got (pinned $pinned)"
    else
        echo "FAIL: $name is at block $got; expected $((pinned + 1)) (pinned $pinned)"
        FAILED=1
    fi
}

check base_fork_state "$DATA_EARLIER_STATE" 23000000
check base_fork_state_later "$DATA_LATER_STATE" 23000100

exit $FAILED

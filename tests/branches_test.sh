#!/bin/bash
# Unit tests for the branch registry (docker/helpers/branches.sh).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "${HELPERS_DIR}/branches.sh"

# expect <input> <steam_beta> <platform> <conf_subdir> <rcon_ok> <needs_pass>
expect() {
    Resolve_Branch "$1" || { fail "'$1' did not resolve"; return; }
    check "'$1' steam beta" "$2" "$BRANCH_STEAM_BETA"
    check "'$1' platform" "$3" "$BRANCH_PLATFORM"
    check "'$1' config dir" "$4" "$BRANCH_CONF_SUBDIR"
    check "'$1' rcon" "$5" "$BRANCH_RCON_OK"
    check "'$1' needs password" "$6" "$BRANCH_NEEDS_PASS"
}

expect evrima        evrima          linux   LinuxServer   1 0
expect " Evrima "    evrima          linux   LinuxServer   1 0
expect spiro         spiro0.11.59.04 linux   LinuxServer   1 0
expect hordetesting  hordetesting    linux   LinuxServer   1 1
expect LEGACY        public          windows WindowsServer 0 0

HORDETEST_BRANCH="hordetest2" Resolve_Branch hordetesting
check "HORDETEST_BRANCH override" "hordetest2" "$BRANCH_STEAM_BETA"

Resolve_Branch legacy
check "legacy binary" "TheIsle/Binaries/Win64/TheIsleServer-Win64-Shipping.exe" "$BRANCH_BINARY"

if Resolve_Branch "survival"; then fail "unknown branch should fail"; else pass "unknown branch rejected"; fi
if Resolve_Branch ""; then fail "empty branch should fail"; else pass "empty branch rejected"; fi

check "Branch_Dir" "${CONTAINER_HOME}/branches/spiro" "$(Branch_Dir spiro)"

# Every supported branch has default configs in the image.
for b in $SUPPORTED_BRANCHES; do
    [[ -f "${DEFAULTS_DIR}/${b}/Game.ini" ]] && pass "defaults/${b}/Game.ini exists" || fail "defaults/${b}/Game.ini missing"
done
finish

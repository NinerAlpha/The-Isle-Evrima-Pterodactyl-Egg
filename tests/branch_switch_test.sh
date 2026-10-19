#!/bin/bash
# Tests for switch detection, pruning and the game update flow with a stub
# SteamCMD (docker/sections/branch_switch.sh + update_game.sh).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Stub SteamCMD: records its argv and "installs" the requested branch's binary
# unless STUB_FAIL=1.
export STEAMCMD_BIN="${WORKROOT}/steamcmd_stub.sh" STEAMCMD_RETRIES=2 STEAMCMD_RETRY_DELAY=0
export STUB_LOG="${WORKROOT}/steamcmd.calls"
cat > "$STEAMCMD_BIN" <<'STUB'
#!/bin/bash
echo "$*" >> "$STUB_LOG"
[[ "${STUB_FAIL:-0}" == "1" ]] && exit 8
dir="" plat=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        +force_install_dir) dir="$2"; shift ;;
        +@sSteamCmdForcePlatformType) plat="$2"; shift ;;
    esac
    shift
done
if [[ "$plat" == "windows" ]]; then
    mkdir -p "$dir/TheIsle/Binaries/Win64" && touch "$dir/TheIsle/Binaries/Win64/TheIsleServer-Win64-Shipping.exe"
else
    mkdir -p "$dir/TheIsle/Binaries/Linux" && touch "$dir/TheIsle/Binaries/Linux/TheIsleServer-Linux-Shipping"
fi
mkdir -p "$dir/steamapps" "$dir/Engine"
STUB
chmod +x "$STEAMCMD_BIN"

source "${SECTIONS_DIR}/branch_switch.sh"
source "${SECTIONS_DIR}/update_game.sh"
active() { cat "${CONTAINER_HOME}/.active-branch" 2>/dev/null; }
last_call() { tail -n1 "$STUB_LOG"; }

# --- fresh install ------------------------------------------------------------
Detect_Branch_Switch evrima
check "fresh server is not a switch" "0" "$BRANCH_SWITCHED"
Update_Game evrima "$BRANCH_SWITCHED" >/dev/null && pass "evrima installs" || fail "evrima install failed"
check "active marker written" "evrima" "$(active)"
[[ "$(last_call)" == *"-beta evrima validate +quit"* && "$(last_call)" == *"ForcePlatformType linux"* ]] \
    && pass "fresh install is validated linux evrima" || fail "fresh install args: $(last_call)"

# --- normal restart: AUTO_UPDATE without validate -------------------------------
AUTO_UPDATE=1 VALIDATE=0 Update_Game evrima 0 >/dev/null
[[ "$(last_call)" != *validate* ]] && pass "plain restart skips validate" || fail "restart validated: $(last_call)"
calls=$(wc -l < "$STUB_LOG")
AUTO_UPDATE=0 Update_Game evrima 0 >/dev/null
check "AUTO_UPDATE=0 skips SteamCMD" "$calls" "$(wc -l < "$STUB_LOG")"

# --- switch to spiro, prune evrima but keep its Saved ---------------------------
mkdir -p "$(Branch_Dir evrima)/TheIsle/Saved/Databases" && echo data > "$(Branch_Dir evrima)/TheIsle/Saved/Databases/players.db"
Detect_Branch_Switch spiro
check "switch detected" "1" "$BRANCH_SWITCHED"
check "previous branch" "evrima" "$PREVIOUS_BRANCH"
Prune_Inactive_Branches spiro >/dev/null
[[ ! -d "$(Branch_Dir evrima)/TheIsle/Binaries" && ! -d "$(Branch_Dir evrima)/steamapps" ]] \
    && pass "inactive branch game files pruned" || fail "evrima not pruned"
check "inactive branch saves kept" "data" "$(cat "$(Branch_Dir evrima)/TheIsle/Saved/Databases/players.db")"
Update_Game spiro 1 >/dev/null
check "switch marker" "spiro" "$(active)"
[[ "$(last_call)" == *"-beta spiro0.11.59.04 validate"* ]] && pass "spiro validated" || fail "spiro args: $(last_call)"

# --- PRUNE_INACTIVE_BRANCHES=0 keeps everything ---------------------------------
Update_Game evrima 1 >/dev/null
PRUNE_INACTIVE_BRANCHES=0 Prune_Inactive_Branches evrima
[[ -f "$(Branch_Dir spiro)/TheIsle/Binaries/Linux/TheIsleServer-Linux-Shipping" ]] \
    && pass "prune disabled keeps inactive installs" || fail "prune ran while disabled"

# --- failed switch: marker not moved, server refuses to start --------------------
echo evrima > "${CONTAINER_HOME}/.active-branch"
if STUB_FAIL=1 Update_Game hordetesting 1 >/dev/null; then fail "failed switch should not start"; else pass "failed switch returns error"; fi
check "marker unchanged after failed switch" "evrima" "$(active)"
check "retries happen" "2" "$(grep -c 'hordetesting' "$STUB_LOG")"

# --- failed routine update with an existing install still starts -----------------
if STUB_FAIL=1 AUTO_UPDATE=1 Update_Game evrima 0 >/dev/null; then pass "update failure falls back to installed build"; else fail "installed build should still start"; fi

# --- hordetesting password + legacy platform -------------------------------------
BETA_PASSWORD='s3cret' Update_Game hordetesting 1 >/dev/null
[[ "$(last_call)" == *"-beta hordetesting -betapassword s3cret validate"* ]] \
    && pass "hordetesting passes beta password" || fail "hordetesting args: $(last_call)"
BETA_PASSWORD='s3cret' Update_Game spiro 0 >/dev/null
[[ "$(last_call)" != *betapassword* ]] && pass "password only used for private branches" || fail "password leaked to spiro"
Update_Game legacy 1 >/dev/null
[[ "$(last_call)" == *"ForcePlatformType windows"* && "$(last_call)" == *"-beta public"* ]] \
    && pass "legacy uses the windows depot" || fail "legacy args: $(last_call)"
check "legacy marker" "legacy" "$(active)"
finish

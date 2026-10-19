#!/bin/bash
# Tests for per-branch config seeding and panel sync (docker/sections/config_sync.sh).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "${SECTIONS_DIR}/config_sync.sh"

# shellcheck disable=SC2034  # read by the sourced section
SERVER_PORT=7777 RESOLVED_QUERY_PORT=7778 RESOLVED_RCON_PORT=7779 RESOLVED_QUEUE_PORT=7780
export SERVER_NAME='Pine & Co | "Test" \ server' MAX_PLAYERS=42 RCON_PASSWORD='p@ss/w|rd&' \
       ENABLE_QUEUE=false HUMANS=true DISCORD='https://discord.gg/abc' \
       SERVER_PASSWORD_ENABLED=false SERVER_PASSWORD='secret' ALLOW_REPLAY=true DYNAMIC_WEATHER=false

val() { grep -m1 "^$2=" "$1" | cut -d= -f2-; }
count() { grep -c "^$2=" "$1"; }

# --- Evrima: seed + sync -----------------------------------------------------
Sync_Branch_Config evrima
GI="$(Branch_Dir evrima)/TheIsle/Saved/Config/LinuxServer/Game.ini"
[[ -f "$GI" ]] && pass "evrima Game.ini seeded" || fail "evrima Game.ini not seeded"
[[ -f "$(Branch_Dir evrima)/TheIsle/Saved/Config/LinuxServer/Engine.ini" ]] && pass "evrima Engine.ini seeded" || fail "Engine.ini not seeded"
check "ServerName with special chars" "$SERVER_NAME" "$(val "$GI" ServerName)"
check "MaxPlayerCount" "42" "$(val "$GI" MaxPlayerCount)"
check "RCON forced on" "true" "$(val "$GI" bRconEnabled)"
check "RconPort" "7779" "$(val "$GI" RconPort)"
check "RconPassword special chars" "$RCON_PASSWORD" "$(val "$GI" RconPassword)"
check "QueuePort" "7780" "$(val "$GI" QueuePort)"
check "QueryPort on game port" "7777" "$(val "$GI" QueryPort)"
check "Discord quoted" '"https://discord.gg/abc"' "$(val "$GI" Discord)"
check "bEnableHumans" "true" "$(val "$GI" bEnableHumans)"
check "AllowedClasses untouched" "18" "$(count "$GI" AllowedClasses)"

# --- user edits survive, managed keys re-synced, missing key inserted ----------
sed -i 's/^GrowthMultiplier=.*/GrowthMultiplier=3/; /^RconPort=/d; s/^bRconEnabled=.*/bRconEnabled=false/' "$GI"
Sync_Branch_Config evrima
check "user edit preserved" "3" "$(val "$GI" GrowthMultiplier)"
check "RCON re-enabled" "true" "$(val "$GI" bRconEnabled)"
check "deleted RconPort re-inserted" "7779" "$(val "$GI" RconPort)"
section_line=$(grep -n '^\[/script/theisle.tigamesession\]' "$GI" | cut -d: -f1)
rcon_line=$(grep -n '^RconPort=' "$GI" | cut -d: -f1)
check "inserted key directly under its section" "$((section_line + 1))" "$rcon_line"

# --- CRLF file + duplicate keys ----------------------------------------------
printf '[/script/theisle.tigamesession]\r\nServerName=a\r\nServerName=b\r\n' > "$GI"
Sync_Branch_Config evrima
check "duplicate key collapsed" "1" "$(count "$GI" ServerName)"

# --- unset panel var is not written -------------------------------------------
unset HUMANS
printf '[/script/theisle.tigamesession]\nbEnableHumans=false\n' > "$GI"
Sync_Branch_Config evrima
check "unset variable leaves key alone" "false" "$(val "$GI" bEnableHumans)"

# --- Legacy schema ------------------------------------------------------------
Sync_Branch_Config legacy
LG="$(Branch_Dir legacy)/TheIsle/Saved/Config/WindowsServer/Game.ini"
check "legacy MaxPlayers" "42" "$(val "$LG" MaxPlayers)"
check "legacy password cleared when disabled" "" "$(val "$LG" ServerPassword)"
check "legacy has no RCON keys" "0" "$(count "$LG" bRconEnabled)"
SERVER_PASSWORD_ENABLED=true Sync_Branch_Config legacy
check "legacy password set when enabled" "secret" "$(val "$LG" ServerPassword)"

printf '[/Script/TheIsle.TheIsleGameSession]\nServerName=x\n' > "$LG"
Sync_Branch_Config legacy >/dev/null
[[ -f "${LG}.old-schema" ]] && grep -q '^\[/Script/TheIsle.IGameSession\]' "$LG" \
    && pass "legacy outdated schema replaced" || fail "legacy outdated schema not replaced"

# --- ServerConfig link --------------------------------------------------------
Link_Active_Config spiro
check "ServerConfig link" "branches/spiro/TheIsle/Saved/Config/LinuxServer" "$(readlink "${CONTAINER_HOME}/ServerConfig")"
Link_Active_Config legacy
check "ServerConfig relinked" "branches/legacy/TheIsle/Saved/Config/WindowsServer" "$(readlink "${CONTAINER_HOME}/ServerConfig")"
finish

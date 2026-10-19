#!/bin/bash

#########################################
# PER-BRANCH CONFIG SEED + PANEL SYNC   #
#########################################
#
# Each branch keeps its own Game.ini / Engine.ini under
# branches/<key>/TheIsle/Saved/Config/<LinuxServer|WindowsServer>/.
# Defaults ship in the image (/defaults/<key>/) and are copied only when a
# file is missing; after that the user's edits are preserved and only the
# panel-managed keys below are rewritten on every boot. (The Wings config
# parser is not used: it cannot follow a per-branch path.)

source "${HELPERS_DIR:-/helpers}/messages.sh"
source "${HELPERS_DIR:-/helpers}/branches.sh"

DEFAULTS_DIR="${DEFAULTS_DIR:-/defaults}"

# Set_Ini_Key <file> <section> <key> <value>
# Replaces the first "key=" line (anywhere in the file, case-sensitive key)
# and drops later duplicates; if the key is missing it is inserted directly
# under [section] (matched case-insensitively), appending the section when
# absent. Values are passed through ENVIRON so no character is interpreted.
Set_Ini_Key() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    local tmp="${file}.tmp.$$"
    INI_SECTION="$2" INI_KEY="$3" INI_VALUE="$4" awk '
        BEGIN {
            sec = tolower(ENVIRON["INI_SECTION"]); key = ENVIRON["INI_KEY"]
            line = key "=" ENVIRON["INI_VALUE"]
        }
        { lines[NR] = $0; l = $0; sub(/\r$/, "", l); sub(/^[ \t]+/, "", l) }
        index(l, key "=") == 1 { if (!found) { found = NR } else { drop[NR] = 1 } }
        tolower(l) == "[" sec "]" && !secline { secline = NR }
        END {
            for (i = 1; i <= NR; i++) {
                if (drop[i]) continue
                if (i == found) { print line; continue }
                print lines[i]
                if (!found && i == secline) print line
            }
            if (!found && !secline) {
                if (NR > 0) print ""
                print "[" ENVIRON["INI_SECTION"] "]"
                print line
            }
        }
    ' "$file" > "$tmp" && cat "$tmp" > "$file"
    rm -f "$tmp"
}

# Seed_Branch_Configs <key> : copy image defaults for missing files.
Seed_Branch_Configs() {
    Resolve_Branch "$1" || return 1
    local conf f
    conf="$(Branch_Dir "$1")/TheIsle/Saved/Config/${BRANCH_CONF_SUBDIR}"
    mkdir -p "$conf"
    for f in Game.ini Engine.ini; do
        if [[ ! -f "${conf}/${f}" && -f "${DEFAULTS_DIR}/$1/${f}" ]]; then
            cp -f "${DEFAULTS_DIR}/$1/${f}" "${conf}/${f}"
            Info "Created default ${f} for $1"
        fi
    done
    BRANCH_CONF_PATH="$conf"
}

# _Sync <file> <section> <key> <env-var-name> [prefix] [suffix]
# Only writes the key when the panel variable is defined.
_Sync() {
    local name="$4"
    [[ -n "${!name+x}" ]] || return 0
    Set_Ini_Key "$1" "$2" "$3" "${5:-}${!name}${6:-}"
}

# Sync_Branch_Config <key>
# Requires RESOLVED_QUERY_PORT / RESOLVED_RCON_PORT / RESOLVED_QUEUE_PORT.
Sync_Branch_Config() {
    local key="$1"
    Seed_Branch_Configs "$key" || return 1
    local gi="${BRANCH_CONF_PATH}/Game.ini"
    [[ -f "$gi" ]] || return 0

    if [[ "$key" == "legacy" ]]; then
        # Older egg builds wrote Legacy settings under a section the game ignores.
        if grep -q '^\[/Script/TheIsle.TheIsleGameSession\]' "$gi"; then
            Warn "Legacy Game.ini uses an outdated section - replacing it (backup: Game.ini.old-schema)"
            mv -f "$gi" "${gi}.old-schema"
            cp -f "${DEFAULTS_DIR}/legacy/Game.ini" "$gi"
        fi
        local s="/Script/TheIsle.IGameSession"
        _Sync "$gi" "$s" ServerName SERVER_NAME
        _Sync "$gi" "/Script/Engine.GameSession" MaxPlayers MAX_PLAYERS
        # Legacy has no password flag: an empty ServerPassword means none.
        if [[ "${SERVER_PASSWORD_ENABLED:-false}" == "true" || "${SERVER_PASSWORD_ENABLED:-}" == "1" ]]; then
            _Sync "$gi" "$s" ServerPassword SERVER_PASSWORD
        else
            Set_Ini_Key "$gi" "$s" ServerPassword ""
        fi
        _Sync "$gi" "$s" ServerDiscord DISCORD
        _Sync "$gi" "$s" bServerAllowReplayRecording ALLOW_REPLAY
        return 0
    fi

    local s="/script/theisle.tigamesession"
    _Sync "$gi" "$s" ServerName SERVER_NAME
    _Sync "$gi" "$s" MaxPlayerCount MAX_PLAYERS
    _Sync "$gi" "$s" bServerPassword SERVER_PASSWORD_ENABLED
    _Sync "$gi" "$s" ServerPassword SERVER_PASSWORD
    _Sync "$gi" "$s" bQueueEnabled ENABLE_QUEUE
    _Sync "$gi" "$s" bEnableHumans HUMANS
    _Sync "$gi" "$s" bAllowRecordingReplay ALLOW_REPLAY
    _Sync "$gi" "$s" bServerDynamicWeather DYNAMIC_WEATHER
    _Sync "$gi" "$s" Discord DISCORD '"' '"'
    # Ports and RCON are always managed: the wrapper needs RCON to bridge the
    # panel console, and ports must match the server's allocations. QueryPort
    # stays on the game port (egg query_offset 0), as with the previous egg.
    Set_Ini_Key "$gi" "$s" QueryPort "${SERVER_PORT}"
    Set_Ini_Key "$gi" "$s" QueuePort "${RESOLVED_QUEUE_PORT}"
    Set_Ini_Key "$gi" "$s" bRconEnabled "true"
    Set_Ini_Key "$gi" "$s" RconPort "${RESOLVED_RCON_PORT}"
    Set_Ini_Key "$gi" "$s" RconPassword "${RCON_PASSWORD:-}"
    return 0
}

# Link_Active_Config <key> : ServerConfig -> active branch's config folder,
# so the file manager always has one stable place to edit Game.ini.
Link_Active_Config() {
    Resolve_Branch "$1" || return 0
    local home="${CONTAINER_HOME:-/home/container}"
    if [[ -e "${home}/ServerConfig" && ! -L "${home}/ServerConfig" ]]; then
        Warn "ServerConfig exists and is not a link - leaving it alone."
        return 0
    fi
    ln -sfn "branches/$1/TheIsle/Saved/Config/${BRANCH_CONF_SUBDIR}" "${home}/ServerConfig"
}

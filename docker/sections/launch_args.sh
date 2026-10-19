#!/bin/bash

################################
# SERVER LAUNCH ARGUMENTS      #
################################
#
# Builds LAUNCH_ARGS (one array element per argv entry; wrapper.js spawns it
# without a shell) and exports what wrapper.js needs to run the branch.

source "${HELPERS_DIR:-/helpers}/branches.sh"

# Public Evrima dedicated-server EOS client (same values the game ships).
EOS_CLIENT_ID="xyza7891gk5PRo3J7G9puCJGFJjmEguW"
EOS_CLIENT_SECRET="pKWl6t5i9NJK8gTpVlAxzENZ65P8hYzodV8Dqe5Rlc8"

# Legacy_Map_Path <LEGACY_MAP value>
Legacy_Map_Path() {
    case "${1:-thenyaw}" in
        isle_v3|isle-v3|v3)        echo "/Game/TheIsle/Maps/Landscape3/Isle_V3" ;;
        isle_v4|isle-v4|v4)        echo "/Game/TheIsle/Maps/Landscape4/Landscape_04" ;;
        region2|region-2)          echo "/Game/Region2/Isle_Region2" ;;
        redwoods|region2_redwoods) echo "/Game/Region2/Isle_Region2_Redwoods" ;;
        dv_testlevel|testlevel)    echo "/Game/TheIsle/Maps/Developer/DV_TestLevel" ;;
        *)                         echo "/Game/TheIsle/Maps/Thenyaw_Island/Thenyaw_Island" ;;
    esac
}

# Build_Launch_Args <key>
# Needs SERVER_PORT and RESOLVED_QUERY_PORT / RESOLVED_RCON_PORT.
# shellcheck disable=SC2034  # LAUNCH_ARGS is consumed by entrypoint.sh
Build_Launch_Args() {
    local key="$1"
    Resolve_Branch "$key" || return 1
    local dir bin
    dir="$(Branch_Dir "$key")"
    bin="${dir}/${BRANCH_BINARY}"

    export GAME_CWD="$dir"
    export GAME_BRANCH_LABEL="$BRANCH_LABEL"
    export RCON_ENABLED="$BRANCH_RCON_OK"
    export RCON_HOST="127.0.0.1"
    export RCON_PORT="${RESOLVED_RCON_PORT}"

    if [[ "$key" == "legacy" ]]; then
        local map
        map="$(Legacy_Map_Path "${LEGACY_MAP:-thenyaw}")"
        export GAME_LOG_FILE="${dir}/TheIsle/Saved/Logs/TheIsle.log"
        export USE_XVFB=1
        export WINEDEBUG="-all"
        export WINEARCH="win64"
        export WINEPREFIX="${CONTAINER_HOME:-/home/container}/.wine"
        # Skip the wine-mono / wine-gecko prompts; the server needs neither.
        export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree=;mshtml=}"
        LAUNCH_ARGS=(wine "$bin"
            "${map}?listen?MaxPlayers=${MAX_PLAYERS:-100}?game=Survival?Port=${SERVER_PORT}?QueryPort=${RESOLVED_QUERY_PORT}"
            "-Port=${SERVER_PORT}" "-QueryPort=${RESOLVED_QUERY_PORT}"
            -log -stdout -FullStdOutLogOutput -unattended -nosplash -USEALLAVAILABLECORES)
        return 0
    fi

    export GAME_LOG_FILE=""
    export USE_XVFB=0
    LAUNCH_ARGS=("$bin")
    if [[ "$key" == "spiro" ]]; then
        LAUNCH_ARGS+=("/Game/TheIsle/Maps/Game/Isla_Spiro/Isla_Spiro?Port=${SERVER_PORT}")
    fi
    LAUNCH_ARGS+=("-Port=${SERVER_PORT}"
        "-ini:Engine:[EpicOnlineServices]:DedicatedServerClientId=${EOS_CLIENT_ID}"
        "-ini:Engine:[EpicOnlineServices]:DedicatedServerClientSecret=${EOS_CLIENT_SECRET}")
    return 0
}

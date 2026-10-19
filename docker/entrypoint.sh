#!/bin/bash

set -uo pipefail

export HELPERS_DIR="${HELPERS_DIR:-/helpers}"
export CONTAINER_HOME="${CONTAINER_HOME:-/home/container}"
SECTIONS_DIR="${SECTIONS_DIR:-/sections}"

export TERM="${TERM:-xterm}"
/bin/bash /splash_screen.sh

source "${HELPERS_DIR}/messages.sh"
source "${HELPERS_DIR}/branches.sh"
source "${HELPERS_DIR}/ports.sh"
for s in migrate_layout branch_switch update_game config_sync launch_args; do
    if [[ -f "${SECTIONS_DIR}/${s}.sh" ]]; then
        # shellcheck disable=SC1090  # section files are listed above
        source "${SECTIONS_DIR}/${s}.sh"
    else
        Error "${SECTIONS_DIR}/${s}.sh does not exist or cannot be found." "1"
    fi
done

if [[ "${EGG_DEBUG:-0}" == "1" ]]; then
    Info "Egg Debug Mode Enabled!"
fi

cd "${CONTAINER_HOME}" || exit 1
export HOME="${CONTAINER_HOME}"

########################
# VALIDATE BRANCH      #
########################

BRANCH="$(Normalize_Branch "${GAME_BRANCH:-evrima}")"
if ! Resolve_Branch "$BRANCH"; then
    Error "Unknown Game Branch '${GAME_BRANCH:-}'. Valid values: ${SUPPORTED_BRANCHES// /, }" "1"
fi
Info "Game branch: ${BRANCH_LABEL}"

########################
# PORTS                #
########################

if ! Resolve_Ports; then
    Error "SERVER_PORT '${SERVER_PORT:-}' is not a valid port." "1"
fi
Info "Ports: ${PORT_SOURCES}"
if [[ "$BRANCH" == "legacy" ]]; then
    Info "Legacy uses the game and query ports only (no RCON / queue)."
fi

##########################################
# MIGRATE / SWITCH / PRUNE / UPDATE      #
##########################################

Migrate_Flat_Layout || true
Ensure_Pteroignore
Detect_Branch_Switch "$BRANCH"
Prune_Inactive_Branches "$BRANCH"
if ! Update_Game "$BRANCH" "$BRANCH_SWITCHED"; then
    exit 1
fi
if [[ "$BRANCH" == "legacy" ]]; then
    Ensure_Legacy_Steamworks
    # Legacy reads its Message Of The Day from Saved/MOTD.txt (empty = no popup).
    mkdir -p "$(Branch_Dir legacy)/TheIsle/Saved/Logs"
    [[ -f "$(Branch_Dir legacy)/TheIsle/Saved/MOTD.txt" ]] || : > "$(Branch_Dir legacy)/TheIsle/Saved/MOTD.txt"
fi

########################
# CONFIG               #
########################

Sync_Branch_Config "$BRANCH" || Warn "Could not sync Game.ini for ${BRANCH}."
Link_Active_Config "$BRANCH"
Info "Active config folder: ServerConfig -> branches/${BRANCH}/TheIsle/Saved/Config/${BRANCH_CONF_SUBDIR}"

########################
# LAUNCH               #
########################

mkdir -p "${CONTAINER_HOME}/logs"
# Keep 5 days of wrapper/game logs.
find "${CONTAINER_HOME}/logs" -type f -name '*.log' -mtime +5 -delete 2>/dev/null || true

Build_Launch_Args "$BRANCH" || Error "Could not build launch arguments." "1"
export GAME_BRANCH_KEY="$BRANCH"
export RCON_PASSWORD="${RCON_PASSWORD:-}"
if [[ "$RCON_ENABLED" == "1" && -z "$RCON_PASSWORD" ]]; then
    Warn "RCON Password is empty - console commands will not reach the server."
    RCON_ENABLED=0
fi

Success "Starting ${BRANCH_LABEL} on port ${SERVER_PORT}..."
exec node /wrapper.js "${LAUNCH_ARGS[@]}"

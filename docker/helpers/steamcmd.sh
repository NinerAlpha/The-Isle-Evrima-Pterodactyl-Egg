#!/bin/bash

source "${HELPERS_DIR:-/helpers}/messages.sh"
source "${HELPERS_DIR:-/helpers}/branches.sh"

STEAMCMD_DIR="${CONTAINER_HOME:-/home/container}/steamcmd"
STEAMCMD_BIN="${STEAMCMD_BIN:-${STEAMCMD_DIR}/steamcmd.sh}"
STEAMCMD_RETRIES="${STEAMCMD_RETRIES:-3}"
STEAMCMD_RETRY_DELAY="${STEAMCMD_RETRY_DELAY:-5}"

# Installs SteamCMD into the server volume if it is missing (e.g. deleted by
# the user). Returns non-zero when the download fails.
Ensure_SteamCMD() {
    [[ -x "${STEAMCMD_BIN}" || -f "${STEAMCMD_BIN}" ]] && return 0

    Warn "SteamCMD not found - installing it..."
    mkdir -p "${STEAMCMD_DIR}" || return 1
    curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
        | tar -xz -C "${STEAMCMD_DIR}" || return 1

    # Steam client libraries for the Linux server builds (Steam API init).
    local home="${CONTAINER_HOME:-/home/container}"
    mkdir -p "${home}/.steam/sdk32" "${home}/.steam/sdk64"
    cp -f "${STEAMCMD_DIR}/linux32/steamclient.so" "${home}/.steam/sdk32/steamclient.so" 2>/dev/null || true
    cp -f "${STEAMCMD_DIR}/linux64/steamclient.so" "${home}/.steam/sdk64/steamclient.so" 2>/dev/null || true
    Success "SteamCMD installed."
}

# Build_SteamCMD_Args <branch_key> <install_dir> <validate 0|1>
# Fills the global STEAMCMD_ARGS array (no shell parsing, no eval).
Build_SteamCMD_Args() {
    local key="$1" dir="$2" validate="${3:-0}"
    Resolve_Branch "$key" || return 1

    STEAMCMD_ARGS=(+@sSteamCmdForcePlatformType "${BRANCH_PLATFORM}"
                   +force_install_dir "$dir"
                   +login anonymous
                   +app_update "${THE_ISLE_APPID}" -beta "${BRANCH_STEAM_BETA}")
    if [[ "${BRANCH_NEEDS_PASS}" == "1" && -n "${BETA_PASSWORD:-}" ]]; then
        STEAMCMD_ARGS+=(-betapassword "${BETA_PASSWORD}")
    fi
    [[ "$validate" == "1" ]] && STEAMCMD_ARGS+=(validate)
    STEAMCMD_ARGS+=(+quit)
    return 0
}

# SteamCMD_Update_Branch <branch_key> <install_dir> <validate 0|1>
# Runs SteamCMD with retries + exponential backoff. Returns non-zero after the
# last failed attempt (callers decide whether that is fatal).
SteamCMD_Update_Branch() {
    local key="$1" dir="$2" validate="${3:-0}"
    Build_SteamCMD_Args "$key" "$dir" "$validate" || return 1
    mkdir -p "$dir" || return 1

    local shown="${STEAMCMD_ARGS[*]}"
    [[ -n "${BETA_PASSWORD:-}" ]] && shown="${shown//${BETA_PASSWORD}/********}"
    Debug "SteamCMD: ${shown}"

    local attempt=1 rc
    while (( attempt <= STEAMCMD_RETRIES )); do
        rc=0
        HOME="${CONTAINER_HOME:-/home/container}" "${STEAMCMD_BIN}" "${STEAMCMD_ARGS[@]}" || rc=$?
        if (( rc == 0 )); then
            return 0
        fi
        Warn "SteamCMD exited with code ${rc} (attempt ${attempt}/${STEAMCMD_RETRIES})."
        if (( attempt < STEAMCMD_RETRIES )); then
            local wait=$(( STEAMCMD_RETRY_DELAY * (1 << (attempt - 1)) ))
            Info "Retrying in ${wait}s..."
            sleep "$wait"
        fi
        attempt=$((attempt + 1))
    done
    return 1
}

#!/bin/bash

#############################
# GAME INSTALL / UPDATE     #
#############################

source "${HELPERS_DIR:-/helpers}/messages.sh"
source "${HELPERS_DIR:-/helpers}/branches.sh"
source "${HELPERS_DIR:-/helpers}/steamcmd.sh"

# Update_Game <key> <switched 0|1>
# Installs/updates the branch into branches/<key>. A missing install or a
# branch switch always runs a validated update; otherwise AUTO_UPDATE /
# VALIDATE decide. Writes .active-branch only when the branch's server binary
# is present afterwards. Returns 1 if the server cannot start.
Update_Game() {
    local key="$1" switched="${2:-0}"
    local home="${CONTAINER_HOME:-/home/container}"
    Resolve_Branch "$key" || return 1

    local dir bin installed=0
    dir="$(Branch_Dir "$key")"
    bin="${dir}/${BRANCH_BINARY}"
    [[ -f "$bin" ]] && installed=1

    local run=0 validate=0
    if [[ "$installed" == "0" || "$switched" == "1" ]]; then
        run=1; validate=1
    elif [[ "${AUTO_UPDATE:-1}" == "1" ]]; then
        run=1
        [[ "${VALIDATE:-0}" == "1" ]] && validate=1
    fi

    if [[ "$run" == "1" ]]; then
        if [[ "${BRANCH_NEEDS_PASS}" == "1" && -z "${BETA_PASSWORD:-}" ]]; then
            Warn "${BRANCH_LABEL} is a private Steam branch - set the Beta Password variable if the download fails."
        fi
        if ! Ensure_SteamCMD; then
            Error "SteamCMD is missing and could not be downloaded."
        else
            Info "Updating ${BRANCH_LABEL} (Steam branch '${BRANCH_STEAM_BETA}', ${BRANCH_PLATFORM}, validate=${validate})..."
            if SteamCMD_Update_Branch "$key" "$dir" "$validate"; then
                Success "${BRANCH_LABEL} is up to date."
            else
                Warn "SteamCMD could not update ${BRANCH_LABEL}."
            fi
        fi
    else
        Info "Auto update disabled - starting the installed ${BRANCH_LABEL} build."
    fi

    if [[ ! -f "$bin" ]]; then
        Error "${BRANCH_LABEL} is not installed (${BRANCH_BINARY} missing)."
        if [[ "${BRANCH_NEEDS_PASS}" == "1" ]]; then
            Error "Check the Beta Password (and Hordetest Steam Branch) variables - private branches need the correct password."
        fi
        Error "Restart to retry, or switch Game Branch back to a working branch."
        return 1
    fi

    [[ "$BRANCH_PLATFORM" == "linux" ]] && chmod +x "$bin" 2>/dev/null
    printf '%s\n' "$key" > "${home}/.active-branch"
    return 0
}

# Legacy (Windows build under Wine) needs the Windows steamclient64.dll next
# to the exe to log into the Steam master server. Fetch it from the
# Steamworks SDK Redist (app 1007, Windows depot) once.
Ensure_Legacy_Steamworks() {
    local dir bindir home="${CONTAINER_HOME:-/home/container}"
    dir="$(Branch_Dir legacy)"
    bindir="${dir}/TheIsle/Binaries/Win64"
    [[ -d "$bindir" ]] || return 0

    if [[ ! -f "${bindir}/steamclient64.dll" ]] && Ensure_SteamCMD; then
        Info "Installing Steamworks SDK Redist (Windows) for the Legacy server browser listing..."
        local redist="${home}/.steamworks-win"
        HOME="$home" "${STEAMCMD_BIN}" +@sSteamCmdForcePlatformType windows \
            +force_install_dir "$redist" +login anonymous +app_update 1007 +quit || true
        local dll
        for dll in steamclient64.dll tier0_s64.dll vstdlib_s64.dll; do
            [[ -f "${redist}/${dll}" ]] && cp -f "${redist}/${dll}" "${bindir}/${dll}"
        done
        if [[ ! -f "${bindir}/steamclient64.dll" ]]; then
            Warn "steamclient64.dll unavailable - Legacy will run but only via direct connect."
        fi
    fi
    # steam_api resolves the game appid from steam_appid.txt beside the exe.
    [[ -f "${bindir}/steam_appid.txt" ]] || echo "376210" > "${bindir}/steam_appid.txt"
    return 0
}

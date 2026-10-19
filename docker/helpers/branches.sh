#!/bin/bash

######################################
# GAME BRANCH REGISTRY (single map)  #
######################################
#
# One source of truth mapping a GAME_BRANCH value to everything that depends
# on it. Update THIS file when the developers add/rename a Steam branch.
#
#   BRANCH_KEY         : normalized branch name (evrima|spiro|hordetesting|legacy)
#   BRANCH_STEAM_BETA  : SteamCMD "-beta" value for app 412680
#   BRANCH_PLATFORM    : linux | windows (legacy has no Linux server depot)
#   BRANCH_CONF_SUBDIR : Saved/Config/<this> holds Game.ini / Engine.ini
#   BRANCH_BINARY      : server executable, relative to the branch install dir
#   BRANCH_RCON_OK     : 1 if the build has Evrima RCON, else 0
#   BRANCH_NEEDS_PASS  : 1 if the Steam branch is private (needs BETA_PASSWORD)
#   BRANCH_LABEL       : human-friendly label for logs
#
# Verified against `steamcmd +app_info_print 412680`: the listed branches are
# public (Windows depot 412681 only), spiro0.11.59.04 and evrima (both depots).
# The app reports "privatebranches 1": hordetesting is not listed publicly and
# needs a beta password. Its Steam name can be overridden with HORDETEST_BRANCH.

# shellcheck disable=SC2034  # used by steamcmd.sh / entrypoint.sh
THE_ISLE_APPID=412680
# shellcheck disable=SC2034
SUPPORTED_BRANCHES="evrima spiro hordetesting legacy"

# Normalize_Branch <value> -> prints lowercased, whitespace-stripped value.
Normalize_Branch() {
    local b="${1:-}"
    b="${b,,}"
    printf '%s' "${b//[[:space:]]/}"
}

# Resolve_Branch <game_branch>
# Populates the BRANCH_* globals. Returns 1 for an unknown branch.
# SC2034: the globals are consumed by the scripts that source this file.
# shellcheck disable=SC2034
Resolve_Branch() {
    local b
    b="$(Normalize_Branch "${1:-}")"

    BRANCH_KEY="$b"
    BRANCH_PLATFORM="linux"
    BRANCH_CONF_SUBDIR="LinuxServer"
    BRANCH_BINARY="TheIsle/Binaries/Linux/TheIsleServer-Linux-Shipping"
    BRANCH_RCON_OK=1
    BRANCH_NEEDS_PASS=0

    case "$b" in
        evrima)
            BRANCH_STEAM_BETA="evrima"
            BRANCH_LABEL="Evrima (live)"
            ;;
        spiro)
            BRANCH_STEAM_BETA="spiro0.11.59.04"
            BRANCH_LABEL="Spiro (frozen 0.11.59.04)"
            ;;
        hordetesting)
            BRANCH_STEAM_BETA="${HORDETEST_BRANCH:-hordetesting}"
            BRANCH_NEEDS_PASS=1
            BRANCH_LABEL="Hordetesting (private test branch)"
            ;;
        legacy)
            BRANCH_STEAM_BETA="public"
            BRANCH_PLATFORM="windows"
            BRANCH_CONF_SUBDIR="WindowsServer"
            BRANCH_BINARY="TheIsle/Binaries/Win64/TheIsleServer-Win64-Shipping.exe"
            BRANCH_RCON_OK=0
            BRANCH_LABEL="Legacy (frozen Feb 2022, Windows build via Wine)"
            ;;
        *)
            BRANCH_STEAM_BETA=""
            BRANCH_LABEL="unknown"
            return 1
            ;;
    esac
    return 0
}

# Branch_Dir <key> -> install directory of a branch.
Branch_Dir() {
    printf '%s/branches/%s' "${CONTAINER_HOME:-/home/container}" "$1"
}

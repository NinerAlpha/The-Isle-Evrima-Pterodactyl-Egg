#!/bin/bash

##########################################
# BRANCH SWITCH DETECTION + PRUNING      #
##########################################
#
# .active-branch records the branch whose install last booted successfully.
# A different GAME_BRANCH is a switch: the requested branch gets a validated
# update into its own branches/<key>/ directory, so the old branch's files are
# never overwritten and its saves/configs stay where they are.
#
# With PRUNE_INACTIVE_BRANCHES=1 (default) every branch other than the
# requested one has its game files deleted to free disk; only its
# TheIsle/Saved (configs, saves, logs) is kept, so switching back restores it
# after a re-download.

source "${HELPERS_DIR:-/helpers}/messages.sh"
source "${HELPERS_DIR:-/helpers}/branches.sh"

# Detect_Branch_Switch <requested_key>
# Sets PREVIOUS_BRANCH and BRANCH_SWITCHED (0|1).
# shellcheck disable=SC2034  # read by entrypoint.sh
Detect_Branch_Switch() {
    local home="${CONTAINER_HOME:-/home/container}"
    PREVIOUS_BRANCH=""
    BRANCH_SWITCHED=0
    [[ -f "${home}/.active-branch" ]] && PREVIOUS_BRANCH="$(Normalize_Branch "$(cat "${home}/.active-branch")")"
    if [[ -n "$PREVIOUS_BRANCH" && "$PREVIOUS_BRANCH" != "$1" ]]; then
        BRANCH_SWITCHED=1
        Info "Branch switch detected: ${PREVIOUS_BRANCH} -> $1"
    fi
    return 0
}

# Prune_Branch <key> : delete a branch's game files, keep TheIsle/Saved.
Prune_Branch() {
    local dir
    dir="$(Branch_Dir "$1")"
    [[ -d "$dir" ]] || return 0

    # Nothing but TheIsle/Saved left -> already pruned.
    local leftovers
    leftovers="$(find "$dir" -mindepth 1 -maxdepth 2 \
                    ! -path "${dir}/TheIsle" ! -path "${dir}/TheIsle/Saved" -print -quit)"
    [[ -z "$leftovers" ]] && return 0

    local before
    before="$(du -sh "$dir" 2>/dev/null | cut -f1)"
    find "$dir" -mindepth 1 -maxdepth 1 ! -name TheIsle -exec rm -rf {} +
    if [[ -d "${dir}/TheIsle" ]]; then
        find "${dir}/TheIsle" -mindepth 1 -maxdepth 1 ! -name Saved -exec rm -rf {} +
    fi
    Info "Pruned inactive branch '$1' (was ${before:-?}); its saves and configs in branches/$1/TheIsle/Saved are kept."
}

# Prune_Inactive_Branches <requested_key>
Prune_Inactive_Branches() {
    [[ "${PRUNE_INACTIVE_BRANCHES:-1}" == "1" ]] || return 0
    local home="${CONTAINER_HOME:-/home/container}" d key
    for d in "${home}"/branches/*/; do
        [[ -d "$d" ]] || continue
        key="$(basename "$d")"
        [[ "$key" == "$1" ]] && continue
        Prune_Branch "$key"
    done
    return 0
}

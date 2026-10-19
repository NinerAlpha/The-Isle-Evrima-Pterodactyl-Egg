#!/bin/bash

#########################################
# MIGRATE OLD FLAT LAYOUT -> branches/  #
#########################################
#
# Servers created with the previous multi-branch egg (yolks Wine image +
# start-theisle.sh) have ONE install at the server root and a .current-branch
# marker. This moves that install into branches/<branch>/ so the per-branch
# layout takes over without a reinstall. Idempotent: does nothing once
# branches/ exists or on a fresh server.

source "${HELPERS_DIR:-/helpers}/messages.sh"
source "${HELPERS_DIR:-/helpers}/branches.sh"

# Root entries that belong to the container/home, not to a game install.
_MIGRATE_KEEP=(steamcmd branches logs branch-defaults start-theisle.sh ServerConfig)

_Is_Kept_Entry() {
    local name="$1" k
    [[ "$name" == .* ]] && return 0   # dotfiles: .steam, .wine, markers, .pteroignore
    for k in "${_MIGRATE_KEEP[@]}"; do
        [[ "$name" == "$k" ]] && return 0
    done
    return 1
}

Migrate_Flat_Layout() {
    local home="${CONTAINER_HOME:-/home/container}"
    [[ -d "${home}/branches" ]] && return 0
    [[ -d "${home}/TheIsle" || -f "${home}/.current-branch" ]] || return 0

    local old=""
    [[ -f "${home}/.current-branch" ]] && old="$(Normalize_Branch "$(cat "${home}/.current-branch")")"
    if ! Resolve_Branch "$old"; then
        # No usable marker: infer from which binary is on disk.
        if [[ -d "${home}/TheIsle/Binaries/Win64" && ! -d "${home}/TheIsle/Binaries/Linux" ]]; then
            old="legacy"
        else
            old="evrima"
        fi
    fi

    Info "Migrating existing install (branch '${old}') to the per-branch layout..."
    local dest
    dest="$(Branch_Dir "$old")"
    mkdir -p "$dest" || { Error "Could not create ${dest} - migration skipped."; return 1; }

    local entry name
    shopt -s nullglob dotglob
    for entry in "${home}"/*; do
        name="$(basename "$entry")"
        _Is_Kept_Entry "$name" && continue
        mv -f "$entry" "$dest/" || Warn "Could not move ${name} into ${dest}"
    done
    shopt -u nullglob dotglob

    # The old egg stashed other branches' Game.ini as Game.ini.<branch>; give
    # each one to its own branch so it is restored when switching to it.
    local cfg b sub target
    for sub in LinuxServer WindowsServer; do
        for cfg in "${dest}/TheIsle/Saved/Config/${sub}"/Game.ini.*; do
            [[ -f "$cfg" ]] || continue
            b="${cfg##*/Game.ini.}"
            Resolve_Branch "$b" || continue
            [[ "$b" == "$old" ]] && { rm -f "$cfg"; continue; }
            target="$(Branch_Dir "$b")/TheIsle/Saved/Config/${BRANCH_CONF_SUBDIR}"
            mkdir -p "$target"
            if [[ ! -f "${target}/Game.ini" ]]; then
                mv -f "$cfg" "${target}/Game.ini"
                Info "Restored stashed ${b} Game.ini into branches/${b}"
            fi
        done
    done

    # Obsolete files from the previous egg.
    rm -rf "${home}/branch-defaults" "${home}/start-theisle.sh" "${home}/.steamworks-win"
    rm -f "${home}/.current-branch"
    printf '%s\n' "$old" > "${home}/.active-branch"

    Success "Migration complete: install moved to branches/${old}."
    return 0
}

# Backups should hold every branch's saves/configs. Writes .pteroignore when it
# is missing or still the previous egg's version (which pointed at the old
# root TheIsle/Saved); a host-customized file is left alone.
Ensure_Pteroignore() {
    local f="${CONTAINER_HOME:-/home/container}/.pteroignore"
    if [[ -f "$f" ]] && ! grep -qx '!TheIsle/Saved' "$f"; then
        return 0
    fi
    cat > "$f" << 'IGNORE'
*
!branches/
!branches/*/
!branches/*/TheIsle/
!branches/*/TheIsle/Saved/
!branches/*/TheIsle/Saved/**
IGNORE
}

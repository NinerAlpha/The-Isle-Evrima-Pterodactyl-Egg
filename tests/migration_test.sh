#!/bin/bash
# Tests for migrating the previous egg's flat layout (docker/sections/migrate_layout.sh).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "${SECTIONS_DIR}/migrate_layout.sh"
H="$CONTAINER_HOME"

# Old egg layout: evrima install at the root with a stashed spiro + legacy config.
mkdir -p "$H/TheIsle/Binaries/Linux" "$H/TheIsle/Saved/Config/LinuxServer" "$H/TheIsle/Saved/Config/WindowsServer" \
         "$H/steamcmd" "$H/steamapps" "$H/Engine" "$H/branch-defaults/evrima" "$H/.steam/sdk64" "$H/logs"
touch "$H/TheIsle/Binaries/Linux/TheIsleServer-Linux-Shipping" "$H/start-theisle.sh" "$H/steamclient.so"
echo "ServerName=live" > "$H/TheIsle/Saved/Config/LinuxServer/Game.ini"
echo "ServerName=spiro-stash" > "$H/TheIsle/Saved/Config/LinuxServer/Game.ini.spiro"
echo "ServerName=evrima-stash" > "$H/TheIsle/Saved/Config/LinuxServer/Game.ini.evrima"
echo "ServerName=legacy-stash" > "$H/TheIsle/Saved/Config/WindowsServer/Game.ini.legacy"
echo "*" > "$H/.pteroignore"
echo "evrima" > "$H/.current-branch"

Migrate_Flat_Layout >/dev/null
E="$H/branches/evrima"
[[ -f "$E/TheIsle/Binaries/Linux/TheIsleServer-Linux-Shipping" ]] && pass "install moved" || fail "install not moved"
[[ -d "$E/steamapps" && -d "$E/Engine" && -f "$E/steamclient.so" ]] && pass "root game files moved" || fail "root files left behind"
check "live config stays with evrima" "ServerName=live" "$(cat "$E/TheIsle/Saved/Config/LinuxServer/Game.ini")"
check "spiro stash restored" "ServerName=spiro-stash" "$(cat "$H/branches/spiro/TheIsle/Saved/Config/LinuxServer/Game.ini")"
check "legacy stash restored" "ServerName=legacy-stash" "$(cat "$H/branches/legacy/TheIsle/Saved/Config/WindowsServer/Game.ini")"
[[ ! -e "$E/TheIsle/Saved/Config/LinuxServer/Game.ini.evrima" ]] && pass "own stale stash removed" || fail "own stash kept"
[[ -d "$H/steamcmd" && -d "$H/.steam" && -d "$H/logs" && -f "$H/.pteroignore" ]] && pass "home entries kept at root" || fail "home entries moved"
[[ ! -e "$H/start-theisle.sh" && ! -e "$H/branch-defaults" && ! -e "$H/.current-branch" ]] && pass "obsolete files removed" || fail "obsolete files remain"
check "active marker" "evrima" "$(cat "$H/.active-branch")"

# Idempotent: a second run changes nothing.
before="$(find "$H" | sort | md5sum)"
Migrate_Flat_Layout >/dev/null
check "second run is a no-op" "$before" "$(find "$H" | sort | md5sum)"

# Missing marker on a Windows-only install -> legacy.
rm -rf "$H"; mkdir -p "$H/TheIsle/Binaries/Win64"
Migrate_Flat_Layout >/dev/null
[[ -d "$H/branches/legacy/TheIsle/Binaries/Win64" ]] && pass "marker-less Win64 install migrates to legacy" || fail "legacy inference"

# Fresh server: nothing to do.
rm -rf "$H"; mkdir -p "$H"
Migrate_Flat_Layout >/dev/null
[[ ! -d "$H/branches" ]] && pass "fresh server untouched" || fail "fresh server migrated"

# .pteroignore: old egg version is upgraded, custom files are kept.
printf '*\n!TheIsle/Saved\n' > "$H/.pteroignore"
Ensure_Pteroignore
grep -qx '!branches/\*/TheIsle/Saved/\*\*' "$H/.pteroignore" && pass "old .pteroignore upgraded" || fail "old .pteroignore kept"
printf 'custom\n' > "$H/.pteroignore"
Ensure_Pteroignore
check "custom .pteroignore kept" "custom" "$(cat "$H/.pteroignore")"
rm -f "$H/.pteroignore"; Ensure_Pteroignore
[[ -f "$H/.pteroignore" ]] && pass "missing .pteroignore created" || fail "missing .pteroignore"
finish

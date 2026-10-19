#!/bin/bash
# The Isle (multi-branch) - install script
# Runs in the debian:trixie-slim installer container. Server files: /mnt/server
#
# Installs SteamCMD and the selected Game Branch into branches/<branch>/.
# Everything else (configs, ports, branch switching, migration of servers made
# with the previous egg) is handled by the image's entrypoint on every start.
# Keep this file in sync with the egg's embedded installation script.

export DEBIAN_FRONTEND=noninteractive
dpkg --add-architecture i386
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates tar lib32gcc-s1 lib32stdc++6

APPID=412680
SERVER=/mnt/server

## resolve branch (mirrors docker/helpers/branches.sh)
BRANCH="$(echo "${GAME_BRANCH:-evrima}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
PASS_ARGS=()
case "${BRANCH}" in
    evrima)       STEAM_BRANCH="evrima";          PLATFORM="linux" ;;
    spiro)        STEAM_BRANCH="spiro0.11.59.04"; PLATFORM="linux" ;;
    hordetesting) STEAM_BRANCH="${HORDETEST_BRANCH:-hordetesting}"; PLATFORM="linux"
                  [ -n "${BETA_PASSWORD:-}" ] && PASS_ARGS=(-betapassword "${BETA_PASSWORD}") ;;
    legacy)       STEAM_BRANCH="public";          PLATFORM="windows" ;;
    *)
        echo "Unknown Game Branch '${GAME_BRANCH}' - installing evrima"
        BRANCH="evrima"; STEAM_BRANCH="evrima"; PLATFORM="linux"
        ;;
esac
INSTALL_DIR="${SERVER}/branches/${BRANCH}"

echo "-----------------------------------------"
echo "Installing The Isle branch: ${BRANCH} (Steam branch: ${STEAM_BRANCH}, ${PLATFORM})"
echo "-----------------------------------------"

## download and install steamcmd
cd /tmp || exit 1
mkdir -p "${SERVER}/steamcmd" "${INSTALL_DIR}"
curl -sSL -o steamcmd.tar.gz https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
tar -xzvf steamcmd.tar.gz -C "${SERVER}/steamcmd"
cd "${SERVER}/steamcmd" || exit 1

# SteamCMD fails otherwise for some reason, even running as root.
chown -R root:root /mnt
export HOME="${SERVER}"

# SteamCMD warmup (prevents "Missing configuration" on first run)
./steamcmd.sh +login anonymous +quit || true

## install game (always validated on install/reinstall)
if ./steamcmd.sh +@sSteamCmdForcePlatformType "${PLATFORM}" +force_install_dir "${INSTALL_DIR}" \
        +login anonymous +app_update "${APPID}" -beta "${STEAM_BRANCH}" "${PASS_ARGS[@]}" validate +quit; then
    echo "${BRANCH}" > "${SERVER}/.active-branch"
else
    echo "SteamCMD failed to install '${STEAM_BRANCH}'. The server will retry on start."
    [ "${BRANCH}" = "hordetesting" ] && echo "Hordetesting is a private branch - check the Beta Password variable."
fi

## Steam client libraries for the Linux server builds
mkdir -p "${SERVER}/.steam/sdk32" "${SERVER}/.steam/sdk64"
cp -v linux32/steamclient.so "${SERVER}/.steam/sdk32/steamclient.so"
cp -v linux64/steamclient.so "${SERVER}/.steam/sdk64/steamclient.so"

## Backups: only saves and configs of every branch
cat > "${SERVER}/.pteroignore" << 'EOF'
*
!branches/
!branches/*/
!branches/*/TheIsle/
!branches/*/TheIsle/Saved/
!branches/*/TheIsle/Saved/**
EOF

echo "-----------------------------------------"
echo "Installation completed (branch: ${BRANCH})"
echo "-----------------------------------------"

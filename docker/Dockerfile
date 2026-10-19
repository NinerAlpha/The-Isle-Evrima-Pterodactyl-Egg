FROM        --platform=$TARGETOS/$TARGETARCH debian:trixie-slim

LABEL       author="Pine Hosting" maintainer="NinerAlpha"
LABEL       org.opencontainers.image.source="https://github.com/NinerAlpha/The-Isle-Evrima-Pterodactyl-Egg"
LABEL       org.opencontainers.image.licenses=MIT

ENV         DEBIAN_FRONTEND=noninteractive

# One image for every branch: native Linux deps for Evrima / Spiro /
# Hordetesting, Wine + Xvfb for the Windows-only Legacy build, Node for the
# wrapper. Switching branches never requires changing the Docker image.
RUN         dpkg --add-architecture i386 \
            && apt-get update \
            && apt-get upgrade -y \
            && apt-get install -y --no-install-recommends \
                # SteamCMD (32-bit) + base tools
                lib32gcc-s1 \
                lib32stdc++6 \
                libc6-i386 \
                libcurl4 \
                libcurl4:i386 \
                ca-certificates \
                curl \
                tar \
                jq \
                tzdata \
                iproute2 \
                procps \
                dos2unix \
                # Legacy branch (Windows build)
                wine \
                wine64 \
                xvfb \
                # Wrapper
                nodejs \
            # SteamCMD's 32-bit crash reporter dlopen()s the unversioned
            # libcurl.so, which Debian only ships in -dev packages.
            && for d in /usr/lib/i386-linux-gnu /usr/lib/x86_64-linux-gnu; do \
                   if [ -e "$d/libcurl.so.4" ] && [ ! -e "$d/libcurl.so" ]; then \
                       ln -s libcurl.so.4 "$d/libcurl.so"; \
                   fi; \
               done \
            && rm -rf /var/lib/apt/lists/*

# glibc heap tuning for long-running servers.
ENV         MALLOC_ARENA_MAX=2 \
            MALLOC_TRIM_THRESHOLD_=131072

RUN         useradd -d /home/container -m container

WORKDIR     /home/container

COPY        --chown=container:container ./wrapper.js ./rcon.js /
COPY        --chown=container:container ./entrypoint.sh ./splash_screen.sh /
COPY        --chown=container:container --chmod=0755 ./sections /sections
COPY        --chown=container:container --chmod=0755 ./helpers /helpers
COPY        --chown=container:container ./defaults /defaults

RUN         dos2unix /entrypoint.sh /splash_screen.sh /wrapper.js /rcon.js \
            && find /sections /helpers -type f -name "*.sh" -exec dos2unix {} \; \
            && find /defaults -type f -exec dos2unix {} \; \
            && chmod +x /entrypoint.sh /splash_screen.sh

USER        container
ENV         USER=container HOME=/home/container

ENTRYPOINT  ["/bin/bash", "/entrypoint.sh"]

LABEL       org.opencontainers.image.title="The Isle Dedicated Server (multi-branch)"
LABEL       org.opencontainers.image.description="Pterodactyl image for The Isle: Evrima, Spiro, Hordetesting and Legacy (Wine) with a built-in RCON console bridge"
LABEL       org.opencontainers.image.vendor="Pine Hosting"

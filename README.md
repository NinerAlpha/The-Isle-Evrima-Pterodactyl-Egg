# PineHosting Pterodactyl Egg for The Isle (multi-branch) - by NinerAlpha

One egg and one Docker image for every branch of The Isle dedicated server
(Steam app `412680`):

| Branch (`GAME_BRANCH`) | Steam branch | Build | RCON console |
|---|---|---|---|
| `evrima` | `evrima` | Linux (live, Gateway) | ✅ |
| `spiro` | `spiro0.11.59.04` | Linux (frozen 0.11.59.04, Isla Spiro) | ✅ (`serverdetails`/`save` reply limited) |
| `hordetesting` | `hordetesting` (private, needs **Beta Password**) | Linux | ✅ |
| `legacy` | `public` | Windows build via Wine (frozen Feb 2022) | ❌ (no RCON in Legacy) |

Repository layout (same pattern as the Rust egg):

- **`docker/Dockerfile`**: the image (`ghcr.io/nineralpha/the_isle`). It ships SteamCMD deps, Wine + Xvfb for Legacy, and Node for the wrapper.
- **`docker/entrypoint.sh`**: runs on every start. It resolves the branch and ports, migrates old servers, switches or prunes branches, updates the game, syncs configs and launches the wrapper.
- **`docker/wrapper.js`**: runs the game and bridges the panel console to Evrima RCON. On stop it saves the world first.
- **`docker/rcon.js`**: the Evrima RCON protocol, command table and a reconnecting client. It has no npm dependencies.
- **`docker/helpers/`**: the branch registry (`branches.sh`), port resolver (`ports.sh`), SteamCMD with retries, and messages.
- **`docker/sections/`**: migration, branch switch and prune, game update, config sync, launch arguments.
- **`docker/defaults/<branch>/`**: the default `Game.ini` / `Engine.ini` for each branch.
- **`egg-the-isle-multibranch.json`** + **`install-script.sh`**: the egg. CI checks that the embedded install script matches the file.

## Switching branches

Change **Game Branch** in the Startup tab and restart. That's all: no reinstall, no Docker image change, and no port changes.

On start the image:

1. Detects the switch by comparing it with `.active-branch`.
2. Downloads the new branch into its own folder, `branches/<branch>/`, with SteamCMD `validate`.
3. With **Prune Inactive Branches** = `1` (the default), deletes the *game files* of the other branches to save disk. Each branch's `TheIsle/Saved` is always kept, so its configs, saves and logs come back when you switch back (after a re-download). Set it to `0` to keep every branch installed for instant switching.
4. Seeds `Game.ini`/`Engine.ini` from the branch defaults if missing, then syncs the panel variables into it.
5. Points the **`ServerConfig`** link at the active branch's config folder. Users always edit `ServerConfig/Game.ini`, whatever the branch.

`.active-branch` only moves once the new branch is installed. If a download fails (wrong Beta Password, Steam down), the server says why and refuses to start. Switching back works immediately.

### Hordetesting

`hordetesting` is not in Steam's public branch list for app 412680 (`privatebranches 1`), so it needs the **Beta Password** from the developers. If the branch is ever renamed, change **Hordetest Steam Branch** (admin-only) instead of updating the image.

### Legacy

Legacy has no Linux server build. The image installs the Windows depot and runs it under Wine (64-bit prefix, headless Xvfb). It fetches the Steamworks redist DLLs for the server-browser listing. Legacy has no RCON or queue, so the console only accepts `stop`. Pick the map with **Legacy Map**.

## Ports

The egg's allocation block is `evrima_main, evrima_query, evrima_rcon, evrima_queue`.

- If the panel fills **Query/RCON/Queue Port** with a valid port that doesn't collide with the game port or another port, it is used.
- Otherwise (`0`, empty, invalid or colliding, e.g. the old egg's RCON and Queue both being `44000`), the port falls back to `SERVER_PORT +1 / +2 / +3`.

The resolved ports and where each came from are printed on every boot:

```
Ports: game=7777 query=7778(SERVER_PORT+1) rcon=7779(SERVER_PORT+2) queue=7780(SERVER_PORT+3)
```

`RconPort`, `QueuePort` and `QueryPort` (= game port, as before) are written into `Game.ini` on every start. Legacy binds the game port and the query port.

## Panel console = RCON (no external bot needed)

`bRconEnabled` is always forced on and the wrapper logs in to RCON locally. Anything typed in the panel console, or sent by a **Pterodactyl Schedule** "Send command" task, goes to the server:

```
announce Server restarts in 10 minutes!
dm 76561198000000000,Hello there
kick 76561198000000000,AFK
ban 76561198000000000,Cheating
players
save
wipecorpses
help                       <- full list
```

Arguments are **comma-separated**, as the game expects. Supported commands: `announce`, `directmessage` (`dm`), `serverdetails`, `wipecorpses`, `getplayables`, `updateplayables`, `togglemigrations`, `ban`, `kick`, `playerlist` (`players`), `save`, `pause`, `getplayerdata`, `togglewhitelist`, `addwhitelist`, `removewhitelist`, `toggleglobalchat`, `togglehumans`, `toggleai`, `disableaiclasses`, `aidensity`, `getqueuestatus`, `toggleailearning`, `togglegrowthmultiplier`, `setgrowthmultiplier`, `togglenetupdatedistancechecks`, `custom`.

Restart announcements, for example, are just schedule tasks: `announce Restart in 5 minutes` → wait → `announce Restart in 1 minute` → wait → power action *Restart*.

**Graceful stop:** the panel Stop button sends `^C`. The wrapper runs RCON `save`, waits for the confirmation (Spiro saves without replying; the wait is capped), then sends SIGINT, and SIGKILL after 60s.

**Protocol:** TCP, `0x01 <password> 0x00` → `Password Accepted`, then `0x02 <opcode> <args> 0x00` per command. The opcodes come from community reverse-engineering, since there is no official spec, and were verified against a live Evrima and Spiro server. A quiet `playerlist` keepalive (file log only) stops idle disconnects, and the client reconnects automatically.

## Migrating servers from the previous egg

Servers created with the old egg (yolks Wine image, `start-theisle.sh`) are migrated automatically on their first start with this image:

- The install at the server root is moved into `branches/<.current-branch>/`.
- Stashed `Game.ini.<branch>` files are handed to their own branches.
- `start-theisle.sh` and `branch-defaults/` are removed, and the old `.pteroignore` is upgraded.

Import the new egg, set the Docker image to `ghcr.io/nineralpha/the_isle:latest`, and restart.

## Logs

- `logs/game/<branch>-<date>.log`: the complete game output.
- `logs/wrapper/wrapper-<date>.log`: RCON connection, console commands, heartbeats.

Files older than 5 days are pruned on start.

## Building the image

```bash
cd docker/
docker build -t ghcr.io/nineralpha/the_isle:latest .
```

`.github/workflows/docker-build.yml` builds and pushes `latest` and `sha-<commit>` on changes to `docker/**` on `main`. `ci.yml` runs bash/ShellCheck/Node checks, egg validation and the tests in `tests/` on every PR. See [TESTING.md](TESTING.md).

# Testing

## Automated (CI, no network)

```bash
for t in tests/*_test.sh; do bash "$t"; done
for t in tests/*_test.js; do node "$t"; done
shellcheck --severity=warning docker/*.sh docker/sections/*.sh docker/helpers/*.sh install-script.sh tests/*.sh
```

| Test | Covers |
|---|---|
| `branches_test.sh` | Branch registry: Steam branch, platform, config dir, RCON, password flag, defaults present |
| `ports_test.sh` | Env ports used when valid; 0, invalid, colliding and old `44000` values fall back to offsets |
| `config_sync_test.sh` | Seeding, key replace/insert under the right section, special characters, CRLF, RCON forced on, Legacy schema, `ServerConfig` link |
| `branch_switch_test.sh` | Stub SteamCMD: fresh install validates, switch prunes but keeps `Saved`, failed switch keeps the marker, retries, beta password, Legacy uses the Windows depot |
| `migration_test.sh` | Old flat layout → `branches/<b>`, stashed configs restored, idempotent, `.pteroignore` upgrade |
| `rcon_test.js` | Packet encoding, console parsing, login/commands/serialization/timeouts against a fake TCP server |
| `wrapper_test.js` | Fake game + fake RCON: console → RCON, unknown commands, stop saves *before* SIGINT, Legacy console |

## Manual (real server, done for v1.0 in a local container)

Run the image with a volume on `/home/container` and `SERVER_PORT`, `GAME_BRANCH` and `RCON_PASSWORD` set:

1. **Evrima fresh install.** SteamCMD is installed, Evrima downloads, Gateway loads, and `[RCON] Connected` appears. `serverdetails`, `players`, `announce …` and `save` all reply.
2. **Stop** (`docker kill -s INT`): "Game saved", then a clean engine exit with code 0.
3. **Switch to Spiro.** Evrima is pruned to `TheIsle/Saved` and Isla Spiro boots. `announce` and `players` work; `serverdetails` and `save` don't reply on this build.
4. **Switch to Legacy.** The Windows depot and Steamworks DLLs install, Thenyaw Island loads under Wine, the console refuses RCON commands and `stop` works.
5. **Switch back to Evrima.** It re-downloads, and the user edits in `Game.ini` plus files in `Saved/` are intact.

On a panel, also check:

- the `done` line flips the server to Running;
- a schedule with `announce` works;
- a server made with the previous egg migrates on first start.

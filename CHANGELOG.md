# Changelog

## v1.0 - Custom image (replaces the yolks Wine multi-branch egg)

What changes for customers and support:

- **Switching branches is one variable + restart.** `evrima`, `spiro`, `hordetesting` (new) and `legacy` all run on one image (`ghcr.io/nineralpha/the_isle`), and nothing else needs changing.
- **Each branch has its own folder** (`branches/<branch>/`). Saves and `Game.ini` never mix between branches, and they are kept when switching away. Inactive branches' game files are deleted to save disk (`PRUNE_INACTIVE_BRANCHES=1`); set it to `0` for instant switching.
- **Ports are automatic.** RCON/Queue/Query ports come from the panel when valid, otherwise from the game port +1/+2/+3. They are printed on every boot. RCON and Queue no longer collide on `44000`.
- **The panel console speaks RCON.** `announce`, `kick`, `ban`, `players`, `save`, `dm` and the rest work from the console and from Pterodactyl schedules, so no Discord bot is needed for announcements. Type `help` in the console.
- **Stop saves first.** The Stop button saves the world over RCON before shutting down.
- **`ServerConfig` link** in the file manager always opens the running branch's config folder.
- **Hordetesting** needs the Beta Password from the developers; it is a private Steam branch.
- **Old servers migrate themselves** on first start: no reinstall, and configs/saves are kept.

Variable changes:

- New: `QUERY_PORT`, `BETA_PASSWORD`, `HORDETEST_BRANCH`, `PRUNE_INACTIVE_BRANCHES`, `EGG_DEBUG`.
- Removed: `RCON`, because RCON is now always on (the console needs it).
- `RCON_PORT` / `QUEUE_PORT` default to `0` (automatic).
- `GAME_BRANCH` also accepts `hordetesting`.

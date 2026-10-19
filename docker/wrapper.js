// The Isle server wrapper (PID 1 after entrypoint.sh execs it).
//  - spawns the game without a shell (argv assembled by sections/launch_args.sh)
//  - mirrors game output to the panel console and logs/
//  - bridges the panel console to Evrima RCON (announce, kick, playerlist, ...)
//  - graceful stop: RCON save, then SIGINT, then SIGKILL after a timeout

const fs = require("fs");
const path = require("path");
const readline = require("readline");
const { spawn, spawnSync } = require("child_process");
const rcon = require("./rcon.js");

const HOME = process.env.CONTAINER_HOME || "/home/container";
const LOG_ROOT = path.join(HOME, "logs");
const RCON_ENABLED = process.env.RCON_ENABLED === "1";
const SAVE_TIMEOUT_MS = 15000;   // wait this long for the RCON save reply
const KILL_TIMEOUT_MS = 60000;   // then this long for the game to exit
const XVFB_DISPLAY = ":99";

const args = process.argv.slice(2);
if (args.length < 1) {
    console.log("Error: no server command given.");
    process.exit(1);
}

// ── Logging ──────────────────────────────────────────────────────────
function stamp() {
    const d = new Date();
    const p = (n) => (n < 10 ? "0" : "") + n;
    return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate()) +
        "_T" + p(d.getHours()) + p(d.getMinutes());
}

function openLog(sub, prefix) {
    try {
        fs.mkdirSync(path.join(LOG_ROOT, sub), { recursive: true });
        const s = fs.createWriteStream(path.join(LOG_ROOT, sub, prefix + "-" + stamp() + ".log"), { flags: "a" });
        s.on("error", () => {});
        return s;
    } catch (e) {
        return null;
    }
}

const wrapperLogStream = openLog("wrapper", "wrapper");
const gameLogStream = openLog("game", (process.env.GAME_BRANCH_KEY || "game"));

function logFile(msg) {
    if (wrapperLogStream) wrapperLogStream.write("[" + new Date().toISOString() + "] " + msg + "\n");
}
function log(msg) {
    console.log(msg);
    logFile(msg);
}

// ── Xvfb (Legacy / Wine only) ────────────────────────────────────────
let xvfb = null;
const childEnv = Object.assign({}, process.env);
if (process.env.USE_XVFB === "1") {
    try {
        xvfb = spawn("Xvfb", [XVFB_DISPLAY, "-screen", "0", "640x480x24", "-nolisten", "tcp"], { stdio: "ignore" });
        xvfb.on("error", () => { xvfb = null; });
        childEnv.DISPLAY = XVFB_DISPLAY;
    } catch (e) {
        xvfb = null;
    }
}

// ── Game process ─────────────────────────────────────────────────────
log("Starting " + (process.env.GAME_BRANCH_LABEL || "The Isle") + "...");
const game = spawn(args[0], args.slice(1), {
    cwd: process.env.GAME_CWD || HOME,
    env: childEnv,
    stdio: ["ignore", "pipe", "pipe"],
});

function toConsole(data) { process.stdout.write(data); }
function toGameLog(data) { if (gameLogStream) gameLogStream.write(data); }

// Legacy (Windows UE4 under Wine) writes its real log to a file; tail that to
// the console. stdout from wine is kept in the game log only.
const tailFile = process.env.GAME_LOG_FILE || "";
if (tailFile) {
    game.stdout.on("data", toGameLog);
    game.stderr.on("data", toConsole);
    game.stderr.on("data", toGameLog);
    startTail(tailFile);
} else {
    game.stdout.on("data", toConsole);
    game.stderr.on("data", toConsole);
    game.stdout.on("data", toGameLog);
    game.stderr.on("data", toGameLog);
}

game.on("error", (err) => {
    log("Failed to start the server: " + err.message);
    finish(1);
});

let exited = false;
game.on("exit", (code, signal) => {
    exited = true;
    if (signal) log("Server process stopped by signal " + signal + ".");
    else if (code) log("Server process exited with code " + code + ".");
    else log("Server process exited.");
    // A stop we initiated is a clean exit even though the game reports
    // 130 (SIGINT) - don't let the panel treat it as a crash.
    finish(shuttingDown ? 0 : (code || (signal ? 1 : 0)));
});

function startTail(file) {
    let pos = 0;
    let ino = null;
    try {
        const st = fs.statSync(file);
        ino = st.ino;
        pos = st.size; // skip the previous run's log
    } catch (e) { /* not created yet */ }

    setInterval(() => {
        let st;
        try { st = fs.statSync(file); } catch (e) { return; }
        if (st.ino !== ino || st.size < pos) { ino = st.ino; pos = 0; }
        if (st.size <= pos) return;
        try {
            const fd = fs.openSync(file, "r");
            const buf = Buffer.alloc(st.size - pos);
            fs.readSync(fd, buf, 0, buf.length, pos);
            fs.closeSync(fd);
            pos = st.size;
            process.stdout.write(buf);
        } catch (e) { /* retry next tick */ }
    }, 1000).unref();
}

// ── RCON bridge ──────────────────────────────────────────────────────
let client = null;
if (RCON_ENABLED) {
    client = new rcon.RconClient({
        host: process.env.RCON_HOST || "127.0.0.1",
        port: parseInt(process.env.RCON_PORT, 10),
        password: process.env.RCON_PASSWORD || "",
        log: log,
        logFile: logFile,
        onReply: (text, tag) => {
            if (tag === "heartbeat") { logFile("[RCON] " + text); return; }
            log("[RCON] " + text);
        },
    });
    client.start();
}

const input = readline.createInterface({ input: process.stdin, terminal: false });
input.on("line", (line) => {
    const cmd = rcon.parseConsoleLine(line);
    if (cmd.type === "empty") return;

    const word = String(line).trim().toLowerCase();
    if (word === "stop" || word === "quit" || word === "exit") {
        shutdown("console '" + word + "'");
        return;
    }
    if (cmd.type === "help") {
        console.log(RCON_ENABLED ? rcon.helpText() :
            "RCON is not available on this branch. Console commands: stop");
        return;
    }
    if (!RCON_ENABLED) {
        console.log("RCON is not available on the " + (process.env.GAME_BRANCH_KEY || "current") +
            " branch - only 'stop' is supported.");
        return;
    }
    if (cmd.type === "unknown") {
        console.log("Unknown command '" + cmd.name + "'. Type 'help' for the list of RCON commands.");
        return;
    }
    if (!client.ready) {
        console.log("RCON is not connected yet - wait for the server to finish starting.");
        return;
    }
    logFile("[Console] " + cmd.name + (cmd.args ? " " + cmd.args : ""));
    client.send(cmd.code, cmd.args, "user").then((reply) => {
        if (reply === null) console.log("[RCON] No reply to '" + cmd.name + "'.");
        else if (reply === "") console.log("[RCON] '" + cmd.name + "' sent.");
    });
});

// ── Shutdown ─────────────────────────────────────────────────────────
let shuttingDown = false;

function shutdown(reason) {
    if (shuttingDown || exited) return;
    shuttingDown = true;
    log("Stopping the server (" + reason + ")...");

    const stopGame = () => {
        if (exited) return;
        if (client) client.stop(); // no "connection lost" noise while stopping
        game.kill("SIGINT");
        setTimeout(() => {
            if (!exited) {
                log("Server did not exit in time - forcing it to stop.");
                game.kill("SIGKILL");
            }
        }, KILL_TIMEOUT_MS).unref();
    };

    if (client && client.ready) {
        log("Saving the world over RCON before shutdown...");
        const timer = setTimeout(() => {
            log("Save requested (no confirmation received) - stopping.");
            stopGame();
        }, SAVE_TIMEOUT_MS);
        client.send(rcon.COMMANDS.save.code, "", "save").then((reply) => {
            clearTimeout(timer);
            // Older builds (Spiro) save without replying.
            log(reply !== null ? "Save complete." : "Save requested (no confirmation received) - stopping.");
            stopGame();
        });
    } else {
        stopGame();
    }
}

process.on("SIGINT", () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));

let finished = false;
function finish(code) {
    if (finished) return;
    finished = true;
    if (client) client.stop();
    if (xvfb) { try { xvfb.kill("SIGTERM"); } catch (e) { /* gone */ } }
    if (process.env.USE_XVFB === "1") {
        try { spawnSync("wineserver", ["-k"], { stdio: "ignore", timeout: 10000 }); } catch (e) { /* no wine */ }
    }
    const done = () => process.exit(code);
    let pending = 0;
    [wrapperLogStream, gameLogStream].forEach((s) => {
        if (s) { pending++; s.end(() => { if (--pending === 0) done(); }); }
    });
    if (pending === 0) done();
    setTimeout(done, 2000).unref();
}

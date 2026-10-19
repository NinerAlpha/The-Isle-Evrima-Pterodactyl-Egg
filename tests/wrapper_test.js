// End-to-end test for docker/wrapper.js with a fake game process and a fake
// RCON server: console -> RCON bridging, graceful stop (save, then SIGINT),
// and the no-RCON (Legacy) console behaviour.
const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");
const { startFakeServer } = require("./fake_rcon_server.js");

const WRAPPER = path.join(__dirname, "..", "docker", "wrapper.js");
const home = fs.mkdtempSync(path.join(os.tmpdir(), "isle-wrapper-"));
const fakeGame = path.join(home, "fake_game.js");
fs.writeFileSync(fakeGame, [
    'console.log("LogInit: Game Engine Initialized");',
    'process.on("SIGINT", () => { console.log("FAKE GAME: got SIGINT"); setTimeout(() => process.exit(0), 50); });',
    'setInterval(() => {}, 1000);',
].join("\n"));

let failed = 0;
async function test(name, fn) {
    try { await fn(); console.log("PASS: " + name); }
    catch (e) { failed = 1; console.log("FAIL: " + name + " - " + e.message); }
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function waitFor(fn, ms) {
    for (let t = 0; t < ms; t += 25) { if (fn()) return true; await sleep(25); }
    return false;
}

function runWrapper(env) {
    const p = spawn(process.execPath, [WRAPPER, process.execPath, fakeGame], {
        env: Object.assign({}, process.env, { CONTAINER_HOME: home, GAME_CWD: home, GAME_BRANCH_KEY: "evrima" }, env),
    });
    p.out = "";
    p.stdout.on("data", (d) => { p.out += d; });
    p.stderr.on("data", (d) => { p.out += d; });
    p.exitCode_ = null;
    p.on("exit", (c) => { p.exitCode_ = c; });
    return p;
}

(async () => {
    const fake = await startFakeServer("pw", (code, args) => (code === 0x50 ? "Saved" : "ok " + args));

    await test("console commands are bridged to RCON; stop saves first", async () => {
        const w = runWrapper({ RCON_ENABLED: "1", RCON_PORT: String(fake.port), RCON_PASSWORD: "pw" });
        assert.ok(await waitFor(() => w.out.includes("Game Engine Initialized"), 5000), "game output not mirrored");
        assert.ok(await waitFor(() => w.out.includes("[RCON] Connected"), 5000), "RCON never connected:\n" + w.out);

        w.stdin.write("announce Restart in 5, hold on\n");
        assert.ok(await waitFor(() => w.out.includes("[RCON] ok Restart in 5, hold on"), 3000), "no announce reply:\n" + w.out);
        const ann = fake.received.find((p) => p[0] === 0x02 && p[1] === 0x10);
        assert.strictEqual(ann.subarray(2).toString(), "Restart in 5, hold on");

        w.stdin.write("teleport me\n");
        assert.ok(await waitFor(() => w.out.includes("Unknown command 'teleport'"), 2000));

        w.kill("SIGINT");
        assert.ok(await waitFor(() => w.exitCode_ !== null, 8000), "wrapper did not exit:\n" + w.out);
        assert.strictEqual(w.exitCode_, 0);
        const saveIdx = w.out.indexOf("Save complete");
        const sigIdx = w.out.indexOf("FAKE GAME: got SIGINT");
        assert.ok(saveIdx !== -1 && sigIdx > saveIdx, "save must happen before SIGINT:\n" + w.out);
        assert.ok(fake.received.some((p) => p[0] === 0x02 && p[1] === 0x50), "save packet not sent");
    });

    await test("no-RCON branch: commands refused, 'stop' still works", async () => {
        const w = runWrapper({ RCON_ENABLED: "0", GAME_BRANCH_KEY: "legacy" });
        assert.ok(await waitFor(() => w.out.includes("Game Engine Initialized"), 5000));
        w.stdin.write("announce hi\n");
        assert.ok(await waitFor(() => w.out.includes("RCON is not available on the legacy branch"), 2000), w.out);
        w.stdin.write("stop\n");
        assert.ok(await waitFor(() => w.exitCode_ !== null, 8000), "wrapper did not exit:\n" + w.out);
        assert.ok(w.out.includes("FAKE GAME: got SIGINT"));
    });

    await test("logs are written under logs/", () => {
        const wrapperLogs = fs.readdirSync(path.join(home, "logs", "wrapper"));
        const gameLogs = fs.readdirSync(path.join(home, "logs", "game"));
        assert.ok(wrapperLogs.length > 0 && gameLogs.length > 0);
        const gl = gameLogs.map((f) => fs.readFileSync(path.join(home, "logs", "game", f), "utf8")).join("");
        assert.ok(gl.includes("Game Engine Initialized"));
    });

    fake.server.close();
    fs.rmSync(home, { recursive: true, force: true });
    console.log(failed ? "Some tests failed." : "All tests passed.");
    process.exit(failed);
})();

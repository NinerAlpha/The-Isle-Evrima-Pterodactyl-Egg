// Unit tests for docker/rcon.js: packet encoding, console parsing and the
// client against a fake TCP server.
const assert = require("assert");
const path = require("path");
const rcon = require(path.join(__dirname, "..", "docker", "rcon.js"));
const { startFakeServer } = require("./fake_rcon_server.js");

let failed = 0;
async function test(name, fn) {
    try { await fn(); console.log("PASS: " + name); }
    catch (e) { failed = 1; console.log("FAIL: " + name + " - " + e.message); }
}

(async () => {
    await test("auth packet", () => {
        assert.deepStrictEqual([...rcon.authPacket("pw")], [0x01, 0x70, 0x77, 0x00]);
    });
    await test("command packet", () => {
        assert.deepStrictEqual([...rcon.commandPacket(0x10, "Hi")], [0x02, 0x10, 0x48, 0x69, 0x00]);
        assert.deepStrictEqual([...rcon.commandPacket(0x40, "")], [0x02, 0x40, 0x00]);
    });
    await test("known opcodes", () => {
        assert.strictEqual(rcon.COMMANDS.announce.code, 0x10);
        assert.strictEqual(rcon.COMMANDS.directmessage.code, 0x11);
        assert.strictEqual(rcon.COMMANDS.kick.code, 0x30);
        assert.strictEqual(rcon.COMMANDS.playerlist.code, 0x40);
        assert.strictEqual(rcon.COMMANDS.save.code, 0x50);
        const codes = Object.values(rcon.COMMANDS).map((c) => c.code);
        assert.strictEqual(new Set(codes).size, codes.length, "duplicate opcode");
    });
    await test("parse: command with args keeps spacing and commas", () => {
        const c = rcon.parseConsoleLine("Announce  Restart in 5 minutes, be ready\n");
        assert.strictEqual(c.type, "command");
        assert.strictEqual(c.name, "announce");
        assert.strictEqual(c.args, "Restart in 5 minutes, be ready");
    });
    await test("parse: aliases", () => {
        assert.strictEqual(rcon.parseConsoleLine("players").name, "playerlist");
        assert.strictEqual(rcon.parseConsoleLine("dm 7656,hi").code, 0x11);
    });
    await test("parse: help / empty / unknown", () => {
        assert.strictEqual(rcon.parseConsoleLine("help").type, "help");
        assert.strictEqual(rcon.parseConsoleLine("   ").type, "empty");
        assert.deepStrictEqual(rcon.parseConsoleLine("rm -rf"), { type: "unknown", name: "rm" });
    });
    await test("help lists every command", () => {
        const h = rcon.helpText();
        Object.keys(rcon.COMMANDS).forEach((n) => assert.ok(h.includes(n), n));
    });
    await test("cleanResponse strips control bytes", () => {
        assert.strictEqual(rcon.cleanResponse(Buffer.from("\x02\x40PlayerList\n1,2\x00")), "@PlayerList\n1,2");
    });

    await test("client: login, command, reply", async () => {
        const fake = await startFakeServer("secret", (code, args) =>
            code === 0x40 ? "PlayerList\n76561,\nBob," : "Announced: " + args);
        const logs = [];
        const c = new rcon.RconClient({ port: fake.port, password: "secret", log: (m) => logs.push(m), heartbeatInterval: 0 });
        c.start();
        for (let i = 0; i < 50 && !c.ready; i++) await new Promise((r) => setTimeout(r, 20));
        assert.ok(c.ready, "not authenticated");
        assert.ok(logs.some((l) => l.includes("Connected")));
        assert.strictEqual(await c.send(0x10, "hello world"), "Announced: hello world");
        assert.strictEqual(await c.send(0x40, ""), "PlayerList\n76561,\nBob,");
        assert.deepStrictEqual([...fake.received[1]], [0x02, 0x10, ...Buffer.from("hello world")]);
        c.stop();
        fake.server.close();
    });

    await test("client: requests are serialized", async () => {
        const fake = await startFakeServer("pw", (code, args) => "r:" + args);
        const c = new rcon.RconClient({ port: fake.port, password: "pw", heartbeatInterval: 0 });
        c.start();
        for (let i = 0; i < 50 && !c.ready; i++) await new Promise((r) => setTimeout(r, 20));
        const replies = await Promise.all([c.send(0x10, "a"), c.send(0x10, "b"), c.send(0x10, "c")]);
        assert.deepStrictEqual(replies, ["r:a", "r:b", "r:c"]);
        c.stop();
        fake.server.close();
    });

    await test("client: wrong password is reported, never ready", async () => {
        const fake = await startFakeServer("right");
        const logs = [];
        const c = new rcon.RconClient({ port: fake.port, password: "wrong", log: (m) => logs.push(m), heartbeatInterval: 0 });
        c.start();
        await new Promise((r) => setTimeout(r, 300));
        assert.ok(!c.ready);
        assert.ok(logs.some((l) => l.includes("rejected")), logs.join("|"));
        c.stop();
        fake.server.close();
    });

    await test("client: command timeout resolves null", async () => {
        const fake = await startFakeServer("pw", () => null);
        const c = new rcon.RconClient({ port: fake.port, password: "pw", heartbeatInterval: 0, commandTimeout: 100 });
        c.start();
        for (let i = 0; i < 50 && !c.ready; i++) await new Promise((r) => setTimeout(r, 20));
        assert.strictEqual(await c.send(0x50, ""), null);
        c.stop();
        fake.server.close();
    });

    await test("client: send while disconnected resolves null", async () => {
        const c = new rcon.RconClient({ port: 1, password: "pw", heartbeatInterval: 0 });
        assert.strictEqual(await c.send(0x50, ""), null);
    });

    console.log(failed ? "Some tests failed." : "All tests passed.");
    process.exit(failed);
})();

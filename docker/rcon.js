// Evrima RCON: protocol encoding, console command table and a reconnecting
// TCP client. No third-party dependencies (Node's built-in "net" only).
//
// Wire format (community-documented, no official spec):
//   login   : 0x01 <password> 0x00          -> reply contains "Password Accepted"
//   command : 0x02 <opcode> <args> 0x00     -> plain-text reply
// Arguments are COMMA-separated, exactly as the game expects them, e.g.
//   directmessage 76561198000000000,Hello there
//   kick 76561198000000000,Reason

const net = require("net");

const AUTH_PREFIX = 0x01;
const COMMAND_PREFIX = 0x02;
const TERMINATOR = 0x00;
const AUTH_SUCCESS = "Password Accepted";
const ENCODING = "latin1";

// Console name -> { code, args, help }. Names follow the in-game RCON names.
const COMMANDS = {
    announce:                      { code: 0x10, args: "<message>",          help: "Server-wide announcement" },
    directmessage:                 { code: 0x11, args: "<steamid>,<message>", help: "Message one player" },
    serverdetails:                 { code: 0x12, args: "",                   help: "Server information" },
    wipecorpses:                   { code: 0x13, args: "",                   help: "Remove all corpses" },
    getplayables:                  { code: 0x14, args: "",                   help: "List playable classes" },
    updateplayables:               { code: 0x15, args: "<class:enabled,...>", help: "Update playable classes" },
    togglemigrations:              { code: 0x19, args: "<1|0>",              help: "Toggle migrations" },
    ban:                           { code: 0x20, args: "<steamid>,<reason>[,...]", help: "Ban a player" },
    togglegrowthmultiplier:        { code: 0x21, args: "<1|0>",              help: "Toggle growth multiplier" },
    setgrowthmultiplier:           { code: 0x22, args: "<value>",            help: "Set growth multiplier" },
    togglenetupdatedistancechecks: { code: 0x23, args: "<1|0>",              help: "Toggle net update distance checks" },
    kick:                          { code: 0x30, args: "<steamid>,<reason>", help: "Kick a player" },
    playerlist:                    { code: 0x40, args: "",                   help: "List online players" },
    save:                          { code: 0x50, args: "",                   help: "Save the world" },
    pause:                         { code: 0x60, args: "<1|0>",              help: "Pause / unpause the server" },
    custom:                        { code: 0x70, args: "<text>",             help: "Custom command" },
    getplayerdata:                 { code: 0x77, args: "[steamid]",          help: "Detailed player data" },
    togglewhitelist:               { code: 0x81, args: "<1|0>",              help: "Toggle whitelist" },
    addwhitelist:                  { code: 0x82, args: "<steamid>",          help: "Add to whitelist" },
    removewhitelist:               { code: 0x83, args: "<steamid>",          help: "Remove from whitelist" },
    toggleglobalchat:              { code: 0x84, args: "<1|0>",              help: "Toggle global chat" },
    togglehumans:                  { code: 0x86, args: "<1|0>",              help: "Toggle humans" },
    toggleai:                      { code: 0x90, args: "<1|0>",              help: "Toggle AI spawning" },
    disableaiclasses:              { code: 0x91, args: "<class,class,...>",  help: "Disable AI classes" },
    aidensity:                     { code: 0x92, args: "<0.0-1.0>",          help: "Set AI density" },
    getqueuestatus:                { code: 0x93, args: "",                   help: "Queue status" },
    toggleailearning:              { code: 0x94, args: "<1|0>",              help: "Toggle AI learning" },
};

const ALIASES = {
    players: "playerlist",
    dm: "directmessage",
    msg: "directmessage",
    details: "serverdetails",
    queue: "getqueuestatus",
};

function authPacket(password) {
    return Buffer.concat([
        Buffer.from([AUTH_PREFIX]),
        Buffer.from(String(password), ENCODING),
        Buffer.from([TERMINATOR]),
    ]);
}

function commandPacket(code, args) {
    return Buffer.concat([
        Buffer.from([COMMAND_PREFIX, code]),
        Buffer.from(args || "", ENCODING),
        Buffer.from([TERMINATOR]),
    ]);
}

// Parses one console line. Returns one of:
//   { type: "empty" } | { type: "help" } | { type: "unknown", name }
//   { type: "command", name, code, args }
function parseConsoleLine(line) {
    const text = String(line || "").replace(/[\r\n]+$/, "").trim();
    if (!text) return { type: "empty" };

    const space = text.search(/\s/);
    let name = (space === -1 ? text : text.slice(0, space)).toLowerCase();
    const args = space === -1 ? "" : text.slice(space + 1).trim();

    if (name === "help" || name === "?") return { type: "help" };
    if (ALIASES[name]) name = ALIASES[name];
    const def = COMMANDS[name];
    if (!def) return { type: "unknown", name };
    return { type: "command", name, code: def.code, args };
}

function helpText() {
    const lines = ["Available RCON commands (arguments are comma-separated):"];
    Object.keys(COMMANDS).forEach(function (name) {
        const d = COMMANDS[name];
        lines.push("  " + (name + " " + d.args).trim().padEnd(48) + d.help);
    });
    lines.push("Aliases: " + Object.keys(ALIASES).map(function (a) { return a + "=" + ALIASES[a]; }).join(", "));
    return lines.join("\n");
}

// Strips the framing / control bytes the server leaves in replies.
function cleanResponse(buf) {
    return Buffer.from(buf).toString(ENCODING)
        .replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, "")
        .trim();
}

// Reconnecting RCON client.
//   opts: { host, port, password, log(msg), logFile(msg), onReply(text, tag),
//           retryDelay, heartbeatInterval, commandTimeout }
// Requests are serialized: the reply to the oldest outstanding request is the
// next chunk the server sends (the protocol has no request ids).
class RconClient {
    constructor(opts) {
        this.opts = Object.assign({
            host: "127.0.0.1",
            retryDelay: 10000,
            heartbeatInterval: 120000,
            commandTimeout: 10000,
            log: function () {},
            logFile: function () {},
            onReply: function () {},
        }, opts);
        this.socket = null;
        this.authed = false;
        this.stopped = false;
        this.queue = [];      // pending { packet, tag, resolve, timer }
        this.inflight = null; // request awaiting a reply
        this.heartbeat = null;
        this.retryTimer = null;
        this.everConnected = false;
        this.rejected = false;
    }

    get ready() { return this.authed && this.socket && !this.socket.destroyed; }

    start() {
        this.stopped = false;
        this._connect();
    }

    stop() {
        this.stopped = true;
        clearTimeout(this.retryTimer);
        this._teardown();
    }

    // Queue a command. Resolves with the reply text, or null on timeout /
    // disconnect. tag is passed to onReply ("user", "heartbeat", "save", ...).
    send(code, args, tag) {
        const self = this;
        return new Promise(function (resolve) {
            if (!self.ready) { resolve(null); return; }
            self.queue.push({ packet: commandPacket(code, args), tag: tag || "user", resolve: resolve });
            self._pump();
        });
    }

    _pump() {
        if (this.inflight || !this.ready || this.queue.length === 0) return;
        const req = this.queue.shift();
        this.inflight = req;
        const self = this;
        req.timer = setTimeout(function () {
            if (self.inflight === req) {
                self.inflight = null;
                req.resolve(null);
                self._pump();
            }
        }, this.opts.commandTimeout);
        this.socket.write(req.packet);
    }

    _connect() {
        if (this.stopped) return;
        const o = this.opts;
        const sock = new net.Socket();
        this.socket = sock;
        this.authed = false;
        let authBuf = "";
        const self = this;

        sock.setKeepAlive(true, 30000);
        sock.on("connect", function () {
            sock.write(authPacket(o.password));
        });
        sock.on("data", function (data) {
            if (!self.authed) {
                authBuf += Buffer.from(data).toString(ENCODING);
                if (authBuf.indexOf(AUTH_SUCCESS) !== -1) {
                    self.authed = true;
                    o.log(self.everConnected ? "[RCON] Reconnected." :
                        "[RCON] Connected - console commands are now sent to the server over RCON. Type 'help' for the list.");
                    self.everConnected = true;
                    self._startHeartbeat();
                    self._pump();
                } else if (/reject|invalid|denied|wrong/i.test(authBuf)) {
                    o.log("[RCON] Password rejected by the server - check the RCON Password variable.");
                    self.rejected = true;
                    sock.destroy();
                }
                return;
            }
            const text = cleanResponse(data);
            const req = self.inflight;
            if (req) {
                clearTimeout(req.timer);
                self.inflight = null;
                req.resolve(text);
                if (text) o.onReply(text, req.tag);
                self._pump();
            } else if (text) {
                o.onReply(text, "unsolicited");
            }
        });
        sock.on("error", function (err) {
            o.logFile("[RCON] socket error: " + err.message);
        });
        sock.on("close", function () {
            const wasAuthed = self.authed;
            self._teardown();
            if (self.stopped) return;
            if (wasAuthed) o.log("[RCON] Connection lost, reconnecting...");
            // Back off harder after a rejected password so the console isn't spammed.
            const delay = self.rejected ? Math.max(o.retryDelay, 60000) : o.retryDelay;
            self.rejected = false;
            self.retryTimer = setTimeout(function () { self._connect(); }, delay);
        });
        sock.connect(o.port, o.host);
    }

    _startHeartbeat() {
        clearInterval(this.heartbeat);
        if (!(this.opts.heartbeatInterval > 0)) return;
        const self = this;
        this.heartbeat = setInterval(function () {
            // playerlist is cheap, answered by every Evrima-based build (Spiro
            // does not answer serverdetails) and keeps idle connections open.
            self.send(COMMANDS.playerlist.code, "", "heartbeat").then(function (r) {
                self.opts.logFile(r === null ? "[RCON] heartbeat: no reply" : "[RCON] heartbeat OK");
            });
        }, this.opts.heartbeatInterval);
    }

    _teardown() {
        clearInterval(this.heartbeat);
        this.heartbeat = null;
        this.authed = false;
        if (this.inflight) {
            clearTimeout(this.inflight.timer);
            this.inflight.resolve(null);
            this.inflight = null;
        }
        this.queue.splice(0).forEach(function (r) { r.resolve(null); });
        if (this.socket) {
            this.socket.removeAllListeners("data");
            if (!this.socket.destroyed) this.socket.destroy();
        }
    }
}

module.exports = {
    COMMANDS,
    ALIASES,
    AUTH_SUCCESS,
    authPacket,
    commandPacket,
    parseConsoleLine,
    helpText,
    cleanResponse,
    RconClient,
};

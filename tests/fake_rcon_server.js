// Minimal fake Evrima RCON server for tests. Records every packet it receives
// and answers like the game: "Password Accepted" on a good login, a text reply
// per command.
const net = require("net");

function startFakeServer(password, onPacket) {
    return new Promise((resolve) => {
        const received = [];
        const server = net.createServer((sock) => {
            let authed = false;
            let buf = Buffer.alloc(0);
            sock.on("data", (d) => {
                buf = Buffer.concat([buf, d]);
                let i;
                while ((i = buf.indexOf(0x00)) !== -1) {
                    const pkt = buf.subarray(0, i);
                    buf = buf.subarray(i + 1);
                    received.push(Buffer.from(pkt));
                    if (pkt[0] === 0x01) {
                        authed = pkt.subarray(1).toString("latin1") === password;
                        sock.write(authed ? "Password Accepted\x00" : "Password Rejected\x00");
                        if (!authed) sock.end();
                    } else if (pkt[0] === 0x02 && authed) {
                        const reply = onPacket ? onPacket(pkt[1], pkt.subarray(2).toString("latin1")) : "OK";
                        if (reply !== null) sock.write(reply + "\x00");
                    }
                }
            });
            sock.on("error", () => {});
        });
        server.listen(0, "127.0.0.1", () => resolve({ server, port: server.address().port, received }));
    });
}

module.exports = { startFakeServer };

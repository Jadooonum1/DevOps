// Plain Node.js HTTP server - no framework needed for a hello world.
const http = require("http");
const os = require("os");

const PORT = process.env.PORT || 3000;

const server = http.createServer((req, res) => {
  if (req.url === "/health") {
    res.writeHead(200, { "Content-Type": "text/plain" });
    return res.end("ok\n");
  }
  res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
  res.end(
    `<h1>Hello World from the Bookshelf (Node.js ${process.version})</h1>` +
      `<p>Served by container ${os.hostname()}</p>\n`
  );
});

server.listen(PORT, () => console.log(`node-hello listening on ${PORT}`));

// A Node server with the same routes as examples/hello/main.bend, for comparison.
import http from "node:http";

const port = Number(process.argv[2] ?? 8081);
http.createServer((req, res) => {
  const url = new URL(req.url, "http://x");
  const close = {};
  let chunks = [];
  req.on("data", (c) => chunks.push(c));
  req.on("end", () => {
    const m = url.pathname.match(/^\/hello\/([^/]+)$/);
    if (req.method === "GET" && url.pathname === "/") {
      res.writeHead(200, { ...close, "content-type": "text/html; charset=utf-8" }).end("<h1>Hello from Node</h1>");
    } else if (req.method === "GET" && m) {
      res.writeHead(200, { ...close, "content-type": "text/plain; charset=utf-8" }).end(`Olá, ${m[1]}!`);
    } else if (req.method === "POST" && url.pathname === "/echo") {
      res.writeHead(200, { ...close, "content-type": "text/plain; charset=utf-8" }).end(Buffer.concat(chunks));
    } else {
      res.writeHead(404, close).end("Not Found");
    }
  });
}).listen(port, () => console.log(`node: listening on http://localhost:${port}`));

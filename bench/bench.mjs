// Load generator for Air. No dependencies.
//
//   node bench/bench.mjs [--url http://localhost:8080/] [--conns 64] [--seconds 10] [--method GET] [--body TEXT] [--close] [--json]
//
// Opens `conns` clients that each fire requests back to back for `seconds`,
// then prints throughput, latency percentiles and errors. Connections are
// kept alive and reused; `--close` opens one per request instead. `--json`
// prints one JSON object instead of the text, for scripts.

import http from "node:http";
import { performance } from "node:perf_hooks";

const args = Object.fromEntries(
  process.argv.slice(2).map((a, i, xs) => (a.startsWith("--") ? [a.slice(2), xs[i + 1]] : [])).filter((x) => x.length)
);
const url = new URL(args.url ?? "http://localhost:8080/");
const conns = Number(args.conns ?? 64);
const seconds = Number(args.seconds ?? 10);
const method = (args.method ?? "GET").toUpperCase();
const body = args.body ?? null;
const close = process.argv.includes("--close");
const json = process.argv.includes("--json");

const agent = new http.Agent({ keepAlive: !close, maxSockets: close ? Infinity : conns });

const latencies = [];
const statuses = new Map();
let errors = 0;
const errorKinds = new Map();
let bytes = 0;

function once() {
  return new Promise((resolve) => {
    const t0 = performance.now();
    const req = http.request(
      { hostname: url.hostname, port: url.port, path: url.pathname + url.search, method, agent,
        headers: { ...(close ? { connection: "close" } : {}),
                   ...(body ? { "content-type": "text/plain", "content-length": Buffer.byteLength(body) } : {}) } },
      (res) => {
        res.on("data", (c) => (bytes += c.length));
        res.on("end", () => {
          latencies.push(performance.now() - t0);
          statuses.set(res.statusCode, (statuses.get(res.statusCode) ?? 0) + 1);
          resolve();
        });
      }
    );
    req.on("error", (e) => { errors++; errorKinds.set(e.code ?? e.message, (errorKinds.get(e.code ?? e.message) ?? 0) + 1); resolve(); });
    if (body) req.write(body);
    req.end();
  });
}

async function worker(deadline) {
  while (performance.now() < deadline) await once();
}

function pct(sorted, p) {
  return sorted[Math.min(sorted.length - 1, Math.floor((p / 100) * sorted.length))];
}

const start = performance.now();
await Promise.all(Array.from({ length: conns }, () => worker(start + seconds * 1000)));
const elapsed = (performance.now() - start) / 1000;

latencies.sort((a, b) => a - b);
const total = latencies.length;
if (json) {
  console.log(JSON.stringify({
    target: `${method} ${url.pathname}`,
    rps: Number((total / elapsed).toFixed(1)),
    requests: total,
    errors,
    p50: total ? Number(pct(latencies, 50).toFixed(3)) : null,
    p99: total ? Number(pct(latencies, 99).toFixed(3)) : null,
    statuses: Object.fromEntries(statuses),
  }));
  process.exit(0);
}
console.log(`target      ${method} ${url}`);
console.log(`connections ${conns}   duration ${elapsed.toFixed(1)}s`);
console.log(`requests    ${total}   errors ${errors}`);
console.log(`throughput  ${(total / elapsed).toFixed(0)} req/s   ${(bytes / elapsed / 1024).toFixed(0)} KB/s`);
if (total) {
  const mean = latencies.reduce((a, b) => a + b, 0) / total;
  console.log(`latency ms  mean ${mean.toFixed(2)}  p50 ${pct(latencies, 50).toFixed(2)}  p90 ${pct(latencies, 90).toFixed(2)}  p99 ${pct(latencies, 99).toFixed(2)}  max ${latencies[total - 1].toFixed(2)}`);
}
console.log(`statuses    ${[...statuses].map(([k, v]) => `${k}:${v}`).join(" ") || "-"}`);
if (errors) console.log(`error kinds ${[...errorKinds].map(([k, v]) => `${k}:${v}`).join(" ")}`);

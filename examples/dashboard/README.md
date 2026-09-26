# dashboard

An HTML page with JavaScript and Tailwind, served by Air, talking to JSON
routes on the same server.

```
cd examples/dashboard && bend main.bend    # or: bend examples/dashboard/main.bend
open http://localhost:8080
```

- `main.bend` serves `app.bend`, the app: it serves `public/` through `Air.static` on one
  wildcard route, and answers `/api/stats`, `/api/tasks`, `/api/hello/:name`
  and `POST /api/echo` with JSON built as values. `POST /api/shutdown` flips the
  stop switch: the server stops accepting, lets the requests in flight
  finish, and the process exits. It runs under `Air.serve_until` with the
  default timeouts. Every request is counted by `Air.metrics` (read them at
  `/metrics`) and traced by `Air.trace`, which prints one span per request
  and puts the trace id in the log line; `/trace` shows the ids a handler
  sees. `tests/dashboard.bend` runs the app without a socket.
- `public/index.html`: the page. Tailwind comes from the CDN build
  (`@tailwindcss/browser`), so there is no build step.
- `public/app.js`: fetches the routes, renders stat cards and the task list,
  and logs each request's status and latency.


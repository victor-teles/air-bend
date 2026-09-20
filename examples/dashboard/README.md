# dashboard

An HTML page with JavaScript and Tailwind, served by Air, talking to JSON
routes on the same server.

```
cd examples/dashboard && bend main.bend    # or: bend examples/dashboard/main.bend
open http://localhost:8080
```

- `main.bend`: the server. Reads `public/` files from disk with `File.open`
  and `File.read`, and answers `/api/stats`, `/api/tasks`, `/api/hello/:name`
  and `POST /api/echo` with hand-built JSON. `POST /api/shutdown` flips the
  stop switch: the server stops accepting, lets the requests in flight
  finish, and the process exits. It runs under `Air.serve_until` with the
  default timeouts.
- `public/index.html`: the page. Tailwind comes from the CDN build
  (`@tailwindcss/browser`), so there is no build step.
- `public/app.js`: fetches the routes, renders stat cards and the task list,
  and logs each request's status and latency.

Air has no static-file middleware yet, so each file is its own route.

<p align="center">
  <img src="docs/public/banner.png" alt="Air Bend" width="640">
</p>

# Air

A web framework for [Bend](https://bend-lang.com).

```python
import Base
import ./air.bend as Air

def greet(req: Air.Request()) -> IO(Air.Response()):
  IO.pure(Air.Response(), Air.Response.text("hi " ++ Air.Request.param(req, "name")))

def routes() -> List<Air.Route()>:
  [Air.Route.get("/hello/:name", greet)]

def app(req: Air.Request()) -> IO(Air.Response()):
  Air.dispatch(routes(), req)

def main() -> IO(Unit):
  Air.serve(~app, 8080)
```

```
bend examples/hello/main.bend
curl localhost:8080/hello/world
```

## Documentation

The guides live in `docs/`, a Next.js + Fumadocs site:

```
cd docs && pnpm install && pnpm dev
```

Then open http://localhost:3000/docs. Pages are MDX under
`docs/content/docs/`: middleware, request ids and logging, shared state,
sessions, rate limiting, validation, templates, static files, CORS and
security headers, errors, and what Air does not do yet.

## Checks

`bend PROOF.bend` proves the laws in `LAWS.bend`. It must print
"All terms check." before a commit.

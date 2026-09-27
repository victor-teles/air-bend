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

To run the starter example from the repository root:

```bash
bend examples/hello/main.bend
curl localhost:8080/hello/world
```

## Documentation

The documentation site is in `docs/`. To read it locally:

```bash
cd docs
pnpm install
pnpm dev
```

Then open http://localhost:3000/docs. To learn Air, start with the
tutorial, [Build your first Air app](docs/content/docs/tutorial/first-app.mdx).

## Checks

Run these checks from the repository root before you commit:

- `bend PROOF.bend` proves the laws in `LAWS.bend`. It must print
  `All terms check.`
- `bend tests/hello.bend` and `bend tests/dashboard.bend` run the example
  apps in-process. Each exits with code 1 when an assertion fails.

import Base
import ../../air.bend as Air
import ./app.bend as Hello

# Checks the routes, then serves the app in `app.bend` on `PORT`, or
# 8080. Limits, timeouts and a `.env` file come from the environment too.
def main() -> IO(Unit):
  do IO<Unit>:
    Air.Route.check(Hello.routes())
    Air.serve_env(~Hello.app, 8080)

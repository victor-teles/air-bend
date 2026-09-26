import Base
import ../../air.bend as Air
import ./app.bend as Dashboard

# dashboard
# =========
#
# Serves the app in `app.bend`; see there for what it does. Run it from
# this folder or from the repo root:
#
#   cd examples/dashboard && bend main.bend
#   bend examples/dashboard/main.bend
#
# and open http://localhost:8080 (or `PORT`).

# The switch is a channel, so it can be shared: once with the route
# check, once with the server.
def serve(+switch: Air.Switch()) -> IO(Unit):
  do IO<Unit>:
    Air.Route.check(Dashboard.routes(switch))
    Air.serve_env_until(~Dashboard.app, switch, 8080)
    Air.exit(0)

def main() -> IO(Unit):
  do IO<Unit>:
    switch : Air.Switch() <- Air.Switch.new()
    serve(switch)

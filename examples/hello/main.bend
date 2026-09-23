import Base
import ../../air.bend as Air
import ./app.bend as Hello

# Checks the routes, then serves the app in `app.bend` on port 8080.
def main() -> IO(Unit):
  do IO<Unit>:
    Air.Route.check(Hello.routes())
    Air.serve(~Hello.app, 8080)

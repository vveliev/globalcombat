# Global Combat
....is a Risk like web based game in which turns are taken simultaneously. Since it is played over the internet, actions are hidden from your enemies until the turn runs.

GLOBAL COMBAT has a WW1 era motif and contains a Elo based rating system which rewards players depending on their place in the game, not just whether they win or lose.

This leads to the political side to GLOBAL COMBAT, in which you must sometimes forge alliances in order to survive, fighting not just to win, but for your honor...

https://globalcombat.com

# Project Status
Global Combat was originally launched on 2001-01-22. After hosting the game for so long, we're considering the difficult decision to take the site offline.

To honor the players who played the game every day for over twenty years, I'm open sourcing the code for the game here.

See https://github.com/Bryan-Legend/globalcombat/issues/11 if you'd be interested in hosting GC.

# Running the Phoenix port locally

The `liveview/` directory holds the Elixir / Phoenix LiveView port of the game. The
only local dependency is Docker; the compose stack builds the Phoenix app and a
Postgres 18 instance the app migrates on boot.

```bash
make dev
```

Then open http://localhost:11400. The dev database is seeded with a ready-to-use
account:

| Login | Password |
|---|---|
| `modern_player` | `correcthorse` |

Create a game with **Training Mode** checked to play against the Computer opponent
without a second person. Ports are pinned to the `11400` block (`11400` web, `11410`
gRPC engine, `11434` Postgres, loopback only) -- see the header of `docker-compose.yml`.

The `.NET` gRPC engine host is optional. The app resolves turns with its own Elixir
engine; the .NET host is only needed for the differential harness that checks the two
engines agree:

```bash
docker compose --profile engine up -d grpc-host
docker compose run --rm web mix game_engine.diff_harness --turns 50 --seed 42
```

One stack at a time: the compose project name and subnet are fixed, so the stack is
shared by every checkout of this repo on the machine. Running `make dev` from a second
clone or worktree re-points the running containers at that checkout's files (same
database, same ports) rather than starting a second copy.

This repository is public. CI refuses pushes and PRs that add internal tracker ids,
non-public email addresses, or internal hostnames and host paths (see `scripts/check-internal-refs.mjs`);
enable the same check locally with `git config core.hooksPath .githooks`. Keep private
infrastructure out of docs too: say "the fleet's port registry" or "the secrets manager"
rather than naming the repo or the product.

Run the test suite inside the web container:

```bash
docker compose exec web mix test
```

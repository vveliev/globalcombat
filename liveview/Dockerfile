# Dev-mode image for the gRPC spike client only (mix game_engine.resolve_turn).
# Not the production release Dockerfile for the Phoenix app.
FROM hexpm/elixir:1.18.3-erlang-27.3.4-debian-bookworm-20250811-slim

RUN apt-get update -y && apt-get install -y --no-install-recommends git ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get

COPY . .
RUN mix deps.compile

ENV MIX_ENV=dev
CMD ["mix", "game_engine.resolve_turn"]

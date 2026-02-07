ARG BUILDER_IMAGE="hexpm/elixir:1.15.8-erlang-25.3.2.5-debian-bullseye-20260202"
ARG RUNNER_IMAGE="debian:bullseye-20260202"

FROM ${BUILDER_IMAGE} AS builder

ARG MIX_ENV=prod
ENV MIX_ENV=${MIX_ENV}

WORKDIR /app

RUN apt-get update -y && apt-get install -y \
  build-essential \
  git \
  curl \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only ${MIX_ENV}
RUN mix deps.compile

COPY priv priv
COPY assets assets
COPY lib lib

RUN mix compile
RUN mix assets.deploy
RUN mix release

FROM ${RUNNER_IMAGE} AS runner

RUN apt-get update -y && apt-get install -y \
  libstdc++6 \
  openssl \
  libncurses5 \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

ENV MIX_ENV=prod
ENV LANG=C.UTF-8

COPY --from=builder /app/_build/prod/rel/luca_gymapp ./

CMD ["/app/bin/luca_gymapp", "start"]

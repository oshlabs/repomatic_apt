ARG ELIXIR_VERSION=1.18.3
ARG OTP_VERSION=27.3
ARG DEBIAN_VERSION=bookworm-20250224-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

# Build stage
FROM ${BUILDER_IMAGE} AS build

RUN apt-get update -y && apt-get install -y build-essential && apt-get clean

WORKDIR /app

ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV && mix deps.compile

COPY config/config.exs config/prod.exs config/runtime.exs config/
COPY lib lib

RUN mix compile --warnings-as-errors
RUN mix release

# Runtime stage
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app

RUN groupadd --system repomatic && \
    useradd --system --gid repomatic --home /app repomatic && \
    mkdir -p /var/lib/repomatic_apt/repo && \
    chown -R repomatic:repomatic /var/lib/repomatic_apt /app

COPY --from=build --chown=repomatic:repomatic /app/_build/prod/rel/repomatic_apt ./

USER repomatic

EXPOSE 4080
EXPOSE 4443

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -sf http://localhost:4080/healthz || exit 1

CMD ["bin/repomatic_apt", "start"]

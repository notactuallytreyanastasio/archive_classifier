# Build stage
ARG BUILDER_IMAGE="hexpm/elixir:1.18.1-erlang-27.3.4.8-debian-bookworm-20260202-slim"
ARG RUNNER_IMAGE="debian:bookworm-20260202-slim"

FROM ${BUILDER_IMAGE} AS builder

# Install build dependencies (including FFmpeg 7 dev libs for Xav NIF)
RUN apt-get update -y && apt-get install -y \
    build-essential git nodejs npm pkg-config \
    libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libswresample-dev libavdevice-dev \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV="prod"

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets

# Compile first — colocated JS hooks need the build artifacts
RUN mix compile
RUN mix assets.deploy

COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# Runner stage
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
  apt-get install -y libstdc++6 openssl libncurses5 locales \
  ffmpeg libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libswresample-dev \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

ENV MIX_ENV="prod"

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/archive_classifier ./

USER nobody

CMD ["/app/bin/server"]

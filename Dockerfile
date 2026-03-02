FROM hexpm/elixir:1.18.3-erlang-27.0-debian-bookworm-20250113 AS build

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
  build-essential \
  git \
  npm \
  cmake \
  curl \
  ca-certificates \
  pkg-config \
  libssl-dev \
  libavcodec-dev \
  libavformat-dev \
  libavutil-dev \
  libswscale-dev \
  libclang-dev \
  libsrtp2-dev \
  libjpeg-dev \
  linux-headers-generic \
  libgstreamer1.0-dev \
  libgstreamer-plugins-base1.0-dev \
  && rm -rf /var/lib/apt/lists/*

ARG VERSION
ENV VERSION=${VERSION}
ENV DOCKER_BUILD=true

ARG ERL_FLAGS
ENV ERL_FLAGS=$ERL_FLAGS

WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
  mix local.rebar --force

ENV MIX_ENV=prod

# Copy source
COPY video_processor video_processor
COPY ui ui

WORKDIR /app/ui

RUN mix deps.get
RUN mix deps.compile

# Compile and build release
RUN mix do compile, release

# ============================================================
# Runtime stage: Debian bookworm with Rockchip MPP
# ============================================================
FROM debian:bookworm-slim AS app

# Install Radxa APT repos for Rockchip-specific packages
RUN apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  gnupg \
  && curl -fsSL https://radxa-repo.github.io/radxa-archive-keyring.gpg \
     -o /usr/share/keyrings/radxa-archive-keyring.gpg \
  && echo "deb [signed-by=/usr/share/keyrings/radxa-archive-keyring.gpg] https://radxa-repo.github.io/bookworm bookworm main" \
     > /etc/apt/sources.list.d/radxa.list \
  && echo "deb [signed-by=/usr/share/keyrings/radxa-archive-keyring.gpg] https://radxa-repo.github.io/rk3588-bookworm rk3588-bookworm main" \
     > /etc/apt/sources.list.d/radxa-rk3588.list \
  && apt-get update \
  && rm -rf /var/lib/apt/lists/*

# Install runtime dependencies + Rockchip hardware acceleration
RUN apt-get update && apt-get install -y --no-install-recommends \
  bash \
  openssl \
  libncurses6 \
  ffmpeg \
  libavcodec59 \
  libavformat59 \
  libavutil57 \
  libswscale6 \
  libclang-cpp14 \
  curl \
  libsrtp2-1 \
  libjpeg62-turbo \
  coreutils \
  util-linux \
  # GStreamer core + plugins
  gstreamer1.0-tools \
  gstreamer1.0-plugins-base \
  gstreamer1.0-plugins-good \
  gstreamer1.0-plugins-bad \
  gstreamer1.0-plugins-ugly \
  gstreamer1.0-libav \
  gstreamer1.0-rtsp \
  # Rockchip hardware acceleration
  librockchip-mpp1 \
  librockchip-vpu0 \
  gstreamer1.0-rockchip1 \
  librga2 \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mkdir -p /var/lib/cvr /tmp/hls /data/nvr /mnt/storage

COPY --from=build /app/ui/_build/prod/rel/tpro_nvr ./

ENV HOME=/app

EXPOSE 4000

HEALTHCHECK CMD curl --fail http://localhost:4321 || exit 1

COPY entrypoint.sh ./entrypoint.sh

RUN chmod +x entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]

CMD ["bin/tpro_nvr", "start"]
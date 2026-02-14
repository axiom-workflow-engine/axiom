# ============================================================================
# Stage 1: Build
# ============================================================================
FROM hexpm/elixir:1.17.3-erlang-27.1.2-debian-bookworm-20241016-slim AS builder

ARG APP_VERSION=0.1.0
ARG MIX_ENV=prod

ENV MIX_ENV=${MIX_ENV} \
    LANG=C.UTF-8

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
      build-essential \
      git \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Install dependencies first (layer caching)
COPY mix.exs mix.lock ./
COPY apps/axiom_core/mix.exs apps/axiom_core/
COPY apps/axiom_wal/mix.exs apps/axiom_wal/
COPY apps/axiom_engine/mix.exs apps/axiom_engine/
COPY apps/axiom_scheduler/mix.exs apps/axiom_scheduler/
COPY apps/axiom_worker/mix.exs apps/axiom_worker/
COPY apps/axiom_gateway/mix.exs apps/axiom_gateway/
COPY apps/axiom_projections/mix.exs apps/axiom_projections/
COPY apps/axiom_chaos/mix.exs apps/axiom_chaos/
COPY apps/axiom_cli/mix.exs apps/axiom_cli/

RUN mix deps.get --only ${MIX_ENV} && \
    mix deps.compile

# Copy application code
COPY config config
COPY apps apps

# Compile the release
RUN mix compile

# Build the OTP release
RUN mix release axiom

# ============================================================================
# Stage 2: Runtime
# ============================================================================
FROM debian:bookworm-20241016-slim AS runner

ARG APP_VERSION=0.1.0

ENV LANG=C.UTF-8 \
    MIX_ENV=prod \
    PHX_SERVER=true \
    RELEASE_DISTRIBUTION=name \
    RELEASE_NODE=axiom@127.0.0.1

# Labels (OCI Image Spec)
LABEL org.opencontainers.image.title="Axiom Workflow Engine" \
      org.opencontainers.image.description="Exactly-once, crash-safe workflow orchestration engine" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.source="https://github.com/axiom-workflow-engine/axiom" \
      org.opencontainers.image.licenses="MIT"

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
      libstdc++6 \
      openssl \
      libncurses5 \
      locales \
      ca-certificates \
      curl \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Set locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8

# Create non-root user
RUN groupadd --gid 1000 axiom && \
    useradd --uid 1000 --gid axiom --shell /bin/bash --create-home axiom

# Create directories
RUN mkdir -p /var/lib/axiom/wal /var/log/axiom && \
    chown -R axiom:axiom /var/lib/axiom /var/log/axiom

WORKDIR /app

# Copy the release from builder
COPY --from=builder --chown=axiom:axiom /app/_build/prod/rel/axiom ./

USER axiom

# WAL data volume
VOLUME ["/var/lib/axiom/wal"]

# Phoenix HTTP + EPMD + Erlang distribution range
EXPOSE 4000 4369 9100-9200

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD curl -sf http://localhost:4000/health || exit 1

ENTRYPOINT ["bin/axiom"]
CMD ["start"]

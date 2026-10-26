FROM ghcr.io/astral-sh/uv@sha256:32a7bb39b496babbd997b0a39a4d66c126bdaf5661b302bf6f06abda8deca6ff AS uv

FROM python:3.12-slim-bookworm AS python-base
RUN apt-get update \
    && apt-get install --yes --no-install-recommends --only-upgrade libssl3 openssl \
    && rm -rf /var/lib/apt/lists/*

FROM python-base AS builder
COPY --from=uv /uv /usr/local/bin/uv
ENV UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never
WORKDIR /build
COPY pyproject.toml uv.lock .python-version ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev --no-install-project --python /usr/local/bin/python

FROM python-base AS runtime
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    ADMIN_API_TOKEN_FILE=/run/secrets/admin_api_token
WORKDIR /app
RUN groupadd --gid 10001 app \
    && useradd --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app
COPY --from=builder /opt/venv /opt/venv
COPY --chown=10001:10001 app ./app
COPY --chown=10001:10001 config ./config
USER 10001:10001
EXPOSE 8000
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health/ready', timeout=2).close()"]
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1", "--no-access-log", "--no-proxy-headers"]

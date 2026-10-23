# Status Board

Service status dashboard with a public read API and authenticated status updates. Built with Python, FastAPI and vanilla JavaScript.

## Requirements

- Docker Desktop with Linux containers, or Docker Engine with Compose v2 or later.
- Python 3.12 for development without Docker.

## Run with Docker

Run commands from the repository root. Create a local API token on Windows:

```powershell
./scripts/New-LocalSecret.ps1
```

On Linux or macOS:

```sh
python3 scripts/new_local_secret.py
```

Start the application:

```sh
docker compose up --build -d --wait
```

The dashboard is available at [http://localhost:8000](http://localhost:8000). Compose binds the service to the local machine only.

The token is stored in `.secrets/admin_api_token` and mounted read-only into the container. The setup scripts preserve an existing token. Keep this file private; it is excluded from Git and the Docker build context.

## Configuration

Copy `.env.example` to `.env` to customize Compose settings. Apply changes with `docker compose up -d --force-recreate --wait`.

| Variable | Default | Description |
| --- | --- | --- |
| `BOARD_TITLE` | `Platform Status` | Dashboard title |
| `APP_ENV` | `local` | Environment label |
| `APP_VERSION` | `dev` | Application version |
| `LOG_LEVEL` | `INFO` | Application log level |
| `ADMIN_API_TOKEN_FILE` | `/run/secrets/admin_api_token` in Docker | Path to the API token file |
| `SERVICES_FILE` | `config/services.json` | Service configuration file |

Service definitions are loaded from `config/services.json` at startup. Restart the application after changing them. For a custom `SERVICES_FILE` in Docker, mount the file and set its container path in `compose.yaml`.

The token must contain 32–512 URL-safe characters: letters, digits, `_` or `-`. A trailing newline is accepted. The application requires a valid token file at startup. For direct Python runs, the default token path is `.secrets/admin_api_token`.

## Submit a status report

Select **Report an update** in the dashboard and enter the API token, or send an authenticated request:

```powershell
$adminToken = (Get-Content -Raw .secrets/admin_api_token).Trim()
$headers = @{ Authorization = "Bearer $adminToken" }
$body = @{
    status = 'operational'
    message = 'All checks passed.'
    response_time_ms = 42
} | ConvertTo-Json

Invoke-RestMethod -Method Put `
    -Uri http://localhost:8000/api/services/public-api/status `
    -Headers $headers -ContentType application/json -Body $body

Remove-Variable adminToken, headers
```

Available service IDs are defined in `config/services.json`. The default IDs are `public-api`, `background-worker` and `notifications`.

Supported statuses: `operational`, `degraded`, `outage`, `maintenance`, `unknown`. The optional message accepts up to 240 characters. The optional `response_time_ms` accepts an integer from 0 to 600000.

Reports are public. Response times are supplied by the reporting client; the application does not probe services. New services remain `unknown` until a report is submitted. The dashboard refreshes every 10 seconds.

## API

| Method | Endpoint | Authentication | Description |
| --- | --- | --- | --- |
| GET | `/api/status` | None | Service statuses, recent reports and application metadata |
| PUT | `/api/services/{service_id}/status` | Bearer token | Submit a status report |
| GET | `/health/live` | None | Process health |
| GET | `/health/ready` | None | Application readiness, including token availability |
| GET | `/openapi.json` | None | OpenAPI schema |

Status updates return `401` for missing or invalid credentials, `404` for an unknown service and `422` for invalid report data. If the configured token file becomes unavailable or invalid, readiness and authenticated operations return `503`.

## Operations

```sh
docker compose ps
docker compose logs --tail 50 status-board
docker compose restart status-board
docker compose down
```

The token file is reread on each authenticated request. After replacing a local token file, recreate the container if the mounted file does not reflect the change:

```sh
docker compose up -d --force-recreate --wait
```

Service state and the latest 50 reports are held in process memory and reset on restart. Run a single worker and a single replica. Reported statuses do not expire automatically.

The container runs as UID/GID `10001:10001` with a read-only root filesystem. Local Compose secrets are files on the host; protect them with filesystem permissions. Use HTTPS through a reverse proxy when exposing the service beyond localhost.

## Development

```powershell
py -3.12 -m venv .venv
./.venv/Scripts/python.exe -m pip install --require-hashes -r requirements-dev.txt
./scripts/New-LocalSecret.ps1
./.venv/Scripts/python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --no-access-log --no-proxy-headers
```

On Linux or macOS, use `python3.12 -m venv .venv`, `.venv/bin/python` and `python3 scripts/new_local_secret.py`. Compose reads `.env` automatically; direct Python runs use the process environment.

Run tests:

```sh
python -m pytest
```

Use the Python executable from `.venv` when the environment is not activated.

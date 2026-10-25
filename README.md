# Status Board

Service status dashboard with a public read API and authenticated status updates. Built with Python, FastAPI and vanilla JavaScript.

## Requirements

- Docker Desktop with Linux containers, or Docker Engine with Compose v2 or later.
- [uv 0.13.5](https://docs.astral.sh/uv/getting-started/installation/) for local development. Python 3.12 is selected by `.python-version` and can be installed with uv.

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
uv python install
uv sync --locked
uv run --locked python scripts/new_local_secret.py
uv run --locked uvicorn app.main:app --host 127.0.0.1 --port 8000 --no-access-log --no-proxy-headers
```

These commands work on Windows, Linux and macOS. Compose reads `.env` automatically; direct Python runs use the process environment.

Dependencies are declared in `pyproject.toml` and resolved in `uv.lock`. The `dev` group contains test, lint and audit tools. `uv sync --locked` creates or updates `.venv` without changing the lockfile. Docker installs only runtime dependencies with `uv sync --locked --no-dev`.

Run tests:

```sh
uv run --locked pytest
```

Add dependencies with `uv add <package>` or `uv add --dev <package>`. Use `uv lock --upgrade-package <package>` for a targeted update. Commit both `pyproject.toml` and `uv.lock` when dependencies change.

## Continuous integration

The `CI` workflow runs on pull requests targeting `main`, pushes to `main` and manual dispatch. It validates workflow files with actionlint, scans Git history with Gitleaks, verifies `uv.lock`, runs Ruff lint and formatting checks, executes pytest and audits locked dependencies with pip-audit.

Application images are built only when manually requested. In **Actions → CI → Run workflow**, select a branch and enable `build_image` to build the image and run container smoke tests. The option defaults to `false`. The workflow does not publish images.

Use the `CI` status check in branch protection.

Run the Python checks locally:

```sh
uv lock --check
uv sync --locked
uv run --locked ruff check .
uv run --locked ruff format --check .
uv run --locked pytest
uv export --locked --all-groups --no-emit-project --no-header --no-annotate --quiet --output-file requirements-audit.txt
uv run --locked pip-audit --strict --disable-pip --require-hashes -r requirements-audit.txt
```

`requirements-audit.txt` is a generated audit input excluded from Git. CI exports it to runner temporary storage. `uv.lock` is the project's dependency lockfile.

With the container running, execute `uv run --locked python scripts/smoke_test.py` to verify the HTTP API. This submits a status report for the first configured service.

## Azure infrastructure

Terraform configurations for the AKS development environment and its state backend are in [infra/README.md](infra/README.md). The `Infrastructure CI` workflow checks formatting, validates both configurations, runs mocked security tests, executes TFLint with AzureRM rules and scans for high and critical misconfigurations with Trivy. It runs without Azure credentials and does not provision resources.

Add `Infrastructure CI` alongside `CI` to the required status checks for `main`.

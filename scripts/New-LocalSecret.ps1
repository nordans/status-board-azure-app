$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$secretDir = Join-Path $repoRoot '.secrets'
$secretPath = Join-Path $secretDir 'admin_api_token'
if (Test-Path -LiteralPath $secretPath) {
    Write-Host 'Local secret already exists; left unchanged.'
    exit 0
}
New-Item -ItemType Directory -Path $secretDir -Force | Out-Null
$randomBytes = New-Object byte[] 32
$generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
try { $generator.GetBytes($randomBytes) } finally { $generator.Dispose() }
$token = [Convert]::ToBase64String($randomBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
[IO.File]::WriteAllText($secretPath, $token, [Text.UTF8Encoding]::new($false))
Write-Host 'Created .secrets/admin_api_token (ignored by Git and excluded from the image).'

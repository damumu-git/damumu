[CmdletBinding()]
param(
    [switch]$StopDatabase
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $repositoryRoot 'docker-compose.local-test.yml'
$connectionString = 'Host=127.0.0.1;Port=55432;Database=damumu_test;Username=damumu;Password=damumu-local;SSL Mode=Disable'
$apiUrl = 'http://127.0.0.1:8089'
$apiProcess = $null

try {
    docker compose -f $composeFile up -d --wait
    if ($LASTEXITCODE -ne 0) { throw 'Local PostGIS container failed to start' }

    Get-ChildItem (Join-Path $repositoryRoot 'restapi/Migrations') -Filter '*.sql' |
        Sort-Object Name |
        ForEach-Object {
            Write-Host "Applying $($_.Name)"
            Get-Content -LiteralPath $_.FullName -Raw |
                docker compose -f $composeFile exec -T postgres `
                    psql -v ON_ERROR_STOP=1 -U damumu -d damumu_test
            if ($LASTEXITCODE -ne 0) { throw "Migration failed: $($_.Name)" }
        }

    Get-Content -LiteralPath (Join-Path $repositoryRoot 'restapi.tests/local_seed.sql') -Raw |
        docker compose -f $composeFile exec -T postgres `
            psql -v ON_ERROR_STOP=1 -U damumu -d damumu_test
    if ($LASTEXITCODE -ne 0) { throw 'Local test seed failed' }

    $testOutput = Join-Path $repositoryRoot 'restapi/.codex-build/local-postgres-tests'
    dotnet build (Join-Path $repositoryRoot 'restapi.tests/Muda.Api.PaginationTests.csproj') `
        --no-restore -o $testOutput
    if ($LASTEXITCODE -ne 0) { throw 'Test project build failed' }

    $previousConnection = $env:ConnectionStrings__Muda
    $previousEnvironment = $env:ASPNETCORE_ENVIRONMENT
    $previousUrls = $env:ASPNETCORE_URLS
    $env:ConnectionStrings__Muda = $connectionString
    $env:ASPNETCORE_ENVIRONMENT = 'Testing'
    $env:ASPNETCORE_URLS = $apiUrl
    $apiProcess = Start-Process -FilePath 'dotnet' -WindowStyle Hidden -PassThru `
        -ArgumentList @((Join-Path $testOutput 'Muda.Api.dll'))
    $env:ConnectionStrings__Muda = $previousConnection
    $env:ASPNETCORE_ENVIRONMENT = $previousEnvironment
    $env:ASPNETCORE_URLS = $previousUrls

    $healthy = $false
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri "$apiUrl/api/v1/health" -TimeoutSec 2 | Out-Null
            $healthy = $true
            break
        } catch {
            Start-Sleep -Milliseconds 500
        }
    }
    if (-not $healthy) { throw 'Local test API did not become healthy' }

    dotnet (Join-Path $testOutput 'Muda.Api.PaginationTests.dll') `
        "$apiUrl/" (Join-Path $repositoryRoot 'restapi/appsettings.Testing.json')
    if ($LASTEXITCODE -ne 0) { throw 'Local PostgreSQL integration tests failed' }
} finally {
    if ($null -ne $apiProcess -and -not $apiProcess.HasExited) {
        Stop-Process -Id $apiProcess.Id
    }
    if ($StopDatabase) {
        docker compose -f $composeFile down
    }
}

[CmdletBinding()]
param(
    [string]$Database = 'muda',
    [string]$Username = 'postgres',
    [switch]$ApplyMigrations
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$apiUrl = 'http://127.0.0.1:8089'
$apiProcess = $null
$buildRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot 'restapi/.codex-build'))
$testOutput = Join-Path $buildRoot ('local-postgres-tests-' + [Guid]::NewGuid().ToString('N'))
$password = $env:DAMUMU_LOCAL_POSTGRES_PASSWORD

if ([string]::IsNullOrWhiteSpace($password)) {
    $securePassword = Read-Host 'localhost:5432 PostgreSQL password' -AsSecureString
    $password = [System.Net.NetworkCredential]::new('', $securePassword).Password
}
if ([string]::IsNullOrWhiteSpace($password)) {
    throw 'A local PostgreSQL password is required'
}

$connectionString = "Host=127.0.0.1;Port=5432;Database=$Database;Username=$Username;Password=$password;SSL Mode=Disable"
$psql = 'C:\Program Files\PostgreSQL\17\bin\psql.exe'
if (-not (Test-Path -LiteralPath $psql)) {
    $psqlCommand = Get-Command psql -ErrorAction SilentlyContinue
    if ($null -eq $psqlCommand) { throw 'PostgreSQL psql was not found' }
    $psql = $psqlCommand.Source
}

$previousPassword = $env:PGPASSWORD
$previousConnection = $env:ConnectionStrings__Muda
$previousEnvironment = $env:ASPNETCORE_ENVIRONMENT
$previousUrls = $env:ASPNETCORE_URLS

try {
    $env:PGPASSWORD = $password
    & $psql -h 127.0.0.1 -p 5432 -U $Username -d $Database -v ON_ERROR_STOP=1 -P pager=off `
        -tAc 'SELECT current_database(), current_user'
    if ($LASTEXITCODE -ne 0) { throw 'Could not connect to localhost:5432 PostgreSQL' }

    if ($ApplyMigrations) {
        Get-ChildItem (Join-Path $repositoryRoot 'restapi/Migrations') -Filter '*.sql' |
            Sort-Object Name |
            ForEach-Object {
                Write-Host "Applying $($_.Name)"
                Get-Content -LiteralPath $_.FullName -Raw |
                    & $psql -h 127.0.0.1 -p 5432 -U $Username -d $Database `
                        -v ON_ERROR_STOP=1 -P pager=off
                if ($LASTEXITCODE -ne 0) { throw "Migration failed: $($_.Name)" }
            }
    }

    dotnet build (Join-Path $repositoryRoot 'restapi.tests/Muda.Api.PaginationTests.csproj') `
        --no-restore -o $testOutput
    if ($LASTEXITCODE -ne 0) { throw 'Test project build failed' }

    $env:ConnectionStrings__Muda = $connectionString
    $env:ASPNETCORE_ENVIRONMENT = 'Testing'
    $env:ASPNETCORE_URLS = $apiUrl
    $apiProcess = Start-Process -FilePath 'dotnet' -WindowStyle Hidden -PassThru `
        -ArgumentList @((Join-Path $testOutput 'Muda.Api.dll'))

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
        "$apiUrl/" (Join-Path $repositoryRoot 'restapi/appsettings.json')
    if ($LASTEXITCODE -ne 0) { throw 'Local PostgreSQL integration tests failed' }
} finally {
    if ($null -ne $apiProcess -and -not $apiProcess.HasExited) {
        Stop-Process -Id $apiProcess.Id -ErrorAction SilentlyContinue
        $apiProcess.WaitForExit(5000) | Out-Null
    }
    $resolvedOutput = [System.IO.Path]::GetFullPath($testOutput)
    if ($resolvedOutput.StartsWith($buildRoot + [System.IO.Path]::DirectorySeparatorChar) -and
        (Test-Path -LiteralPath $resolvedOutput)) {
        Remove-Item -LiteralPath $resolvedOutput -Recurse -Force -ErrorAction SilentlyContinue
    }
    $env:PGPASSWORD = $previousPassword
    $env:ConnectionStrings__Muda = $previousConnection
    $env:ASPNETCORE_ENVIRONMENT = $previousEnvironment
    $env:ASPNETCORE_URLS = $previousUrls
}

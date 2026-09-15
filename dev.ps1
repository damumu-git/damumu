$ErrorActionPreference = 'Stop'

$repositoryRoot = $PSScriptRoot
$logDirectory = Join-Path $repositoryRoot '.dev-logs'
$apiPort = if ($env:API_PORT) { $env:API_PORT } else { '8080' }
$adminPort = if ($env:ADMIN_PORT) { $env:ADMIN_PORT } else { '5173' }
$apiBaseUrl = if ($env:API_BASE_URL) {
    $env:API_BASE_URL
} else {
    "http://localhost:$apiPort/api/v1"
}
$databaseConnection = $env:ConnectionStrings__Muda
if ([string]::IsNullOrWhiteSpace($databaseConnection)) {
    $databaseName = if ($env:DAMUMU_LOCAL_POSTGRES_DATABASE) {
        $env:DAMUMU_LOCAL_POSTGRES_DATABASE
    } else { 'muda' }
    $databaseUsername = if ($env:DAMUMU_LOCAL_POSTGRES_USERNAME) {
        $env:DAMUMU_LOCAL_POSTGRES_USERNAME
    } else { 'postgres' }
    $databasePassword = $env:DAMUMU_LOCAL_POSTGRES_PASSWORD
    if ([string]::IsNullOrWhiteSpace($databasePassword)) {
        $securePassword = Read-Host 'localhost:5432 PostgreSQL password' -AsSecureString
        $databasePassword = [System.Net.NetworkCredential]::new('', $securePassword).Password
    }
    if ([string]::IsNullOrWhiteSpace($databasePassword)) {
        throw '本地 PostgreSQL 密码不能为空。'
    }
    $databaseConnection = "Host=127.0.0.1;Port=5432;Database=$databaseName;Username=$databaseUsername;Password=$databasePassword;SSL Mode=Disable"
}
$flutterArguments = @($args)
$servicesOnly = $flutterArguments.Count -gt 0 -and $flutterArguments[0] -eq '--services'
if ($servicesOnly) {
    $flutterArguments = @($flutterArguments | Select-Object -Skip 1)
}

function Resolve-Executable([string[]]$Names, [string]$Description) {
    foreach ($name in $Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $command) { return $command.Source }
    }
    throw "找不到 $Description。请先安装并确认它已加入 PATH。"
}

function Stop-DevelopmentProcess([System.Diagnostics.Process]$Process) {
    if ($null -eq $Process -or $Process.HasExited) { return }
    & taskkill.exe /PID $Process.Id /T /F *> $null
}

function Show-StartupFailure([string]$Name, [string]$ErrorLog) {
    Write-Host "$Name 启动失败。" -ForegroundColor Red
    if (Test-Path -LiteralPath $ErrorLog) {
        Get-Content -LiteralPath $ErrorLog -Tail 30
    }
}

function Wait-DevelopmentEndpoint(
    [string]$Uri,
    [System.Diagnostics.Process]$Process,
    [int]$Attempts = 30
) {
    $client = [System.Net.Http.HttpClient]::new()
    $client.Timeout = [TimeSpan]::FromSeconds(2)
    try {
        for ($attempt = 0; $attempt -lt $Attempts; $attempt++) {
            if ($Process.HasExited) { return $false }
            try {
                $response = $client.GetAsync(
                    $Uri,
                    [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead
                ).GetAwaiter().GetResult()
                try {
                    if ($response.IsSuccessStatusCode) { return $true }
                } finally {
                    $response.Dispose()
                }
            } catch {
                Start-Sleep -Milliseconds 500
            }
        }
        return $false
    } finally {
        $client.Dispose()
    }
}

$dotnet = Resolve-Executable @('dotnet.exe', 'dotnet') '.NET 10 SDK'
$node = Resolve-Executable @('node.exe', 'node') 'Node.js'
$viteEntryPoint = Join-Path $repositoryRoot 'admin/node_modules/vite/bin/vite.js'
if (-not (Test-Path -LiteralPath $viteEntryPoint)) {
    throw '找不到 Admin 的 Vite。请先在 admin 目录执行 npm install。'
}
$flutter = if ($servicesOnly) { $null } else {
    Resolve-Executable @('flutter.bat', 'flutter.exe', 'flutter') 'Flutter'
}

New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$apiLog = Join-Path $logDirectory 'restapi.log'
$apiErrorLog = Join-Path $logDirectory 'restapi.error.log'
$adminLog = Join-Path $logDirectory 'admin.log'
$adminErrorLog = Join-Path $logDirectory 'admin.error.log'
$apiProcess = $null
$adminProcess = $null

$previousAspNetEnvironment = $env:ASPNETCORE_ENVIRONMENT
$previousAspNetUrls = $env:ASPNETCORE_URLS
$previousViteApiBase = $env:VITE_API_BASE
$previousDatabaseConnection = $env:ConnectionStrings__Muda

try {
    Write-Host "启动 REST API：http://localhost:$apiPort/api/v1"
    $env:ASPNETCORE_ENVIRONMENT = 'Development'
    $env:ASPNETCORE_URLS = "http://localhost:$apiPort"
    $env:ConnectionStrings__Muda = $databaseConnection
    $apiProcess = Start-Process -FilePath $dotnet -WindowStyle Hidden -PassThru `
        -WorkingDirectory (Join-Path $repositoryRoot 'restapi') `
        -ArgumentList @('run', '--no-launch-profile') `
        -RedirectStandardOutput $apiLog -RedirectStandardError $apiErrorLog
    $env:ASPNETCORE_ENVIRONMENT = $previousAspNetEnvironment
    $env:ASPNETCORE_URLS = $previousAspNetUrls
    $env:ConnectionStrings__Muda = $previousDatabaseConnection

    Write-Host "启动 Admin：http://localhost:$adminPort"
    $env:VITE_API_BASE = "http://localhost:$apiPort/api/v1"
    $adminProcess = Start-Process -FilePath $node -WindowStyle Hidden -PassThru `
        -WorkingDirectory (Join-Path $repositoryRoot 'admin') `
        -ArgumentList @($viteEntryPoint, '--host', '127.0.0.1', '--port', $adminPort) `
        -RedirectStandardOutput $adminLog -RedirectStandardError $adminErrorLog
    $env:VITE_API_BASE = $previousViteApiBase

    if (-not (Wait-DevelopmentEndpoint "http://localhost:$apiPort/api/v1/health" $apiProcess)) {
        Show-StartupFailure 'REST API' $apiErrorLog
        throw 'REST API 未通过健康检查，请确认 localhost:5432/muda 的账号和密码。'
    }
    if (-not (Wait-DevelopmentEndpoint "http://localhost:$adminPort" $adminProcess)) {
        Show-StartupFailure 'Admin' $adminErrorLog
        throw 'Admin 启动失败'
    }

    Write-Host "日志目录：$logDirectory"
    if ($servicesOnly) {
        Write-Host 'Admin 和 REST API 已启动；按 Ctrl+C 停止。'
        while (-not $apiProcess.HasExited -and -not $adminProcess.HasExited) {
            Start-Sleep -Seconds 1
        }
        throw '开发服务意外停止，请检查 .dev-logs。'
    }

    Write-Host "启动 Flutter App（API：$apiBaseUrl）"
    Push-Location (Join-Path $repositoryRoot 'app')
    try {
        & $flutter run "--dart-define=API_BASE_URL=$apiBaseUrl" @flutterArguments
        if ($LASTEXITCODE -ne 0) { throw "Flutter 运行失败，退出代码：$LASTEXITCODE" }
    } finally {
        Pop-Location
    }
} finally {
    $env:ASPNETCORE_ENVIRONMENT = $previousAspNetEnvironment
    $env:ASPNETCORE_URLS = $previousAspNetUrls
    $env:VITE_API_BASE = $previousViteApiBase
    $env:ConnectionStrings__Muda = $previousDatabaseConnection
    Write-Host '正在停止 DAMUMU 开发服务…'
    Stop-DevelopmentProcess $adminProcess
    Stop-DevelopmentProcess $apiProcess
}

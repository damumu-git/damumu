$ErrorActionPreference = 'Stop'

$repositoryRoot = $PSScriptRoot
$processFile = Join-Path $repositoryRoot '.dev-logs/dev-processes.json'

if (-not (Test-Path -LiteralPath $processFile)) {
    Write-Host '没有找到 DAMUMU 开发服务的 PID 文件。'
    Write-Host '如果服务由旧版 dev.ps1 启动，可按端口查找并停止：'
    Write-Host '  netstat -ano | findstr ":8080 :5173"'
    Write-Host '  taskkill /PID <PID> /T /F'
    exit 0
}

try {
    $manifest = Get-Content -LiteralPath $processFile -Raw | ConvertFrom-Json
} catch {
    throw "PID 文件无法读取：$processFile"
}

if ($manifest.repositoryRoot -ne $repositoryRoot) {
    throw 'PID 文件属于另一个项目目录，已拒绝停止进程。'
}

$stopped = 0
foreach ($entry in $manifest.processes) {
    $process = Get-Process -Id ([int]$entry.pid) -ErrorAction SilentlyContinue
    if ($null -eq $process) {
        continue
    }

    $actualStartTicks = $process.StartTime.ToUniversalTime().Ticks
    if ($actualStartTicks -ne [long]$entry.startedAtUtcTicks) {
        Write-Warning "$($entry.name) 的 PID $($entry.pid) 已被其他进程复用，跳过。"
        continue
    }

    Write-Host "正在停止 $($entry.name)（PID $($entry.pid)，端口 $($entry.port)）…"
    & taskkill.exe /PID $process.Id /T /F *> $null
    if ($LASTEXITCODE -ne 0 -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
    }
    $process.WaitForExit(3000) | Out-Null
    if (-not $process.HasExited) {
        throw "无法停止 $($entry.name)（PID $($entry.pid)）。请以管理员身份运行此脚本。"
    }
    $stopped++
}

Remove-Item -LiteralPath $processFile -Force
if ($stopped -eq 0) {
    Write-Host '记录的开发服务已经停止。'
} else {
    Write-Host 'DAMUMU 开发服务已停止。'
}

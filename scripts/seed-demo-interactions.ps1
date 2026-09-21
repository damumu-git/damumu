[CmdletBinding()]
param(
    [ValidateRange(2, 100)]
    [int]$UserCount = 20,
    [string]$ApiBaseUrl = 'http://127.0.0.1:8080/api/v1',
    [string]$RunTag = (Get-Date -Format 'yyyyMMdd-HHmmss'),
    [string]$Password = $env:DAMUMU_DEMO_PASSWORD,
    [string]$ResumeManifest
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $repositoryRoot '.dev-data'
$outputPath = Join-Path $outputDirectory "demo-interactions-$RunTag.json"

if ([string]::IsNullOrWhiteSpace($Password)) {
    $Password = 'Demo!' + [Guid]::NewGuid().ToString('N').Substring(0, 18) + '7a'
}

function Invoke-DamumuApi {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')] [string]$Method = 'GET',
        [string]$Token,
        [object]$Body
    )

    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $headers.Authorization = "Bearer $Token"
    }
    $parameters = @{
        Uri = "$ApiBaseUrl$Path"
        Method = $Method
        Headers = $headers
        TimeoutSec = 20
    }
    if ($null -ne $Body) {
        $parameters.ContentType = 'application/json; charset=utf-8'
        $parameters.Body = $Body | ConvertTo-Json -Depth 10 -Compress
    }

    try {
        $response = Invoke-RestMethod @parameters
    } catch {
        $detail = $_.ErrorDetails.Message
        if (-not [string]::IsNullOrWhiteSpace($detail)) {
            throw "API $Method $Path failed: $detail"
        }
        throw
    }
    return $response.data
}

Write-Host "Checking API: $ApiBaseUrl"
$health = Invoke-DamumuApi -Path '/health'
if ($health.status -ne 'healthy') {
    throw 'API health check did not return healthy.'
}

$categories = @(Invoke-DamumuApi -Path '/categories') |
    Where-Object { $_.level -eq 2 -and -not $_.requires_custom_label }
$regions = @(Invoke-DamumuApi -Path '/regions')
$cities = @($regions | Where-Object { $_.level -eq 1 })
$districts = @($regions | Where-Object { $_.level -eq 2 })
$usableCities = @($cities | Where-Object {
    $candidateCode = $_.code
    ($districts | Where-Object { $_.parent_code -eq $candidateCode } | Measure-Object).Count -gt 0
})
if ($categories.Count -eq 0 -or $usableCities.Count -eq 0 -or $districts.Count -eq 0) {
    throw 'Active categories or administrative regions are missing.'
}

$profiles = @(
    @{ Name = '林夏'; Theme = '汉江晚风散步' },
    @{ Name = '小满'; Theme = '周末咖啡探店' },
    @{ Name = '阿泽'; Theme = '北汉山轻徒步' },
    @{ Name = '安然'; Theme = '弘大摄影漫步' },
    @{ Name = 'Eric'; Theme = '江南桌游之夜' },
    @{ Name = '智妍'; Theme = '韩语口语交换' },
    @{ Name = '可可'; Theme = '圣水洞手作体验' },
    @{ Name = '俊浩'; Theme = '周末羽毛球局' },
    @{ Name = 'Mina'; Theme = '梨泰院世界料理' },
    @{ Name = '浩宇'; Theme = '汝矣岛骑行' },
    @{ Name = 'Sora'; Theme = '独立电影交流' },
    @{ Name = '子涵'; Theme = '首尔美术馆同行' },
    @{ Name = '泰民'; Theme = '清溪川夜跑' },
    @{ Name = 'Nana'; Theme = '甜品烘焙体验' },
    @{ Name = '思远'; Theme = '产品经理交流会' },
    @{ Name = '秀彬'; Theme = '周日城市野餐' },
    @{ Name = 'Leo'; Theme = '新手攀岩体验' },
    @{ Name = '恩熙'; Theme = '汉江读书会' },
    @{ Name = '嘉怡'; Theme = '复古市集寻宝' },
    @{ Name = 'Daniel'; Theme = '周末音乐分享会' }
)

$accounts = [System.Collections.Generic.List[object]]::new()
if (-not [string]::IsNullOrWhiteSpace($ResumeManifest)) {
    $resolvedManifest = Resolve-Path $ResumeManifest
    $savedManifest = Get-Content -LiteralPath $resolvedManifest -Raw | ConvertFrom-Json
    $RunTag = [string]$savedManifest.RunTag
    Write-Host "Resuming demo batch $RunTag..."
    foreach ($savedAccount in $savedManifest.Accounts) {
        $login = Invoke-DamumuApi -Path '/auth/login' -Method POST -Body @{
            email = $savedAccount.Email
            password = $savedAccount.Password
        }
        $profile = $profiles[([int]$savedAccount.Index - 1) % $profiles.Count]
        $accounts.Add([pscustomobject]@{
            Index = [int]$savedAccount.Index
            UserId = [string]$savedAccount.UserId
            Nickname = [string]$savedAccount.Nickname
            Email = [string]$savedAccount.Email
            Password = [string]$savedAccount.Password
            Token = [string]$login.accessToken
            Theme = [string]$profile.Theme
            EventId = [string]$savedAccount.EventId
        })
    }
    $outputPath = [string]$resolvedManifest
} else {
    Write-Host "Registering $UserCount demo members..."
    for ($index = 0; $index -lt $UserCount; $index++) {
        $profile = $profiles[$index % $profiles.Count]
        $sequence = $index + 1
        $email = "demo.$RunTag.$($sequence.ToString('00'))@damumu.local"
        $registration = Invoke-DamumuApi -Path '/auth/register' -Method POST -Body @{
            nickname = "$($profile.Name)$sequence"
            email = $email
            password = $Password
            avatarId = $null
        }
        $accounts.Add([pscustomobject]@{
            Index = $sequence
            UserId = [string]$registration.user.id
            Nickname = [string]$registration.user.nickname
            Email = $email
            Password = $Password
            Token = [string]$registration.accessToken
            Theme = [string]$profile.Theme
            EventId = $null
        })
    }

    Write-Host "Publishing $UserCount demo activities..."
    for ($index = 0; $index -lt $accounts.Count; $index++) {
        $account = $accounts[$index]
        $category = $categories[$index % $categories.Count]
        $city = $usableCities[$index % $usableCities.Count]
        $matchingDistricts = @($districts | Where-Object { $_.parent_code -eq $city.code })
        $district = $matchingDistricts[$index % $matchingDistricts.Count]
        $startsAt = (Get-Date).Date.AddDays(2 + $index).AddHours(10 + ($index % 8))
        $endsAt = $startsAt.AddHours(2)
        $created = Invoke-DamumuApi -Path '/events' -Method POST -Token $account.Token -Body @{
            categoryId = $category.id
            title = "[DEMO $RunTag] $($account.Theme)"
            description = "用于多用户报名、审批、通知和活动群聊测试的模拟活动。组织者：$($account.Nickname)。"
            cityCode = $city.code
            districtCode = $district.code
            startsAt = $startsAt.ToUniversalTime().ToString('o')
            endsAt = $endsAt.ToUniversalTime().ToString('o')
            minParticipants = 2
            capacity = 8
            approvalMode = 'manual'
            visibility = 'public'
            minAge = 18
            maxAge = 60
            priceMin = 0
            priceMax = 20000
            priceCurrency = 'KRW'
            announcement = '这是 DEMO 测试活动，请勿当作真实活动参与。'
            organizerNote = '测试报名审批和群聊成员同步。'
            languageCodes = @('zh-CN', 'ko-KR')
            interestIds = @()
            place = @{
                name = "$($district.name_zh_cn)测试集合点"
                addressPublic = "$($city.name_zh_cn) $($district.name_zh_cn)"
                latitude = $null
                longitude = $null
            }
        }
        $account.EventId = [string]$created.id
    }
}

# Persist credentials before cross-account operations so an interrupted run can
# be resumed or inspected without losing the generated password.
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
[pscustomobject]@{
    RunTag = $RunTag
    ApiBaseUrl = $ApiBaseUrl
    CreatedAt = (Get-Date).ToString('o')
    Status = 'activities_created'
    UserCount = $accounts.Count
    EventCount = ($accounts | Where-Object { -not [string]::IsNullOrWhiteSpace($_.EventId) }).Count
    Accounts = @($accounts | Select-Object Index, UserId, Nickname, Email, Password, EventId)
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $outputPath -Encoding utf8

Write-Host 'Creating cross-account applications and organizer decisions...'
for ($index = 0; $index -lt $accounts.Count; $index++) {
    $organizer = $accounts[$index]
    $approvedApplicant = $accounts[($index + 1) % $accounts.Count]
    $rejectedApplicant = $accounts[($index + 2) % $accounts.Count]
    $pendingApplicant = $accounts[($index + 3) % $accounts.Count]

    $members = @(Invoke-DamumuApi -Path "/events/$($organizer.EventId)/members" -Token $organizer.Token)
    $approvedMember = $members | Where-Object {
        [string]$_.user_id -eq [string]$approvedApplicant.UserId
    } | Select-Object -First 1
    if ($null -eq $approvedMember) {
        Invoke-DamumuApi -Path "/events/$($organizer.EventId)/join" -Method POST `
            -Token $approvedApplicant.Token -Body @{
                partySize = 1
                note = "我是 $($approvedApplicant.Nickname)，申请参加 DEMO 活动。"
                shareContact = $false
            } | Out-Null
        $approvedMember = [pscustomobject]@{ status = 'applied' }
    }
    if ($approvedMember.status -eq 'applied') {
        Invoke-DamumuApi -Path "/events/$($organizer.EventId)/members/$($approvedApplicant.UserId)/approve" `
            -Method POST -Token $organizer.Token -Body @{} | Out-Null
    }

    $rejectedMember = $members | Where-Object {
        [string]$_.user_id -eq [string]$rejectedApplicant.UserId
    } | Select-Object -First 1
    if ($null -eq $rejectedMember) {
        Invoke-DamumuApi -Path "/events/$($organizer.EventId)/join" -Method POST `
            -Token $rejectedApplicant.Token -Body @{
                partySize = 1
                note = "我是 $($rejectedApplicant.Nickname)，用于测试拒绝通知。"
                shareContact = $false
            } | Out-Null
        $rejectedMember = [pscustomobject]@{ status = 'applied' }
    }
    if ($rejectedMember.status -eq 'applied') {
        Invoke-DamumuApi -Path "/events/$($organizer.EventId)/members/$($rejectedApplicant.UserId)/reject" `
            -Method POST -Token $organizer.Token -Body @{ reason = 'DEMO：用于验证申请未通过通知。' } | Out-Null
    }

    $pendingMember = $members | Where-Object {
        [string]$_.user_id -eq [string]$pendingApplicant.UserId
    } | Select-Object -First 1
    if ($null -eq $pendingMember) {
        Invoke-DamumuApi -Path "/events/$($organizer.EventId)/join" -Method POST `
            -Token $pendingApplicant.Token -Body @{
                partySize = 1
                note = "我是 $($pendingApplicant.Nickname)，请在界面中手动审批这条 DEMO 申请。"
                shareContact = $false
            } | Out-Null
    }

    $conversations = @(Invoke-DamumuApi -Path '/conversations' -Token $organizer.Token)
    $eventConversation = $conversations | Where-Object {
        [string]$_.event_id -eq [string]$organizer.EventId
    } | Select-Object -First 1
    if ($null -eq $eventConversation) {
        throw "Event conversation was not created for $($organizer.EventId)."
    }
    $groupMessages = @(Invoke-DamumuApi -Path "/conversations/$($eventConversation.id)/messages" -Token $organizer.Token)
    $organizerMessage = "欢迎加入 $($organizer.Theme)，这是组织者的 DEMO 消息。"
    $applicantMessage = "收到，我是 $($approvedApplicant.Nickname)，群聊功能正常。"
    if ($organizerMessage -notin @($groupMessages | ForEach-Object { $_.body })) {
        Invoke-DamumuApi -Path "/conversations/$($eventConversation.id)/messages" -Method POST `
            -Token $organizer.Token -Body @{ messageType = 'text'; body = $organizerMessage } | Out-Null
    }
    if ($applicantMessage -notin @($groupMessages | ForEach-Object { $_.body })) {
        Invoke-DamumuApi -Path "/conversations/$($eventConversation.id)/messages" -Method POST `
            -Token $approvedApplicant.Token -Body @{ messageType = 'text'; body = $applicantMessage } | Out-Null
    }
}

Write-Host 'Creating direct conversations...'
for ($index = 0; $index -lt $accounts.Count; $index += 2) {
    $first = $accounts[$index]
    $second = $accounts[($index + 1) % $accounts.Count]
    $conversation = Invoke-DamumuApi -Path '/conversations/direct' -Method POST `
        -Token $first.Token -Body @{ otherUserId = $second.UserId }
    $directMessages = @(Invoke-DamumuApi -Path "/conversations/$($conversation.id)/messages" -Token $first.Token)
    $firstMessage = "你好 $($second.Nickname)，这是 DEMO 私信。"
    $secondMessage = "你好 $($first.Nickname)，已经收到。"
    if ($firstMessage -notin @($directMessages | ForEach-Object { $_.body })) {
        Invoke-DamumuApi -Path "/conversations/$($conversation.id)/messages" -Method POST `
            -Token $first.Token -Body @{ messageType = 'text'; body = $firstMessage } | Out-Null
    }
    if ($secondMessage -notin @($directMessages | ForEach-Object { $_.body })) {
        Invoke-DamumuApi -Path "/conversations/$($conversation.id)/messages" -Method POST `
            -Token $second.Token -Body @{ messageType = 'text'; body = $secondMessage } | Out-Null
    }
}

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$manifest = [pscustomobject]@{
    RunTag = $RunTag
    ApiBaseUrl = $ApiBaseUrl
    CreatedAt = (Get-Date).ToString('o')
    Status = 'complete'
    UserCount = $accounts.Count
    EventCount = ($accounts | Where-Object { -not [string]::IsNullOrWhiteSpace($_.EventId) }).Count
    Accounts = @($accounts | Select-Object Index, UserId, Nickname, Email, Password, EventId)
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $outputPath -Encoding utf8

Write-Host "Created $($manifest.UserCount) members and $($manifest.EventCount) activities."
Write-Host 'Each activity has one approved, one rejected, and one pending application plus group-chat messages.'
Write-Host "Credentials manifest: $outputPath"

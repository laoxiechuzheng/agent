# Installs nezha-agent from the fork-owned GitHub repository.
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Error "PowerShell 5 or newer is required"
    exit 1
}

$repository = "laoxiechuzheng/agent"
$installDir = "C:\nezha"
$binaryPath = Join-Path $installDir "nezha-agent.exe"

if ([System.Environment]::Is64BitOperatingSystem) {
    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
        $assetName = "nezha-agent_windows_arm64.zip"
    } else {
        $assetName = "nezha-agent_windows_amd64.zip"
    }
} else {
    $assetName = "nezha-agent_windows_386.zip"
}

if ([string]::IsNullOrWhiteSpace($env:NZ_SERVER)) {
    Write-Error "NZ_SERVER must not be empty"
    exit 1
}
if ([string]::IsNullOrWhiteSpace($env:NZ_CLIENT_SECRET)) {
    Write-Error "NZ_CLIENT_SECRET must not be empty"
    exit 1
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$releaseBase = "https://github.com/$repository/releases/latest/download"
$tempDir = Join-Path $env:TEMP "nezha-agent-install-$PID"
$archivePath = Join-Path $tempDir $assetName
$checksumsPath = Join-Path $tempDir "checksums.txt"

try {
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
    Write-Host "Downloading $assetName from $repository"
    Invoke-WebRequest -Uri "$releaseBase/$assetName" -OutFile $archivePath -UseBasicParsing
    Invoke-WebRequest -Uri "$releaseBase/checksums.txt" -OutFile $checksumsPath -UseBasicParsing

    $checksumLine = Get-Content $checksumsPath | Where-Object {
        $parts = $_ -split "\s+"
        $parts.Length -ge 2 -and $parts[1] -eq $assetName
    } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($checksumLine)) {
        throw "Checksum entry for $assetName was not found"
    }
    $expectedHash = ($checksumLine -split "\s+")[0].ToLowerInvariant()
    $actualHash = (Get-FileHash -Path $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "Checksum verification failed for $assetName"
    }

    if (Test-Path $binaryPath) {
        & $binaryPath service uninstall 2>$null
    }
    New-Item -Path $installDir -ItemType Directory -Force | Out-Null
    $extractDir = Join-Path $tempDir "expanded"
    Expand-Archive -Path $archivePath -DestinationPath $extractDir -Force
    Copy-Item -Path (Join-Path $extractDir "nezha-agent.exe") -Destination $binaryPath -Force

    $configPath = Join-Path $installDir "config.yml"
    if (Test-Path $configPath) {
        $configPath = Join-Path $installDir ("config-{0}-{1}.yml" -f (Get-Date -Format "yyyyMMddHHmmss"), $PID)
    }

    if ([string]::IsNullOrWhiteSpace($env:NZ_TLS)) { $env:NZ_TLS = "false" }
    if ([string]::IsNullOrWhiteSpace($env:NZ_DISABLE_AUTO_UPDATE)) { $env:NZ_DISABLE_AUTO_UPDATE = "false" }
    if ([string]::IsNullOrWhiteSpace($env:NZ_DISABLE_FORCE_UPDATE)) { $env:NZ_DISABLE_FORCE_UPDATE = "false" }
    if ([string]::IsNullOrWhiteSpace($env:NZ_DISABLE_COMMAND_EXECUTE)) { $env:NZ_DISABLE_COMMAND_EXECUTE = "false" }
    if ([string]::IsNullOrWhiteSpace($env:NZ_SKIP_CONNECTION_COUNT)) { $env:NZ_SKIP_CONNECTION_COUNT = "false" }
    if ([string]::IsNullOrWhiteSpace($env:NZ_SKIP_PROCS_COUNT)) { $env:NZ_SKIP_PROCS_COUNT = "false" }
    $env:NZ_UPDATE_REPOSITORY = $repository
    $env:NZ_USE_GITEE_TO_UPGRADE = "false"
    $env:NZ_USE_ATOMGIT_TO_UPGRADE = "false"

    & $binaryPath service -c $configPath install
    if ($LASTEXITCODE -ne 0) {
        throw "nezha-agent service installation failed"
    }
    if (-not (Test-Path $configPath)) {
        throw "Agent installed but configuration was not created at $configPath"
    }

    Write-Host "nezha-agent installed from $repository"
    Write-Host "Agent self-updates are locked to $repository"
} finally {
    if (Test-Path $tempDir) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force
    }
}

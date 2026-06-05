param(
    [Parameter(Mandatory = $true)]
    [string] $NodeVersion,

    [Parameter(Mandatory = $true)]
    [string] $MxcSdkVersion,

    [Parameter(Mandatory = $true)]
    [string] $OpenClawPackage,

    [Parameter(Mandatory = $true)]
    [int] $GatewayPort,

    [Parameter(Mandatory = $true)]
    [string] $OllamaModel,

    [Parameter(Mandatory = $true)]
    [string] $OllamaVersion,

    [Parameter(Mandatory = $true)]
    [string] $GitForWindowsVersion,

    [Parameter(Mandatory = $true)]
    [string] $InstallOllama,

    [Parameter(Mandatory = $true)]
    [string] $DisableControlUiDeviceAuth
)

$ErrorActionPreference = "Stop"

$InstallOllamaEnabled = [System.Convert]::ToBoolean($InstallOllama)
$DisableControlUiDeviceAuthEnabled = [System.Convert]::ToBoolean($DisableControlUiDeviceAuth)

$BootstrapRoot = "C:\bootstrap"
$OpenClawRoot = "C:\openclaw"
$OllamaRoot = "C:\ollama"
$OllamaModelsDir = Join-Path $OllamaRoot "models"
$ConfigDir = Join-Path $OpenClawRoot "config"
$StateDir = Join-Path $ConfigDir "state"
$WorkspaceDir = Join-Path $ConfigDir "workspace"
$LogFile = Join-Path $BootstrapRoot "bootstrap.log"
$ConfigFile = Join-Path $ConfigDir "openclaw.json"
$EnvFile = Join-Path $ConfigDir ".env"
$AccessFile = Join-Path $OpenClawRoot "gateway-access.txt"

function Write-Log {
    param([string] $Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -Path $LogFile -Value $line
    Write-Host $line
}

function Refresh-Path {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

function Set-OpenClawEnvironment {
    $env:OPENCLAW_CONFIG_DIR = $ConfigDir
    $env:OPENCLAW_CONFIG_PATH = $ConfigFile
    $env:OPENCLAW_STATE_DIR = $StateDir
    $env:OPENCLAW_WORKSPACE_DIR = $WorkspaceDir

    [Environment]::SetEnvironmentVariable("OPENCLAW_CONFIG_DIR", $ConfigDir, "Machine")
    [Environment]::SetEnvironmentVariable("OPENCLAW_CONFIG_PATH", $ConfigFile, "Machine")
    [Environment]::SetEnvironmentVariable("OPENCLAW_STATE_DIR", $StateDir, "Machine")
    [Environment]::SetEnvironmentVariable("OPENCLAW_WORKSPACE_DIR", $WorkspaceDir, "Machine")
}

function Get-OrCreateGatewayToken {
    if (Test-Path $EnvFile) {
        $existing = Get-Content $EnvFile | Where-Object { $_ -match '^\s*OPENCLAW_GATEWAY_TOKEN=(.+)$' } | Select-Object -First 1
        if ($existing -match 'OPENCLAW_GATEWAY_TOKEN=(.+)') {
            return $Matches[1].Trim()
        }
    }

    $bytes = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return ([Convert]::ToBase64String($bytes) -replace '[+/=]', '').Substring(0, 32)
}

function Get-PublicIp {
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        try {
            $ip = Invoke-RestMethod `
                -Uri "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2021-02-01&format=text" `
                -Headers @{ Metadata = "true" } `
                -TimeoutSec 5
            if ($ip) { return $ip }
        }
        catch {
            Start-Sleep -Seconds 5
        }
    }
    return "<vm-public-ip>"
}

function Invoke-NpmGlobal {
    param(
        [string] $PackageSpec,
        [switch] $AllowFailure
    )

    Write-Log "npm install -g $PackageSpec"
    npm install -g $PackageSpec 2>&1 | ForEach-Object { Write-Log $_ }
    if ($LASTEXITCODE -ne 0) {
        if ($AllowFailure) {
            Write-Log "WARNING: npm install -g $PackageSpec failed with exit code $LASTEXITCODE"
            return
        }
        throw "npm install -g $PackageSpec failed with exit code $LASTEXITCODE"
    }
}

function Save-RemoteFile {
    param(
        [string] $Uri,
        [string] $Destination,
        [int] $TimeoutSeconds = 3600
    )

    Write-Log "Downloading $Uri"
    $ProgressPreference = "SilentlyContinue"
    if (Test-Path $Destination) {
        Remove-Item -Path $Destination -Force
    }

    try {
        Start-BitsTransfer -Source $Uri -Destination $Destination -TransferType Download -ErrorAction Stop
    }
    catch {
        Write-Log "BITS download failed, falling back to Invoke-WebRequest: $($_.Exception.Message)"
        Invoke-WebRequest -Uri $Uri -OutFile $Destination -TimeoutSec $TimeoutSeconds -UseBasicParsing
    }

    if (-not (Test-Path $Destination)) {
        throw "Download did not create file: $Destination"
    }

    $sizeMb = [math]::Round((Get-Item $Destination).Length / 1MB, 2)
    Write-Log "Download complete: $Destination ($sizeMb MB)"
}

function Wait-OllamaReady {
    param([int] $TimeoutSeconds = 300)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/tags" -TimeoutSec 5 | Out-Null
            return $true
        }
        catch {
            Start-Sleep -Seconds 5
        }
    }
    return $false
}

function Resolve-OllamaExecutable {
    param([string] $SearchRoot)

    $candidate = Join-Path $SearchRoot "ollama.exe"
    if (Test-Path $candidate) {
        return $candidate
    }

    $nested = Get-ChildItem -Path $SearchRoot -Filter "ollama.exe" -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($nested) {
        return $nested.FullName
    }

    throw "ollama.exe not found under $SearchRoot after install"
}

function Start-OllamaModelPull {
    param(
        [string] $Model,
        [string] $OllamaExe
    )

    $pullScript = Join-Path $BootstrapRoot "pull-ollama-model.ps1"
    $pullLog = Join-Path $BootstrapRoot "ollama-pull.log"
    @"
param(
    [string] `$Model,
    [string] `$OllamaExe,
    [string] `$LogFile
)

`$ErrorActionPreference = 'Continue'
"`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Starting Ollama pull for `$Model" | Out-File -FilePath `$LogFile -Encoding UTF8
& `$OllamaExe pull `$Model 2>&1 | Tee-Object -FilePath `$LogFile -Append
if (`$LASTEXITCODE -ne 0) {
    "`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Ollama pull failed with exit code `$LASTEXITCODE" | Out-File -FilePath `$LogFile -Append
    exit `$LASTEXITCODE
}
"`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Ollama pull finished: `$Model" | Out-File -FilePath `$LogFile -Append
exit 0
"@ | Set-Content -Path $pullScript -Encoding UTF8

    $taskName = "OllamaPullModel"
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    $action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$pullScript`" -Model `"$Model`" -OllamaExe `"$OllamaExe`" -LogFile `"$pullLog`""
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1)
    $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName
    Write-Log "Scheduled background Ollama model pull: $Model (log: $pullLog)"
}

function Install-Ollama {
    param(
        [string] $Model,
        [string] $Version
    )

    Write-Log "Installing Ollama to $OllamaRoot (SYSTEM-friendly layout)"
    New-Item -ItemType Directory -Force -Path $OllamaRoot | Out-Null
    New-Item -ItemType Directory -Force -Path $OllamaModelsDir | Out-Null

    [Environment]::SetEnvironmentVariable("OLLAMA_MODELS", $OllamaModelsDir, "Machine")
    $env:OLLAMA_MODELS = $OllamaModelsDir

    $ollamaExe = Join-Path $OllamaRoot "ollama.exe"
    if (-not (Test-Path $ollamaExe)) {
        $zipPath = Join-Path $BootstrapRoot "ollama-windows-amd64.zip"
        $zipUrl = "https://github.com/ollama/ollama/releases/download/v$Version/ollama-windows-amd64.zip"
        Save-RemoteFile -Uri $zipUrl -Destination $zipPath
        $extractDir = Join-Path $BootstrapRoot "ollama-extract"
        if (Test-Path $extractDir) {
            Remove-Item -Path $extractDir -Recurse -Force
        }
        New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
        Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
        $resolvedExe = Resolve-OllamaExecutable -SearchRoot $extractDir
        Copy-Item -Path $resolvedExe -Destination $ollamaExe -Force
        $ollamaDir = Split-Path $resolvedExe -Parent
        Get-ChildItem -Path $ollamaDir -File | ForEach-Object {
            $target = Join-Path $OllamaRoot $_.Name
            if ($_.FullName -ne $ollamaExe -and -not (Test-Path $target)) {
                Copy-Item -Path $_.FullName -Destination $target -Force
            }
        }
    }

    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($machinePath -notlike "*$OllamaRoot*") {
        [Environment]::SetEnvironmentVariable("Path", "$machinePath;$OllamaRoot", "Machine")
    }
    Refresh-Path

    $taskName = "OllamaServe"
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    $action = New-ScheduledTaskAction -Execute $ollamaExe -Argument "serve"
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null

    Start-ScheduledTask -TaskName $taskName
    Start-Sleep -Seconds 5

    if (-not (Wait-OllamaReady)) {
        throw "Ollama API did not become ready on http://127.0.0.1:11434"
    }

    Write-Log "Ollama serve is ready; deferring model pull to background task"
    Start-OllamaModelPull -Model $Model -OllamaExe $ollamaExe
}

New-Item -ItemType Directory -Force -Path $BootstrapRoot | Out-Null
New-Item -ItemType Directory -Force -Path $OpenClawRoot | Out-Null
New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
New-Item -ItemType Directory -Force -Path $WorkspaceDir | Out-Null

Write-Log "Starting MXC + OpenClaw + Ollama bootstrap (gateway on lan)"
Write-Log "Pinned versions: Node v$NodeVersion, MXC SDK $MxcSdkVersion, OpenClaw $OpenClawPackage, Ollama v$OllamaVersion, Git $GitForWindowsVersion"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Log "Installing Git for Windows $GitForWindowsVersion"
    $gitTag = "v$GitForWindowsVersion"
    $gitBaseVersion = ($GitForWindowsVersion -split '\.windows\.')[0]
    $gitInstaller = Join-Path $BootstrapRoot "Git-$gitBaseVersion-64-bit.exe"
    $gitUrl = "https://github.com/git-for-windows/git/releases/download/$gitTag/Git-$gitBaseVersion-64-bit.exe"
    Invoke-WebRequest -Uri $gitUrl -OutFile $gitInstaller
    Start-Process -FilePath $gitInstaller -ArgumentList "/VERYSILENT /NORESTART" -Wait
    Refresh-Path
    Write-Log "Git install finished"
}
else {
    Write-Log "Git already installed"
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Log "Installing Node.js v$NodeVersion from nodejs.org"
    $nodeMsi = "node-v$NodeVersion-x64.msi"
    $nodeUrl = "https://nodejs.org/dist/v$NodeVersion/$nodeMsi"
    $nodeInstaller = Join-Path $BootstrapRoot $nodeMsi
    Invoke-WebRequest -Uri $nodeUrl -OutFile $nodeInstaller
    Start-Process msiexec.exe -ArgumentList "/i `"$nodeInstaller`" /qn" -Wait
    Refresh-Path
}
else {
    Write-Log "Node.js already installed: $(node --version)"
}

Write-Log "Node version: $(node --version)"
Write-Log "npm version: $(npm --version)"

Invoke-NpmGlobal -PackageSpec "@microsoft/mxc-sdk@$MxcSdkVersion" -AllowFailure

Write-Log "Installing OpenClaw package: $OpenClawPackage"
Invoke-NpmGlobal -PackageSpec $OpenClawPackage
Refresh-Path

if ($InstallOllamaEnabled) {
    Install-Ollama -Model $OllamaModel -Version $OllamaVersion
}

Set-OpenClawEnvironment

$gatewayToken = Get-OrCreateGatewayToken
$publicIp = Get-PublicIp
if ($publicIp -eq "<vm-public-ip>") {
    Write-Log "Public IP metadata unavailable on first attempt; retrying before writing config"
    Start-Sleep -Seconds 10
    $publicIp = Get-PublicIp
}
Write-Log "Gateway token ready (also written to $AccessFile)"

$allowedOrigins = @(
    "http://localhost:$GatewayPort",
    "http://127.0.0.1:$GatewayPort"
)
if ($publicIp -ne "<vm-public-ip>") {
    $allowedOrigins += "http://${publicIp}:$GatewayPort"
    Write-Log "Control UI allowedOrigins includes public IP: http://${publicIp}:$GatewayPort"
}
else {
    Write-Log "WARNING: Public IP unavailable; Control UI may reject remote browser origins until openclaw.json is updated"
}

$controlUi = @{
    allowedOrigins    = $allowedOrigins
    allowInsecureAuth = $true
}
if ($DisableControlUiDeviceAuthEnabled) {
    $controlUi.dangerouslyDisableDeviceAuth = $true
    Write-Log "Control UI device auth disabled for plain HTTP lab access (security downgrade)"
}

$config = @{
    gateway = @{
        mode      = "local"
        port      = $GatewayPort
        bind      = "lan"
        auth      = @{ mode = "token" }
        reload    = @{ mode = "hybrid" }
        controlUi = $controlUi
    }
    agents = @{
        defaults = @{
            workspace = $WorkspaceDir
        }
    }
}

if ($InstallOllamaEnabled) {
    $config.models = @{
        providers = @{
            ollama = @{
                baseUrl        = "http://127.0.0.1:11434"
                apiKey         = "ollama-local"
                api            = "ollama"
                timeoutSeconds = 300
                models         = @(
                    @{
                        id     = $OllamaModel
                        name   = $OllamaModel
                        params = @{ keep_alive = "15m" }
                    }
                )
            }
        }
    }
    $config.agents.defaults.model = @{
        primary = "ollama/$OllamaModel"
    }
}

$config | ConvertTo-Json -Depth 8 | Set-Content -Path $ConfigFile -Encoding UTF8

$envLines = @(
    "OPENCLAW_GATEWAY_TOKEN=$gatewayToken",
    "OPENCLAW_GATEWAY_PORT=$GatewayPort"
)

if ($InstallOllamaEnabled) {
    $envLines += "OLLAMA_API_KEY=ollama-local"
}
else {
    $envLines += "# Optional cloud provider keys if not using Ollama:"
    $envLines += "# OPENAI_API_KEY=sk-..."
    $envLines += "# ANTHROPIC_API_KEY=sk-ant-..."
}

if (Test-Path $EnvFile) {
    $preserved = Get-Content $EnvFile | Where-Object {
        $_ -notmatch '^\s*OPENCLAW_GATEWAY_TOKEN=' -and
        $_ -notmatch '^\s*OPENCLAW_GATEWAY_PORT=' -and
        $_ -notmatch '^\s*OLLAMA_API_KEY=' -and
        $_.Trim().Length -gt 0
    }
    $envLines += $preserved
}

$envLines | Set-Content -Path $EnvFile -Encoding UTF8
[Environment]::SetEnvironmentVariable("OPENCLAW_GATEWAY_TOKEN", $gatewayToken, "Machine")
if ($InstallOllamaEnabled) {
    [Environment]::SetEnvironmentVariable("OLLAMA_API_KEY", "ollama-local", "Machine")
}

$modelLine = if ($InstallOllamaEnabled) { "Ollama model: ollama/$OllamaModel (local, http://127.0.0.1:11434)" } else { "Model: configure cloud provider in $EnvFile" }

@(
    "OpenClaw gateway access"
    "======================="
    ""
    "Control UI:  http://${publicIp}:$GatewayPort"
    "WebSocket:   ws://${publicIp}:$GatewayPort"
    ""
    "Gateway token (paste in Control UI Connect):"
    $gatewayToken
    ""
    $modelLine
    ""
    "Config dir:  $ConfigDir"
    "Env file:    $EnvFile"
    ""
    "1. Open the Control UI URL above from your browser and paste the token"
    "2. If using Ollama, wait for model pull: Get-Content C:\bootstrap\ollama-pull.log -Tail 20"
    "3. Restart gateway if needed: powershell -File C:\openclaw\start-gateway.ps1 -Restart"
    "4. Configure MXC processcontainer backend per @microsoft/mxc-sdk docs"
    ""
    "Note: Ollama listens on localhost only (port 11434 is not exposed in Azure NSG)."
) | Set-Content -Path $AccessFile -Encoding UTF8

$acl = Get-Acl $AccessFile
$acl.SetAccessRuleProtection($true, $false)
$adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "Administrators", "FullControl", "Allow"
)
$acl.SetAccessRule($adminRule)
Set-Acl -Path $AccessFile -AclObject $acl

$StartGatewayScript = Join-Path $OpenClawRoot "start-gateway.ps1"
@'
param(
    [switch] $Restart,
    [string] $ConfigDir = "C:\openclaw\config",
    [int] $Port = 18789
)

$ErrorActionPreference = "Stop"

$env:OPENCLAW_CONFIG_DIR = $ConfigDir
$env:OPENCLAW_CONFIG_PATH = Join-Path $ConfigDir "openclaw.json"
$env:OPENCLAW_STATE_DIR = Join-Path $ConfigDir "state"
$env:OPENCLAW_WORKSPACE_DIR = Join-Path $ConfigDir "workspace"

$envFile = Join-Path $ConfigDir ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
            $name = $Matches[1].Trim()
            $value = $Matches[2].Trim()
            Set-Item -Path "Env:$name" -Value $value
        }
    }
}

if (-not (Get-Command openclaw -ErrorAction SilentlyContinue)) {
    throw "OpenClaw CLI not found on PATH."
}

if ($Restart) {
    openclaw gateway restart
    openclaw gateway status
    exit 0
}

openclaw gateway --bind lan --port $Port
'@ | Set-Content -Path $StartGatewayScript -Encoding UTF8

Write-Log "Opening Windows Firewall for OpenClaw gateway port $GatewayPort"
$firewallRuleName = "OpenClaw Gateway TCP $GatewayPort"
if (-not (Get-NetFirewallRule -DisplayName $firewallRuleName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $firewallRuleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $GatewayPort | Out-Null
}
Write-Log "Windows Firewall rule ensured: $firewallRuleName"

Write-Log "Removing legacy OpenClawAgent scheduled task if present"
Unregister-ScheduledTask -TaskName "OpenClawAgent" -Confirm:$false -ErrorAction SilentlyContinue

Write-Log "Installing OpenClaw gateway scheduled task"
Set-OpenClawEnvironment

if ($publicIp -eq "<vm-public-ip>") {
    $publicIp = Get-PublicIp
}
if ($publicIp -ne "<vm-public-ip>") {
    $origin = "http://${publicIp}:$GatewayPort"
    $configObj = Get-Content $ConfigFile -Raw | ConvertFrom-Json
    $origins = [System.Collections.Generic.List[string]]@($configObj.gateway.controlUi.allowedOrigins)
    if ($origins -notcontains $origin) {
        [void]$origins.Add($origin)
        $configObj.gateway.controlUi.allowedOrigins = $origins.ToArray()
        $configObj | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigFile -Encoding UTF8
        Write-Log "Patched allowedOrigins with public IP before gateway start: $origin"
    }
}

$gatewayTaskName = "OpenClawGateway"
Unregister-ScheduledTask -TaskName $gatewayTaskName -Confirm:$false -ErrorAction SilentlyContinue
$gatewayAction = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$StartGatewayScript`" -Port $GatewayPort"
$startupTrigger = New-ScheduledTaskTrigger -AtStartup
$nowTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(15)
$gatewayPrincipal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask `
    -TaskName $gatewayTaskName `
    -Action $gatewayAction `
    -Trigger @($startupTrigger, $nowTrigger) `
    -Principal $gatewayPrincipal `
    -Force | Out-Null

Start-Sleep -Seconds 20
try {
    $status = openclaw gateway status 2>&1 | Out-String
    Write-Log $status.Trim()
}
catch {
    Write-Log "Gateway status check: $($_.Exception.Message)"
}

$Readme = Join-Path $OpenClawRoot "README.txt"
@(
    "OpenClaw + MXC + Ollama VM bootstrap complete."
    ""
    "Gateway URL and token: C:\openclaw\gateway-access.txt"
    "Ollama models dir:     C:\ollama\models"
    "Restart gateway:       powershell -File C:\openclaw\start-gateway.ps1 -Restart"
    ""
    "Note: MXC is alpha preview; do not treat profiles as security boundaries."
) | Set-Content -Path $Readme -Encoding UTF8

Write-Log "Enabling Windows features for WSL2 and Hyper-V (best-effort; may require reboot)"
$features = @(
    "Microsoft-Windows-Subsystem-Linux",
    "VirtualMachinePlatform",
    "Microsoft-Hyper-V-All"
)

foreach ($feature in $features) {
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart | Out-Null
        Write-Log "Enabled feature: $feature"
    }
    catch {
        Write-Log "Feature $feature may require reboot or is already enabled: $($_.Exception.Message)"
    }
}

Write-Log "Bootstrap finished. Reboot recommended for WSL2/Hyper-V features."
exit 0

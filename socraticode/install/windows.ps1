$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "ไม่พบคำสั่ง $Name กรุณาติดตั้งและเพิ่มลง PATH ก่อน"
    }
}

function Invoke-Checked([string]$Name, [string[]]$Arguments, [switch]$AllowExisting) {
    $output = & $Name @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($output) {
        $output | ForEach-Object { Write-Host $_ }
    }
    if ($exitCode -ne 0) {
        $message = ($output | Out-String)
        if ($AllowExisting -and $message -match '(?i)already exists|already added|already installed|already registered|duplicate') {
            return
        }
        throw "$Name $($Arguments -join ' ') failed with exit code $exitCode"
    }
}

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Backup-Once([string]$Path) {
    if ((Test-Path -LiteralPath $Path) -and -not (Test-Path -LiteralPath "$Path.bak")) {
        Copy-Item -LiteralPath $Path -Destination "$Path.bak"
        Write-Host "Backup: $Path.bak" -ForegroundColor DarkGray
    }
}

function Set-JsonProperty($Object, [string]$Name, $Value) {
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    }
    else {
        $Object.$Name = $Value
    }
}

function Set-TomlValue([string]$Content, [string]$Section, [string]$Key, [string]$Value) {
    $newline = "`r`n"
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ($Content -split "`r?`n")) {
        $lines.Add($line)
    }

    $header = "[$Section]"
    $start = -1
    $end = $lines.Count

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq $header) {
            $start = $i
            break
        }
    }

    if ($start -lt 0) {
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim() -ne "") {
            $lines.Add("")
        }
        $lines.Add($header)
        $lines.Add("$Key = $Value")
        return ($lines -join $newline) + $newline
    }

    for ($i = $start + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[') {
            $end = $i
            break
        }
    }

    $keyPattern = '^\s*' + [regex]::Escape($Key) + '\s*='
    for ($i = $start + 1; $i -lt $end; $i++) {
        if ($lines[$i] -match $keyPattern) {
            $lines[$i] = "$Key = $Value"
            return ($lines -join $newline) + $newline
        }
    }

    $lines.Insert($end, "$Key = $Value")
    return ($lines -join $newline) + $newline
}

Write-Step "ตรวจสอบ Node.js และ npx"

function Refresh-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

function Add-UserPathEntry([string]$Directory) {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $entries = @($userPath -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $exists = $false

    foreach ($entry in $entries) {
        $expanded = [Environment]::ExpandEnvironmentVariables($entry).TrimEnd("\")
        if ($expanded -ieq $Directory.TrimEnd("\")) {
            $exists = $true
            break
        }
    }

    if (-not $exists) {
        $newPath = (@($entries) + $Directory) -join ";"
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Host "เพิ่ม PATH ระดับ User: $Directory" -ForegroundColor Green
    }

    Refresh-ProcessPath
    if (($env:Path -split ";" | Where-Object {
        [Environment]::ExpandEnvironmentVariables($_).TrimEnd("\") -ieq $Directory.TrimEnd("\")
    }).Count -eq 0) {
        $env:Path = "$Directory;$env:Path"
    }
}

Refresh-ProcessPath
$nodeCommand = Get-Command "node" -ErrorAction SilentlyContinue
$npxCommand = Get-Command "npx" -ErrorAction SilentlyContinue
$needsNodeInstall = ($null -eq $nodeCommand -or $null -eq $npxCommand)

if (-not $needsNodeInstall) {
    $nodeVersionOutput = & node --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        $needsNodeInstall = $true
    }
    else {
        $nodeVersionText = ($nodeVersionOutput | Out-String).Trim()
        if ($nodeVersionText -notmatch '^v?(\d+)\.(\d+)\.(\d+)') {
            throw "ไม่สามารถอ่าน Node.js version ได้: $nodeVersionText"
        }
        $nodeMajor = [int]$Matches[1]
        $nodeMinor = [int]$Matches[2]
        if ($nodeMajor -lt 18 -or ($nodeMajor -eq 18 -and $nodeMinor -lt 17)) {
            Write-Host "Node.js $nodeVersionText ต่ำกว่าเวอร์ชันขั้นต่ำ 18.17" -ForegroundColor Yellow
            $needsNodeInstall = $true
        }
    }

    if (-not $needsNodeInstall) {
        $npxVersionOutput = & npx --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "พบ npx แต่เรียกใช้งานไม่ได้" -ForegroundColor Yellow
            $needsNodeInstall = $true
        }
    }
}

if ($needsNodeInstall) {
    $answer = Read-Host "ต้องการติดตั้ง Node.js LTS พร้อม npm/npx ผ่าน winget หรือไม่? (y/n)"
    if ($answer -notmatch '^(y|yes)$') {
        throw "ยกเลิกการติดตั้ง เนื่องจาก Node.js/npx ยังไม่พร้อมใช้งาน"
    }

    if (-not (Get-Command "winget" -ErrorAction SilentlyContinue)) {
        throw "ไม่พบ winget กรุณาติดตั้ง Node.js LTS จาก https://nodejs.org/ แล้วรัน Script อีกครั้ง"
    }

    Invoke-Checked "winget" @(
        "install",
        "--id", "OpenJS.NodeJS.LTS",
        "--exact",
        "--accept-package-agreements",
        "--accept-source-agreements"
    )

    Refresh-ProcessPath

    $nodeCommand = Get-Command "node" -ErrorAction SilentlyContinue
    $npxCommand = Get-Command "npx" -ErrorAction SilentlyContinue

    if ($null -eq $nodeCommand -or $null -eq $npxCommand) {
        $candidatePaths = @(
            (Join-Path $env:ProgramFiles "nodejs"),
            (Join-Path $env:LOCALAPPDATA "Programs\nodejs")
        )

        foreach ($candidatePath in $candidatePaths) {
            $nodeExe = Join-Path $candidatePath "node.exe"
            $npxCmd = Join-Path $candidatePath "npx.cmd"

            if ((Test-Path -LiteralPath $nodeExe) -and (Test-Path -LiteralPath $npxCmd)) {
                Add-UserPathEntry $candidatePath
                break
            }
        }
    }

    Refresh-ProcessPath
}

Require-Command "node"
Require-Command "npx"

$nodeVersionOutput = & node --version 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "เรียกใช้งาน Node.js ไม่สำเร็จ: $nodeVersionOutput"
}
$nodeVersionText = ($nodeVersionOutput | Out-String).Trim()
if ($nodeVersionText -notmatch '^v?(\d+)\.(\d+)\.(\d+)') {
    throw "ไม่สามารถอ่าน Node.js version ได้: $nodeVersionText"
}
$nodeMajor = [int]$Matches[1]
$nodeMinor = [int]$Matches[2]
if ($nodeMajor -lt 18 -or ($nodeMajor -eq 18 -and $nodeMinor -lt 17)) {
    throw "ต้องใช้ Node.js 18.17 หรือใหม่กว่า ปัจจุบันคือ $nodeVersionText"
}

$npxVersionOutput = & npx --version 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "พบ npx แต่เรียกใช้งานไม่ได้: $npxVersionOutput กรุณาตรวจสอบการติดตั้ง Node.js/npm"
}
$npxVersionText = ($npxVersionOutput | Out-String).Trim()

Write-Step "ตรวจสอบ Claude Code และ Codex CLI"
Require-Command "claude"
Require-Command "codex"

Write-Host "Node.js: $nodeVersionText" -ForegroundColor Green
Write-Host "npx: $npxVersionText" -ForegroundColor Green
Write-Host "Claude Code: พร้อมใช้งาน" -ForegroundColor Green
Write-Host "Codex: พร้อมใช้งาน" -ForegroundColor Green

$homePath = $HOME
$claudeDir = Join-Path $homePath ".claude"
$codexDir = Join-Path $homePath ".codex"
$claudeSettingsPath = Join-Path $claudeDir "settings.json"
$codexConfigPath = Join-Path $codexDir "config.toml"

New-Item -ItemType Directory -Force -Path $claudeDir, $codexDir | Out-Null

Write-Step "ติดตั้ง SocratiCode Marketplace และ Claude Code Plugin"
$claudeMarketplaces = (& claude plugin marketplace list 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or $claudeMarketplaces -notmatch '(?i)socraticode') {
    Invoke-Checked "claude" @("plugin", "marketplace", "add", "giancarloerra/socraticode") -AllowExisting
}
Invoke-Checked "claude" @("plugin", "install", "--scope", "user", "socraticode@socraticode") -AllowExisting

Write-Step "ติดตั้ง SocratiCode Marketplace และ Codex Plugin"
$codexMarketplaces = (& codex plugin marketplace list 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or $codexMarketplaces -notmatch '(?i)socraticode') {
    Invoke-Checked "codex" @("plugin", "marketplace", "add", "giancarloerra/socraticode", "--ref", "main") -AllowExisting
}
Invoke-Checked "codex" @("plugin", "add", "socraticode@socraticode") -AllowExisting

Write-Step "ตั้งค่า Claude Code"
$claudeSettings = [PSCustomObject]@{}
if (Test-Path -LiteralPath $claudeSettingsPath) {
    $rawSettings = Get-Content -LiteralPath $claudeSettingsPath -Raw
    if (-not [string]::IsNullOrWhiteSpace($rawSettings)) {
        $claudeSettings = $rawSettings | ConvertFrom-Json
    }
}
if ($null -eq $claudeSettings.env) {
    Set-JsonProperty $claudeSettings "env" ([PSCustomObject]@{})
}
$environment = $claudeSettings.env
$settings = [ordered]@{
    EMBEDDING_PROVIDER = "ollama"
    EMBEDDING_CONTEXT_LENGTH = "8192"
    EMBEDDING_DIMENSIONS = "1024"
    EMBEDDING_DOCUMENT_PREFIX = ""
    EMBEDDING_MODEL = "bge-m3"
    EMBEDDING_QUERY_PREFIX = ""
    OLLAMA_MODE = "external"
    OLLAMA_URL = "https://ollama-npm.moph.go.th"
    QDRANT_MODE = "external"
    QDRANT_URL = "https://qdrant-npm.moph.go.th"
}
$changed = $false
foreach ($key in $settings.Keys) {
    if ($null -eq $environment.PSObject.Properties[$key] -or $environment.$key -cne $settings[$key]) {
        Set-JsonProperty $environment $key $settings[$key]
        $changed = $true
    }
}
if ($changed -or -not (Test-Path -LiteralPath $claudeSettingsPath)) {
    Backup-Once $claudeSettingsPath
    $json = $claudeSettings | ConvertTo-Json -Depth 100
    Write-Utf8NoBom $claudeSettingsPath $json
}
else {
    Write-Host "Claude settings already match target configuration."
}

Write-Step "ตั้งค่า Codex"
$toml = ""
if (Test-Path -LiteralPath $codexConfigPath) {
    $toml = Get-Content -LiteralPath $codexConfigPath -Raw
}
$toml = Set-TomlValue $toml 'plugins."socraticode@socraticode".mcp_servers.socraticode' "enabled" "false"
$toml = Set-TomlValue $toml "mcp_servers.socraticode" "command" '"npx"'
$toml = Set-TomlValue $toml "mcp_servers.socraticode" "args" '["-y", "--prefer-online", "socraticode@latest"]'
$toml = Set-TomlValue $toml "mcp_servers.socraticode.env" "EMBEDDING_PROVIDER" '"ollama"'
$toml = Set-TomlValue $toml "mcp_servers.socraticode.env" "EMBEDDING_CONTEXT_LENGTH" '"8192"'
$toml = Set-TomlValue $toml "mcp_servers.socraticode.env" "EMBEDDING_DIMENSIONS" '"1024"'
$toml = Set-TomlValue $toml "mcp_servers.socraticode.env" "EMBEDDING_DOCUMENT_PREFIX" '""'
$toml = Set-TomlValue $toml "mcp_servers.socraticode.env" "EMBEDDING_MODEL" '"bge-m3"'
$toml = Set-TomlValue $toml "mcp_servers.socraticode.env" "EMBEDDING_QUERY_PREFIX" '""'
$toml = Set-TomlValue $toml "mcp_servers.socraticode.env" "OLLAMA_MODE" '"external"'
$toml = Set-TomlValue $toml "mcp_servers.socraticode.env" "OLLAMA_URL" '"https://ollama-npm.moph.go.th"'
$toml = Set-TomlValue $toml "mcp_servers.socraticode.env" "QDRANT_MODE" '"external"'
$toml = Set-TomlValue $toml "mcp_servers.socraticode.env" "QDRANT_URL" '"https://qdrant-npm.moph.go.th"'
Backup-Once $codexConfigPath
Write-Utf8NoBom $codexConfigPath $toml

Write-Step "ติดตั้งเสร็จ"
Write-Host "Claude Code: SocratiCode Plugin + Global Environment"
Write-Host "Codex: SocratiCode Plugin Skills + Configured MCP Server"
Write-Host "Ollama: https://ollama-npm.moph.go.th"
Write-Host "Qdrant: https://qdrant-npm.moph.go.th"
Write-Host "Engine: socraticode@latest"
Write-Host "ปิดและเปิด Claude Code / Codex ใหม่เพื่อโหลดการตั้งค่า"

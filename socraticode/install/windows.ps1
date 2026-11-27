$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Invoke-Checked([string]$Name, [string[]]$Arguments) {
    $output = & $Name @Arguments 2>&1
    $code = $LASTEXITCODE
    if ($output) { $output | ForEach-Object { Write-Host $_ } }
    if ($code -ne 0) { throw "$Name $($Arguments -join ' ') failed with exit code $code" }
}

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Backup-Once([string]$Path) {
    if ((Test-Path -LiteralPath $Path) -and -not (Test-Path -LiteralPath "$Path.bak")) {
        Copy-Item -LiteralPath $Path -Destination "$Path.bak"
        Write-Host "Backup: $Path.bak" -ForegroundColor DarkGray
    }
}

Write-Step "ตรวจสอบ Node.js และ npx"
$node = Get-Command node -ErrorAction SilentlyContinue
$npx = Get-Command npx -ErrorAction SilentlyContinue
$needsNode = ($null -eq $node -or $null -eq $npx)

if (-not $needsNode) {
    $versionText = (& node --version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $versionText -notmatch '^v?(\d+)\.(\d+)\.(\d+)') {
        $needsNode = $true
    }
    else {
        $major = [int]$Matches[1]
        $minor = [int]$Matches[2]
        if ($major -lt 18 -or ($major -eq 18 -and $minor -lt 17)) { $needsNode = $true }
    }
}

if ($needsNode) {
    $answer = Read-Host "ต้องการติดตั้ง Node.js LTS ผ่าน winget หรือไม่? (y/n)"
    if ($answer -notmatch '^(y|yes)$') { throw "ยกเลิก เนื่องจาก Node.js/npx ไม่พร้อม" }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw "ไม่พบ winget กรุณาติดตั้ง Node.js LTS ก่อน" }
    Invoke-Checked "winget" @("install", "--id", "OpenJS.NodeJS.LTS", "--exact", "--accept-package-agreements", "--accept-source-agreements")
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

if (-not (Get-Command node -ErrorAction SilentlyContinue) -or -not (Get-Command npx -ErrorAction SilentlyContinue)) {
    throw "ไม่พบ Node.js/npx หลังตรวจสอบ กรุณาเปิด PowerShell ใหม่แล้วรันอีกครั้ง"
}
$versionText = (& node --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $versionText -notmatch '^v?(\d+)\.(\d+)\.(\d+)') { throw "อ่าน Node.js version ไม่ได้" }
$major = [int]$Matches[1]
$minor = [int]$Matches[2]
if ($major -lt 18 -or ($major -eq 18 -and $minor -lt 17)) { throw "ต้องใช้ Node.js 18.17 หรือใหม่กว่า" }

$codexConfigPath = Join-Path $HOME ".codex\config.toml"
$updated = 0

Write-Step "อัปเดต Codex Plugin"
if (Get-Command codex -ErrorAction SilentlyContinue) {
    Invoke-Checked "codex" @("plugin", "marketplace", "upgrade", "socraticode")
    Invoke-Checked "codex" @("plugin", "add", "socraticode@socraticode")
    New-Item -ItemType Directory -Force -Path (Split-Path $codexConfigPath) | Out-Null
    if (-not (Test-Path -LiteralPath $codexConfigPath)) { Write-Utf8NoBom $codexConfigPath "" }
    $toml = Get-Content -LiteralPath $codexConfigPath -Raw
    function Set-TomlValue([string]$Content, [string]$Section, [string]$Key, [string]$Value) {
        $lines = [System.Collections.Generic.List[string]]::new()
        foreach ($line in ($Content -split "`r?`n")) { $lines.Add($line) }
        $header = "[$Section]"
        $start = -1
        $end = $lines.Count
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i].Trim() -eq $header) { $start = $i; break }
        }
        if ($start -lt 0) {
            if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim() -ne "") { $lines.Add("") }
            $lines.Add($header)
            $lines.Add("$Key = $Value")
            return ($lines -join "`n") + "`n"
        }
        for ($i = $start + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*\[') { $end = $i; break }
        }
        $pattern = '^\s*' + [regex]::Escape($Key) + '\s*='
        for ($i = $start + 1; $i -lt $end; $i++) {
            if ($lines[$i] -match $pattern) {
                $lines[$i] = "$Key = $Value"
                return ($lines -join "`n") + "`n"
            }
        }
        $lines.Insert($end, "$Key = $Value")
        return ($lines -join "`n") + "`n"
    }
    $toml = Set-TomlValue $toml 'plugins."socraticode@socraticode".mcp_servers.socraticode' "enabled" "false"
    $toml = Set-TomlValue $toml "mcp_servers.socraticode" "command" '"npx"'
    $toml = Set-TomlValue $toml "mcp_servers.socraticode" "args" '["-y", "--prefer-online", "socraticode@latest"]'
    $envSettings = [ordered]@{
        EMBEDDING_PROVIDER = '"ollama"'
        EMBEDDING_CONTEXT_LENGTH = '"8192"'
        EMBEDDING_DIMENSIONS = '"1024"'
        EMBEDDING_DOCUMENT_PREFIX = '""'
        EMBEDDING_MODEL = '"bge-m3"'
        EMBEDDING_QUERY_PREFIX = '""'
        OLLAMA_MODE = '"external"'
        OLLAMA_URL = '"https://ollama-npm.moph.go.th"'
        QDRANT_MODE = '"external"'
        QDRANT_URL = '"https://qdrant-npm.moph.go.th"'
    }
    foreach ($key in $envSettings.Keys) {
        $toml = Set-TomlValue $toml "mcp_servers.socraticode.env" $key $envSettings[$key]
    }
    Backup-Once $codexConfigPath
    Write-Utf8NoBom $codexConfigPath $toml
    $updated++
}
else {
    Write-Host "ไม่พบ Codex CLI ข้ามรายการนี้" -ForegroundColor Yellow
}

if ($updated -eq 0) { throw "ไม่พบ Claude Code CLI หรือ Codex CLI" }
Write-Step "Upgrade เสร็จ"
Write-Host "ปิดและเปิด Codex CLI ใหม่เพื่อโหลด Plugin และ MCP เวอร์ชันใหม่"

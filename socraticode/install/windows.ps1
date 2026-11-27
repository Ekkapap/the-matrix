$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Invoke-Checked([string]$Name, [string[]]$Arguments) {
    $ErrorActionPreference = "Continue"
    $output = & $Name @Arguments 2>&1
    $code = $LASTEXITCODE
    if ($output) { $output | ForEach-Object { Write-Host $_ } }
    if ($code -ne 0) { throw "$Name $($Arguments -join ' ') failed with exit code $code" }
}

function Get-CommandText([string]$Name, [string[]]$Arguments) {
    $ErrorActionPreference = "Continue"
    return (& $Name @Arguments 2>&1 | Out-String)
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

$marketplaceRepo = "giancarloerra/socraticode"
$marketplaceName = "socraticode"
$pluginId = "socraticode@socraticode"
$remoteSettings = [ordered]@{
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
$env:SOCRATICODE_REMOTE_SETTINGS = ($remoteSettings | ConvertTo-Json -Compress)

$claudeSettingsPath = Join-Path $HOME ".claude\settings.json"
$codexConfigPath = Join-Path $HOME ".codex\config.toml"
$updated = 0

Write-Step "ติดตั้ง Claude Code Plugin"
if (Get-Command claude -ErrorAction SilentlyContinue) {
    $marketplaces = Get-CommandText "claude" @("plugin", "marketplace", "list")
    if ($marketplaces -match "(?m)(^|\s)$([regex]::Escape($marketplaceName))\s*$") {
        Invoke-Checked "claude" @("plugin", "marketplace", "update", $marketplaceName)
    }
    else {
        Invoke-Checked "claude" @("plugin", "marketplace", "add", $marketplaceRepo)
    }

    $plugins = Get-CommandText "claude" @("plugin", "list")
    if ($plugins -match [regex]::Escape($pluginId)) {
        try {
            Invoke-Checked "claude" @("plugin", "update", "--scope", "user", $pluginId)
        }
        catch {
            Write-Host "อัปเดต Plugin ไม่สำเร็จ ใช้เวอร์ชันที่ติดตั้งอยู่ต่อ: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    else {
        Invoke-Checked "claude" @("plugin", "install", "--scope", "user", $pluginId)
    }

    Write-Step "กำหนดค่า Remote Ollama/Qdrant ให้ Claude Code"
    New-Item -ItemType Directory -Force -Path (Split-Path $claudeSettingsPath) | Out-Null
    Backup-Once $claudeSettingsPath
    $mergeSettings = @'
const fs = require("node:fs");
const file = process.argv[2];
const raw = fs.existsSync(file) ? fs.readFileSync(file, "utf8").replace(/^\uFEFF/, "") : "";
const config = raw.trim() ? JSON.parse(raw) : {};
if (!config.env || typeof config.env !== "object" || Array.isArray(config.env)) {
  config.env = {};
}
Object.assign(config.env, JSON.parse(process.env.SOCRATICODE_REMOTE_SETTINGS));
fs.writeFileSync(file, JSON.stringify(config, null, 2) + "\n");
'@
    $mergeSettings | & node - $claudeSettingsPath
    $mergeCode = $LASTEXITCODE
    if ($mergeCode -ne 0) { throw "แก้ไข $claudeSettingsPath ไม่สำเร็จ (ไฟล์เดิมไม่ถูกเปลี่ยน)" }
    Write-Host "อัปเดต: $claudeSettingsPath"
    $updated++
}
else {
    Write-Host "ไม่พบ Claude Code CLI ข้ามรายการนี้" -ForegroundColor Yellow
}

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
    foreach ($key in $remoteSettings.Keys) {
        $toml = Set-TomlValue $toml "mcp_servers.socraticode.env" $key ('"' + $remoteSettings[$key] + '"')
    }
    Backup-Once $codexConfigPath
    Write-Utf8NoBom $codexConfigPath $toml
    $updated++
}
else {
    Write-Host "ไม่พบ Codex CLI ข้ามรายการนี้" -ForegroundColor Yellow
}

if ($updated -eq 0) { throw "ไม่พบ Claude Code CLI หรือ Codex CLI" }

Write-Step "ทดสอบการเชื่อมต่อ Ollama และ Qdrant"
$probe = @'
const settings = JSON.parse(process.env.SOCRATICODE_REMOTE_SETTINGS);
const base = (url) => url.replace(/\/+$/, "");
const clean = (value) => String(value).replace(/[^\x20-\x7E]/g, "?").slice(0, 200);
const report = (name, ok, detail) => console.log(JSON.stringify({ name, ok, detail: clean(detail) }));
const reason = (error) => (error && error.cause && (error.cause.code || error.cause.message)) || (error && error.message) || String(error);

async function call(url, options, timeoutMs) {
  const response = await fetch(url, { ...options, signal: AbortSignal.timeout(timeoutMs) });
  if (!response.ok) throw new Error("HTTP " + response.status);
  return response.json();
}

(async () => {
  const ollama = base(settings.OLLAMA_URL);
  const qdrant = base(settings.QDRANT_URL);
  const model = settings.EMBEDDING_MODEL;
  const dimensions = Number(settings.EMBEDDING_DIMENSIONS);

  try {
    const info = await call(ollama + "/api/version", {}, 10000);
    report("Ollama", true, ollama + " (version " + info.version + ")");
  } catch (error) {
    report("Ollama", false, ollama + " - " + reason(error));
  }

  try {
    const tags = await call(ollama + "/api/tags", {}, 10000);
    const found = (tags.models || []).some((item) => item.name === model || item.name === model + ":latest");
    report("Embedding model", found, found ? model : model + " is not on the server");
  } catch (error) {
    report("Embedding model", false, model + " - " + reason(error));
  }

  try {
    const started = Date.now();
    const result = await call(ollama + "/api/embed", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ model, input: "socraticode connection test" }),
    }, 120000);
    const size = result.embeddings && result.embeddings[0] ? result.embeddings[0].length : 0;
    const ok = size === dimensions;
    report("Embedding test", ok, size + " dimensions in " + (Date.now() - started) + " ms" + (ok ? "" : " (expected " + dimensions + ")"));
  } catch (error) {
    report("Embedding test", false, reason(error));
  }

  try {
    const info = await call(qdrant + "/", {}, 10000);
    const list = await call(qdrant + "/collections", {}, 10000);
    report("Qdrant", true, qdrant + " (version " + info.version + ", " + list.result.collections.length + " collections)");
  } catch (error) {
    report("Qdrant", false, qdrant + " - " + reason(error));
  }
})();
'@
$probeLines = @($probe | & node -)
Remove-Item Env:SOCRATICODE_REMOTE_SETTINGS -ErrorAction SilentlyContinue
$checked = 0
$failed = 0
foreach ($line in $probeLines) {
    try { $result = "$line" | ConvertFrom-Json } catch { continue }
    if ($null -eq $result -or $null -eq $result.name) { continue }
    $checked++
    if ($result.ok) {
        Write-Host ("[OK]   {0}: {1}" -f $result.name, $result.detail) -ForegroundColor Green
    }
    else {
        Write-Host ("[FAIL] {0}: {1}" -f $result.name, $result.detail) -ForegroundColor Red
        $failed++
    }
}

Write-Step "ติดตั้งเสร็จ"
if ($checked -eq 0) {
    Write-Host "ทดสอบการเชื่อมต่อไม่ได้ (node ไม่ส่งผลกลับมา)" -ForegroundColor Yellow
}
elseif ($failed -gt 0) {
    Write-Host "เชื่อมต่อไม่ผ่าน $failed จาก $checked รายการ ตรวจว่าเชื่อม Headscale VPN แล้ว และ resolve ชื่อผ่าน MagicDNS ได้ แล้วรัน Installer ซ้ำ" -ForegroundColor Yellow
}
else {
    Write-Host "เชื่อมต่อ Ollama และ Qdrant ได้ครบ $checked รายการ พร้อมใช้งาน" -ForegroundColor Green
}
Write-Host "ปิดและเปิด Claude Code / Codex ใหม่เพื่อโหลด Plugin และ MCP เวอร์ชันใหม่"

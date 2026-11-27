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

function Backup-Once([string]$Path) {
    if ((Test-Path -LiteralPath $Path) -and -not (Test-Path -LiteralPath "$Path.bak")) {
        Copy-Item -LiteralPath $Path -Destination "$Path.bak"
        Write-Host "Backup: $Path.bak" -ForegroundColor DarkGray
    }
}

$nodeMinMajor = 18
$nodeMinMinor = 17
$nodeDist = "https://nodejs.org/dist"

function Get-NodeProblem {
    $ErrorActionPreference = "Continue"
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) { return "Node.js was not found" }
    if (-not (Get-Command npx -ErrorAction SilentlyContinue)) { return "npx was not found" }
    $versionText = (& node --version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $versionText -notmatch '^v?(\d+)\.(\d+)\.(\d+)') { return "The Node.js version cannot be read" }
    $major = [int]$Matches[1]
    $minor = [int]$Matches[2]
    if ($major -lt $nodeMinMajor -or ($major -eq $nodeMinMajor -and $minor -lt $nodeMinMinor)) {
        return "Node.js $versionText is older than $nodeMinMajor.$nodeMinMinor"
    }
    return $null
}

function Update-SessionPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

function Install-NodeFromOfficialSite {
    $ProgressPreference = "SilentlyContinue"
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $cpu = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    $arch = switch ($cpu) {
        "AMD64" { "x64" }
        "ARM64" { "arm64" }
        default { throw "Unsupported Windows architecture: $cpu" }
    }
    $release = Invoke-RestMethod -UseBasicParsing -Uri "$nodeDist/index.json" | Where-Object { $_.lts } | Select-Object -First 1
    if (-not $release) { throw "Cannot read the Node.js release list from $nodeDist" }
    $version = $release.version
    $file = "node-$version-$arch.msi"
    $msi = Join-Path $env:TEMP $file

    Write-Host "Downloading $nodeDist/$version/$file"
    Invoke-WebRequest -UseBasicParsing -Uri "$nodeDist/$version/$file" -OutFile $msi
    $sums = [string](Invoke-RestMethod -UseBasicParsing -Uri "$nodeDist/$version/SHASUMS256.txt")
    $sumLine = ($sums -split "`n") | Where-Object { $_ -match "\s$([regex]::Escape($file))\s*$" } | Select-Object -First 1
    if (-not $sumLine) { throw "No checksum for $file in SHASUMS256.txt" }
    $expected = ($sumLine.Trim() -split '\s+')[0]
    $actual = (Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash
    if ($actual -ne $expected) {
        Remove-Item -LiteralPath $msi -ErrorAction SilentlyContinue
        throw "Checksum mismatch for $file"
    }

    Write-Host "Installing Node.js $version (Windows may ask for administrator approval)"
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList @("/i", "`"$msi`"", "/qn", "/norestart") -Verb RunAs -Wait -PassThru
    Remove-Item -LiteralPath $msi -ErrorAction SilentlyContinue
    if ($process.ExitCode -notin 0, 3010) { throw "The Node.js installer failed with exit code $($process.ExitCode)" }
}

Write-Step "Checking Node.js and npx"
$nodeProblem = Get-NodeProblem
if ($nodeProblem) {
    Write-Host $nodeProblem -ForegroundColor Yellow
    $answer = Read-Host "Install Node.js LTS (includes npm and npx) now? (y/n)"
    if ($answer -notmatch '^(y|yes)$') { throw "Cancelled: Node.js $nodeMinMajor.$nodeMinMinor or newer with npx is required" }

    $nodeInstalled = $false
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Step "Installing Node.js LTS with winget"
        try {
            Invoke-Checked "winget" @("install", "--id", "OpenJS.NodeJS.LTS", "--exact", "--accept-package-agreements", "--accept-source-agreements")
            $nodeInstalled = $true
        }
        catch {
            Write-Host "winget could not install Node.js: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    if (-not $nodeInstalled) {
        Write-Step "Installing Node.js LTS from nodejs.org"
        Install-NodeFromOfficialSite
    }

    Update-SessionPath
    $nodeProblem = Get-NodeProblem
    if ($nodeProblem) { throw "$nodeProblem after the install. Open a new PowerShell window and run this installer again" }
}
Write-Host "Node.js $((& node --version | Out-String).Trim()) with npx"

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

Write-Step "Installing the SocratiCode plugin for Claude Code"
$claude = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
if (-not $claude) { throw "Claude Code CLI not found. Install Claude Code first" }

$marketplaces = Get-CommandText $claude @("plugin", "marketplace", "list")
if ($marketplaces -match "(?m)(^|\s)$([regex]::Escape($marketplaceName))\s*$") {
    Invoke-Checked $claude @("plugin", "marketplace", "update", $marketplaceName)
}
else {
    Invoke-Checked $claude @("plugin", "marketplace", "add", $marketplaceRepo)
}

$plugins = Get-CommandText $claude @("plugin", "list")
if ($plugins -match [regex]::Escape($pluginId)) {
    try {
        Invoke-Checked $claude @("plugin", "update", "--scope", "user", $pluginId)
    }
    catch {
        Write-Host "Plugin update failed, keeping the installed version: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
else {
    Invoke-Checked $claude @("plugin", "install", "--scope", "user", $pluginId)
}

Write-Step "Writing the remote Ollama/Qdrant settings for Claude Code"
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
if ($LASTEXITCODE -ne 0) { throw "Cannot update $claudeSettingsPath (the file was left unchanged)" }
Write-Host "Updated: $claudeSettingsPath"

Write-Step "Testing the connection to Ollama and Qdrant"
$probe = @'
const crypto = require("node:crypto");
const settings = JSON.parse(process.env.SOCRATICODE_REMOTE_SETTINGS);
const base = (url) => url.replace(/\/+$/, "");
const clean = (value) => String(value).replace(/[^\x20-\x7E]/g, "?").slice(0, 200);
const report = (name, ok, detail) => console.log(JSON.stringify({ name, ok, detail: clean(detail) }));
const reason = (error) => (error && error.cause && (error.cause.code || error.cause.message)) || (error && error.message) || String(error);
const json = (method, body) => ({ method, headers: { "content-type": "application/json" }, body: JSON.stringify(body) });

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
  let vector = null;

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
    const result = await call(ollama + "/api/embed", json("POST", { model, input: "socraticode connection test" }), 120000);
    const size = result.embeddings && result.embeddings[0] ? result.embeddings[0].length : 0;
    const ok = size === dimensions;
    if (ok) vector = result.embeddings[0];
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

  const collection = "socraticode_install_test_" + crypto.randomBytes(6).toString("hex");
  const target = qdrant + "/collections/" + collection;
  const source = vector ? "the test embedding" : "a generated vector";
  let created = false;
  let outcome = null;
  try {
    const started = Date.now();
    const point = vector || Array.from({ length: dimensions }, (_, index) => (index % 7) + 1);
    await call(target, json("PUT", { vectors: { size: dimensions, distance: "Cosine" } }), 30000);
    created = true;
    await call(target + "/points?wait=true", json("PUT", { points: [{ id: 1, vector: point, payload: { source: "installer" } }] }), 30000);
    const found = await call(target + "/points/query", json("POST", { query: point, limit: 1 }), 30000);
    const hit = found.result && found.result.points ? found.result.points[0] : null;
    if (!hit || hit.id !== 1) throw new Error("the stored point was not returned by the search");
    outcome = { ok: true, detail: "create, write and search with " + source + " in " + (Date.now() - started) + " ms" };
  } catch (error) {
    outcome = { ok: false, detail: reason(error) };
  }
  if (created) {
    try {
      await call(target, { method: "DELETE" }, 30000);
    } catch (error) {
      outcome = { ok: false, detail: "cannot delete the test collection " + collection + " - " + reason(error) };
    }
  }
  report("Qdrant test", outcome.ok, outcome.detail);
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

Write-Step "Done"
if ($checked -eq 0) {
    Write-Host "Status: the connection test did not run (node returned nothing)" -ForegroundColor Yellow
}
elseif ($failed -gt 0) {
    Write-Host "Status: $failed of $checked checks failed. Connect to the Headscale VPN, make sure MagicDNS resolves both names, then run this installer again" -ForegroundColor Yellow
}
else {
    Write-Host "Status: all $checked checks passed. Ollama and Qdrant are ready" -ForegroundColor Green
}
Write-Host "Restart Claude Code to load the plugin and the new settings"

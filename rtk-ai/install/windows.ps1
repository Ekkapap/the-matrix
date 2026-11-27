
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$repo = "rtk-ai/rtk"
$assetName = "rtk-x86_64-pc-windows-msvc.zip"
$destDir = Join-Path $env:USERPROFILE ".local\bin"
$workDir = Join-Path $env:TEMP ("rtk-install-" + [guid]::NewGuid().ToString("N"))
$zipFile = Join-Path $workDir $assetName
$checksumFile = Join-Path $workDir "checksums.txt"

Write-Host "`n--- RTK Smart Installer ---" -ForegroundColor Cyan

try {
    if (-not [Environment]::Is64BitOperatingSystem) {
        throw "RTK installer requires 64-bit Windows."
    }

    New-Item -ItemType Directory -Path $workDir -Force | Out-Null

    Write-Host "[*] Checking latest release..." -ForegroundColor Gray

    $latest = Invoke-RestMethod `
        -Uri "https://api.github.com/repos/$repo/releases/latest" `
        -Headers @{ "User-Agent" = "RTK-Windows-Installer" }

    if (-not $latest.assets) {
        throw "GitHub release contains no assets."
    }

    $assetMatches = @(
        $latest.assets | Where-Object {
            $_.name -ceq $assetName
        }
    )

    if ($assetMatches.Count -ne 1) {
        throw "Expected exactly one asset '$assetName', found $($assetMatches.Count)."
    }

    $asset = $assetMatches[0]

    $checksumMatches = @(
        $latest.assets | Where-Object {
            $_.name -ceq "checksums.txt"
        }
    )

    if ($checksumMatches.Count -ne 1) {
        throw "Release checksum file not found."
    }

    Write-Host "[+] Latest Version: $($latest.tag_name)" -ForegroundColor Green
    Write-Host "[+] Asset: $($asset.name)" -ForegroundColor Green

    Write-Host "[*] Downloading RTK..." -ForegroundColor Gray

    Invoke-WebRequest `
        -Uri $asset.browser_download_url `
        -OutFile $zipFile `
        -UseBasicParsing

    if (-not (Test-Path $zipFile)) {
        throw "RTK download failed."
    }

    if ((Get-Item $zipFile).Length -eq 0) {
        throw "Downloaded ZIP file is empty."
    }

    Write-Host "[*] Downloading checksums..." -ForegroundColor Gray

    Invoke-WebRequest `
        -Uri $checksumMatches[0].browser_download_url `
        -OutFile $checksumFile `
        -UseBasicParsing

    $checksumLine = @(
        Get-Content $checksumFile | Where-Object {
            $_ -match ([regex]::Escape($assetName) + '$')
        }
    )

    if ($checksumLine.Count -ne 1) {
        throw "SHA256 entry for $assetName was not found."
    }

    if ($checksumLine[0] -notmatch '^([a-fA-F0-9]{64})\s+\*?') {
        throw "Invalid SHA256 checksum format."
    }

    $expectedHash = $Matches[1].ToLowerInvariant()
    $actualHash = (Get-FileHash -Path $zipFile -Algorithm SHA256).Hash.ToLowerInvariant()

    if ($actualHash -ne $expectedHash) {
        throw "SHA256 verification failed. Downloaded file may be corrupted."
    }

    Write-Host "[+] SHA256 verified." -ForegroundColor Green

    $extractPath = Join-Path $workDir "extracted"

    Expand-Archive `
        -Path $zipFile `
        -DestinationPath $extractPath `
        -Force

    $executables = @(
        Get-ChildItem -Path $extractPath -Filter "rtk.exe" -File -Recurse
    )

    if ($executables.Count -ne 1) {
        throw "Expected exactly one rtk.exe in archive, found $($executables.Count)."
    }

    New-Item -ItemType Directory -Path $destDir -Force | Out-Null

    $exe = Join-Path $destDir "rtk.exe"

    Write-Host "[*] Installing RTK..." -ForegroundColor Gray

    Copy-Item `
        -Path $executables[0].FullName `
        -Destination $exe `
        -Force

    if (-not (Test-Path $exe)) {
        throw "RTK executable installation failed."
    }

    Write-Host "[+] Installed: $exe" -ForegroundColor Green

    Write-Host "[*] Configuring User PATH..." -ForegroundColor Gray

    $currentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")

    $pathEntries = @(
        $currentUserPath -split ';' | Where-Object {
            $_.Trim()
        }
    )

    $pathExists = @(
        $pathEntries | Where-Object {
            $_.Trim().TrimEnd('\') -ieq $destDir.TrimEnd('\')
        }
    ).Count -gt 0

    if (-not $pathExists) {
        $newUserPath = (@($pathEntries) + $destDir) -join ';'

        [Environment]::SetEnvironmentVariable(
            "Path",
            $newUserPath,
            "User"
        )

        Write-Host "[+] Added User PATH: $destDir" -ForegroundColor Green
    } else {
        Write-Host "[+] User PATH already configured." -ForegroundColor Green
    }

    $processPathExists = @(
        $env:Path -split ';' | Where-Object {
            $_.Trim().TrimEnd('\') -ieq $destDir.TrimEnd('\')
        }
    ).Count -gt 0

    if (-not $processPathExists) {
        $env:Path = "$destDir;$env:Path"
    }

    Write-Host "`n--- Verifying RTK ---" -ForegroundColor Cyan

    & $exe --version

    if ($LASTEXITCODE -ne 0) {
        throw "RTK version verification failed."
    }

    Write-Host "`n--- Initializing RTK ---" -ForegroundColor Cyan

    & $exe init -g --auto-patch

    if ($LASTEXITCODE -ne 0) {
        throw "RTK global initialization failed."
    }

    Write-Host "`n--- Checking RTK Configuration ---" -ForegroundColor Cyan

    & $exe init --show

    if ($LASTEXITCODE -ne 0) {
        throw "RTK configuration verification failed."
    }

    Write-Host "`n--- Testing RTK ---" -ForegroundColor Cyan

    & $exe gain

    if ($LASTEXITCODE -ne 0) {
        throw "RTK gain verification failed."
    }

    Write-Host "`n[+] RTK installation completed successfully." -ForegroundColor Green
    Write-Host "[+] Version: $($latest.tag_name)" -ForegroundColor Green
    Write-Host "[+] Binary: $exe" -ForegroundColor Green
    Write-Host "[+] PATH: $destDir" -ForegroundColor Green

} catch {
    Write-Host "`n[!] Installation failed!" -ForegroundColor Red
    Write-Host "[!] $($_.Exception.Message)" -ForegroundColor Red
    exit 1

} finally {
    if (Test-Path $workDir) {
        Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

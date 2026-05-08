$repo = "rtk-ai/rtk"
$destDir = "$env:USERPROFILE\.local\bin"
$zipFile = "$env:TEMP\rtk_latest.zip"
$extractPath = "$env:TEMP\rtk_extracted"

$gitPath = "C:\Program Files\Git\usr\bin"
$gitDownloadUrl = "https://gitforwindows.org"

Write-Host "--- RTK Smart Installer ---" -ForegroundColor Cyan

if (!(Test-Path $gitPath)) {
    Write-Host "[!] Git for Windows was not found." -ForegroundColor Red
    Write-Host "[!] Required Path Missing:" -ForegroundColor Yellow
    Write-Host "    $gitPath" -ForegroundColor Gray
    Write-Host ""
    Write-Host "[+] Download Git for Windows:" -ForegroundColor Cyan
    Write-Host "    $gitDownloadUrl" -ForegroundColor White

    Start-Process $gitDownloadUrl

    exit 1
}

if (!(Test-Path $destDir)) {
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
}

try {
    $latest = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest"

    $asset = $latest.assets | Where-Object {
        $_.name -like "*windows-msvc.zip"
    }

    Write-Host "[+] Latest Version: $($latest.tag_name)" -ForegroundColor Green

    Write-Host "[*] Downloading and Updating..." -ForegroundColor Gray

    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipFile

    if (Test-Path $extractPath) {
        Remove-Item -Recurse $extractPath -Force
    }

    Expand-Archive -Path $zipFile -DestinationPath $extractPath -Force

    Move-Item -Path "$extractPath\*.exe" -Destination $destDir -Force

    $pathsToAdd = @(
        $destDir,
        $gitPath
    )

    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")

    foreach ($pathItem in $pathsToAdd) {
        if ($currentPath -notlike "*$pathItem*") {

            $separator = if (
                $currentPath.EndsWith(";") -or
                $currentPath -eq ""
            ) {
                ""
            } else {
                ";"
            }

            $currentPath = $currentPath + $separator + $pathItem

            Write-Host "[+] Added PATH: $pathItem" -ForegroundColor Cyan
        }
    }

    [Environment]::SetEnvironmentVariable(
        "Path",
        $currentPath,
        "User"
    )

    $env:Path = $currentPath

    Write-Host "`n--- Initializing RTK ---" -ForegroundColor Cyan

    $exe = "$destDir\rtk.exe"

    & $exe --version
    & $exe init -g --auto-patch
    & $exe init --show
    & $exe ls . | Out-Null 2>&1
    & $exe gain

    Remove-Item $zipFile -ErrorAction SilentlyContinue

    Remove-Item -Recurse $extractPath -ErrorAction SilentlyContinue

    Write-Host "`n[!] Success! RTK is ready." -ForegroundColor Green

    Write-Host "`n[+] Testing Unix Commands..." -ForegroundColor Yellow

    ls
    rtk ls

} catch {
    Write-Host "[!] Error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "--- RTK installed and is ready to use ---" -ForegroundColor Green

Start-Process "https://github.com/rtk-ai/rtk"

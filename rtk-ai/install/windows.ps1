# --- Configuration ---
$repo = "rtk-ai/rtk"
$destDir = "$env:USERPROFILE\.local\bin"
$zipFile = "$env:TEMP\rtk_latest.zip"
$extractPath = "$env:TEMP\rtk_extracted"

Write-Host "--- RTK Smart Installer ---" -ForegroundColor Cyan

# 1. เตรียม Folder
if (!(Test-Path $destDir)) {
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
}

# 2. ดึงข้อมูลล่าสุด
try {
    $latest = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest"
    $asset = $latest.assets | Where-Object { $_.name -like "*windows-msvc.zip" }
    Write-Host "[+] Latest Version: $($latest.tag_name)" -ForegroundColor Green
    
    # 3. Download & Replace
    Write-Host "[*] Downloading and Updating..." -ForegroundColor Gray
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipFile
    
    if (Test-Path $extractPath) { Remove-Item -Recurse $extractPath -Force }
    Expand-Archive -Path $zipFile -DestinationPath $extractPath -Force
    
    # ย้ายไฟล์ทับของเดิม (Replace)
    Move-Item -Path "$extractPath\*.exe" -Destination $destDir -Force
    
    # 4. จัดการ PATH (เพิ่มเฉพาะถ้ายังไม่มี)
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($currentPath -notlike "*$destDir*") {
        $separator = if ($currentPath.EndsWith(";") -or $currentPath -eq "") { "" } else { ";" }
        [Environment]::SetEnvironmentVariable("Path", ($currentPath + $separator + $destDir), "User")
        $env:Path += ";$destDir"
        Write-Host "[+] PATH added to your system." -ForegroundColor Cyan
    }

    # 5. Initializing RTK (Added)
    Write-Host "`n--- Initializing RTK ---" -ForegroundColor Cyan
    # ใช้ & เพื่อรัน exe จากตัวแปร path หรือระบุ full path เพื่อความชัวร์ใน session แรก
    $exe = "$destDir\rtk.exe"
    & $exe --version
    & $exe init -g
    & $exe ls | Out-Null 2>&1  # Silence output เหมือน > /dev/null
    & $exe gain

    # 6. Cleanup
    Remove-Item $zipFile -ErrorAction SilentlyContinue
    Remove-Item -Recurse $extractPath -ErrorAction SilentlyContinue
    
    Write-Host "`n[!] Success! RTK is ready." -ForegroundColor Green
} catch {
    Write-Host "[!] Error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "--- RTK installed and is ready to use ---" -ForegroundColor Green
Start-Process "https://github.com/rtk-ai/rtk"

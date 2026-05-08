Write-Host "--- RTK Deep Cleanup Starting ---" -ForegroundColor Cyan

# 1. กำหนด Path พื้นฐานแบบ Dynamic
$destDir = "$env:USERPROFILE\.local\bin"
$configPath = "$env:APPDATA\rtk"
$localShare = "$env:LOCALAPPDATA\rtk"
$claudeSettings = "$env:USERPROFILE\.claude\settings.json"
$rtkMd = "$env:USERPROFILE\.claude\RTK.md"

# 2. ลบไฟล์โปรแกรมและโฟลเดอร์ Binary
if (Test-Path $destDir) { 
    Remove-Item -Recurse -Force $destDir -ErrorAction SilentlyContinue
    Write-Host "[-] Deleted Binaries: $destDir" -ForegroundColor Yellow
}

# 3. ลบ Path ออกจาก Environment (User)
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($currentPath -like "*$destDir*") {
    $newPath = $currentPath.Replace("$destDir", "").Replace(";;", ";").Trim(';')
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Host "[-] Path removed from Environment Variables." -ForegroundColor Yellow
}

# 4. ล้าง Config และ Local Share (Telemetry/Hooks)
foreach ($path in @($configPath, $localShare)) {
    if (Test-Path $path) { 
        Remove-Item -Recurse -Force $path -ErrorAction SilentlyContinue
        Write-Host "[-] Deleted Data: $path" -ForegroundColor Yellow
    }
}

# 5. ลบไฟล์ RTK.md ใน .claude
if (Test-Path $rtkMd) {
    Remove-Item -Force $rtkMd
    Write-Host "[-] Deleted: $rtkMd" -ForegroundColor Yellow
}

# 6. ล้างเฉพาะ RTK Hook ใน Claude settings.json (รักษาค่าอื่นไว้)
if (Test-Path $claudeSettings) {
    try {
        $settings = Get-Content $claudeSettings | ConvertFrom-Json
        if ($settings.hooks.PreToolUse) {
            foreach ($item in $settings.hooks.PreToolUse) {
                if ($item.matcher -eq "Bash") {
                    $item.hooks = $item.hooks | Where-Object { $_.command -ne "rtk hook claude" }
                }
            }
            $settings | ConvertTo-Json -Depth 10 | Set-Content $claudeSettings
            Write-Host "[-] Specific RTK hook removed from settings.json" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[!] Warning: Could not parse settings.json, skipping hook cleanup." -ForegroundColor Red
    }
}

Write-Host "`n[!] Deep Cleanup Complete. Your system is now RTK-free." -ForegroundColor Green
Write-Host "You can now re-run the installer for a clean test." -ForegroundColor White

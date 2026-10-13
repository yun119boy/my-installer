```powershell
$ErrorActionPreference = "Stop"

$folder = Join-Path $env:USERPROFILE "Desktop\MyPlugin"

$steamToolUrl = "https://github.com/yun119boy/my-installer/releases/download/v1.0/st-setup-1.8.30.exe"
$millenniumUrl = "https://github.com/yun119boy/my-installer/releases/download/v1.0/MillenniumInstaller-Windows.exe"
$pluginUrl = "https://github.com/yun119boy/my-installer/releases/download/v1.0/com.yun119boy.licensemanager.star"

$steamToolPath = Join-Path $folder "st-setup-1.8.30.exe"
$millenniumPath = Join-Path $folder "MillenniumInstaller-Windows.exe"
$pluginPath = Join-Path $folder "com.yun119boy.licensemanager.star"

function Download-File($url, $destination) {
    Write-Host "กำลังดาวน์โหลด $(Split-Path $destination -Leaf)..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $url -OutFile $destination

    if (!(Test-Path $destination) -or
        (Get-Item $destination).Length -eq 0) {
        throw "ดาวน์โหลดไฟล์ไม่สำเร็จ: $destination"
    }

    Write-Host "ดาวน์โหลดสำเร็จ" -ForegroundColor Green
}

function Start-VisibleInstaller($path, $name) {
    Write-Host ""
    Write-Host "กำลังเปิดตัวติดตั้ง $name" -ForegroundColor Cyan
    Write-Host "โปรดทำตามขั้นตอนในหน้าต่างที่เปิดขึ้นมา"

    $process = Start-Process -FilePath $path -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        throw "$name ปิดด้วยรหัส $($process.ExitCode) โปรดตรวจสอบการติดตั้ง"
    }

    Write-Host "$name ปิดตัวติดตั้งแล้ว" -ForegroundColor Green
}

try {
    New-Item -ItemType Directory -Path $folder -Force | Out-Null

    Write-Host "====================================" -ForegroundColor Cyan
    Write-Host "       License Manager Setup        " -ForegroundColor Cyan
    Write-Host "====================================" -ForegroundColor Cyan

    # 1. ดาวน์โหลดทุกไฟล์
    Download-File $steamToolUrl $steamToolPath
    Download-File $millenniumUrl $millenniumPath
    Download-File $pluginUrl $pluginPath

    # 2. ติดตั้ง SteamTool แบบแสดงหน้าต่าง
    Start-VisibleInstaller $steamToolPath "SteamTool"

    # 3. ติดตั้ง Millennium แบบแสดงหน้าต่าง
    Start-VisibleInstaller $millenniumPath "Millennium"

    # 4. ค้นหาโฟลเดอร์ Steam จาก Registry
    $steamRoots = @()

    $registryKeys = @(
        "HKCU:\Software\Valve\Steam",
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam"
    )

    foreach ($key in $registryKeys) {
        if (Test-Path $key) {
            $p = Get-ItemProperty $key -ErrorAction SilentlyContinue
            if ($p.SteamPath) {
                $steamRoots += $p.SteamPath
            }
            if ($p.InstallPath) {
                $steamRoots += $p.InstallPath
            }
        }
    }

    $steamRoots = @($steamRoots | Select-Object -Unique)
    $pluginDirs = @()

    foreach ($steamRoot in $steamRoots) {
        $pluginDirs += (Join-Path $steamRoot "millennium\plugins")
        $pluginDirs += (Join-Path $steamRoot "plugins")
    }

    # รองรับโฟลเดอร์ Millennium ใน LocalAppData
    $localMillennium = Join-Path $env:LOCALAPPDATA "Millennium\plugins"
    $pluginDirs += $localMillennium

    $existingDirs = @(
        $pluginDirs |
        Select-Object -Unique |
        Where-Object { Test-Path $_ -PathType Container }
    )

    if ($existingDirs.Count -eq 0) {
        Write-Host ""
        Write-Host "ไม่พบโฟลเดอร์ plugins ของ Millennium" -ForegroundColor Yellow
        Write-Host "ดาวน์โหลดปลั๊กอินไว้ที่: $pluginPath"
        Write-Host "โปรดตรวจสอบตำแหน่งติดตั้ง Millennium แล้วคัดลอกไฟล์ .star ด้วยตนเอง"
    }
    else {
        # คัดลอกไปยังตำแหน่งที่พบ
        foreach ($dir in $existingDirs) {
            Copy-Item -Path $pluginPath `
                -Destination (Join-Path $dir (Split-Path $pluginPath -Leaf)) `
                -Force

            Write-Host "คัดลอกปลั๊กอินไปที่ $dir สำเร็จ" -ForegroundColor Green
        }
    }

    Write-Host ""
    Write-Host "ดำเนินการครบทุกขั้นตอนแล้ว" -ForegroundColor Green
    Write-Host "หาก Millennium ยังไม่แสดงปลั๊กอิน ให้ปิดและเปิด Steam ใหม่"
}
catch {
    Write-Host ""
    Write-Host "เกิดข้อผิดพลาด: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    Write-Host ""
    Read-Host "กด Enter เพื่อปิดหน้าต่าง"
}
```

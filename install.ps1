
$ErrorActionPreference = "Stop"

# ==========================================
# License Manager Setup
# ==========================================

$folder = Join-Path $env:TEMP "MyPlugin"

$steamToolUrl = "https://github.com/yun119boy/my-installer/releases/download/v1.0/st-setup-1.8.30.exe"
$millenniumUrl = "https://github.com/yun119boy/my-installer/releases/download/v1.0/MillenniumInstaller-Windows.exe"
$pluginUrl = "https://github.com/yun119boy/my-installer/releases/download/v1.0/com.yun119boy.licensemanager.star"

$steamToolPath = Join-Path $folder "st-setup-1.8.30.exe"
$millenniumPath = Join-Path $folder "MillenniumInstaller-Windows.exe"
$pluginPath = Join-Path $folder "com.yun119boy.licensemanager.star"

# ==========================================
# Download files
# ==========================================

function Download-File {
    param(
        [string]$Url,
        [string]$Destination
    )

    Write-Host "กำลังดาวน์โหลด $(Split-Path $Destination -Leaf)..." -ForegroundColor Yellow

    Invoke-WebRequest -Uri $Url -OutFile $Destination

    if (
        !(Test-Path -LiteralPath $Destination -PathType Leaf) -or
        (Get-Item -LiteralPath $Destination).Length -eq 0
    ) {
        throw "ดาวน์โหลดไฟล์ไม่สำเร็จ: $Destination"
    }

    Write-Host "ดาวน์โหลดสำเร็จ" -ForegroundColor Green
}

# ==========================================
# Run visible installers and wait
# ==========================================

function Start-VisibleInstaller {
    param(
        [string]$Path,
        [string]$Name
    )

    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "ไม่พบตัวติดตั้ง $Name : $Path"
    }

    Write-Host ""
    Write-Host "กำลังเปิดตัวติดตั้ง $Name" -ForegroundColor Cyan
    Write-Host "ทำตามขั้นตอนในหน้าต่างตัวติดตั้งให้เสร็จ"

    $process = Start-Process -FilePath $Path -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        throw "$Name ปิดด้วยรหัส $($process.ExitCode) กรุณาตรวจสอบการติดตั้ง"
    }

    Write-Host "$Name ปิดตัวติดตั้งแล้ว" -ForegroundColor Green
}

# ==========================================
# Find Steam installation directories
# ==========================================

function Get-SteamRoots {
    $roots = @()

    $registryPaths = @(
        "HKCU:\Software\Valve\Steam",
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam"
    )

    foreach ($registryPath in $registryPaths) {
        if (Test-Path -LiteralPath $registryPath) {
            $reg = Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue

            foreach ($valueName in @("SteamPath", "InstallPath")) {
                $value = $reg.$valueName

                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $roots += ($value -replace "/", "\")
                }
            }
        }
    }

    $roots += @(
        "${env:ProgramFiles(x86)}\Steam",
        "$env:ProgramFiles\Steam",
        "C:\Steam",
        "D:\Steam",
        "E:\Steam"
    )

    return @(
        $roots |
            Where-Object {
                $_ -and (Test-Path -LiteralPath $_ -PathType Container)
            } |
            ForEach-Object {
                (Get-Item -LiteralPath $_).FullName.TrimEnd("\")
            } |
            Select-Object -Unique
    )
}

# ==========================================
# Find Millennium plugins directory
# ==========================================


function Find-MillenniumPlugins {
    param([string[]]$SteamRoots)

    $found = @(
        foreach ($root in $SteamRoots) {
            $candidate = Join-Path $root "millennium\plugins"

            if (Test-Path -LiteralPath $candidate -PathType Container) {
                (Get-Item -LiteralPath $candidate).FullName
            }
        }
    )

    # ตัดรายการซ้ำโดยไม่สนตัวพิมพ์เล็ก-ใหญ่
    $uniqueFound = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    foreach ($path in $found) {
        [void]$uniqueFound.Add($path.TrimEnd("\"))
    }

    $found = @($uniqueFound)

    if ($found.Count -eq 0) {
        throw "ไม่พบโฟลเดอร์ Millennium plugins"
    }

    if ($found.Count -gt 1) {
        Write-Host "พบโฟลเดอร์ plugins หลายตำแหน่ง:" -ForegroundColor Yellow

        for ($i = 0; $i -lt $found.Count; $i++) {
            Write-Host "[$($i + 1)] $($found[$i])"
        }

        $selection = Read-Host "พิมพ์หมายเลขตำแหน่งที่ต้องการติดตั้ง"

        $number = 0
        if (
            ![int]::TryParse($selection, [ref]$number) -or
            $number -lt 1 -or
            $number -gt $found.Count
        ) {
            throw "หมายเลขตำแหน่งไม่ถูกต้อง"
        }

        return $found[$number - 1]
    }

    return $found[0]
}

# ==========================================
# Main
# ==========================================

try {
    New-Item -ItemType Directory -Path $folder -Force | Out-Null

    Write-Host "====================================" -ForegroundColor Cyan
    Write-Host "       License Manager Setup        " -ForegroundColor Cyan
    Write-Host "====================================" -ForegroundColor Cyan

    # 1. Download all required files
    Download-File -Url $steamToolUrl -Destination $steamToolPath
    Download-File -Url $millenniumUrl -Destination $millenniumPath
    Download-File -Url $pluginUrl -Destination $pluginPath

    # 2. Run SteamTool installer
    Start-VisibleInstaller -Path $steamToolPath -Name "SteamTool"

    # 3. Run Millennium installer
    Start-VisibleInstaller -Path $millenniumPath -Name "Millennium"

    # 4. Validate plugin file
    if (
        !(Test-Path -LiteralPath $pluginPath -PathType Leaf) -or
        (Get-Item -LiteralPath $pluginPath).Length -eq 0
    ) {
        throw "ไม่พบไฟล์ปลั๊กอิน หรือไฟล์มีขนาด 0 ไบต์"
    }

    # 5. Find Steam and Millennium plugin directory
    $steamRoots = @(Get-SteamRoots)

    if ($steamRoots.Count -eq 0) {
        throw "ไม่พบตำแหน่งติดตั้ง Steam จาก Registry หรือโฟลเดอร์มาตรฐาน"
    }

    Write-Host ""
    Write-Host "ตำแหน่ง Steam ที่ตรวจพบ:" -ForegroundColor Cyan
    $steamRoots | ForEach-Object { Write-Host " - $_" }

    $pluginDir = Find-MillenniumPlugins -SteamRoots $steamRoots

    Write-Host "โฟลเดอร์ปลั๊กอิน: $pluginDir" -ForegroundColor Green

    # 6. Copy plugin
    $destination = Join-Path $pluginDir "com.yun119boy.licensemanager.star"

    Copy-Item -LiteralPath $pluginPath -Destination $destination -Force -ErrorAction Stop

    if (
        !(Test-Path -LiteralPath $destination -PathType Leaf) -or
        (Get-Item -LiteralPath $destination).Length -eq 0
    ) {
        throw "คัดลอกไฟล์ปลั๊กอินไม่สำเร็จ"
    }

    Write-Host ""
    Write-Host "ติดตั้งปลั๊กอินสำเร็จ!" -ForegroundColor Green
    Write-Host "ตำแหน่ง: $destination"
}
catch {
    Write-Host ""
    Write-Host "เกิดข้อผิดพลาด: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    Write-Host ""
    Read-Host "กด Enter เพื่อปิดหน้าต่าง"
}

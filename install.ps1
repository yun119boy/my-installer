
#Requires -Version 5.1

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

# ตั้งค่า encoding สำหรับ PowerShell 5.1
try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $OutputEncoding = New-Object System.Text.UTF8Encoding($false)
} catch {}

# ==========================================
# Helper: Download files
# ==========================================

function Download-File {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    Write-Host ""
    Write-Host "กำลังดาวน์โหลด $(Split-Path $Destination -Leaf)..." -ForegroundColor Yellow

    Invoke-WebRequest `
        -Uri $Url `
        -OutFile $Destination `
        -UseBasicParsing `
        -ErrorAction Stop

    if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
        throw "ไม่พบไฟล์หลังดาวน์โหลด: $Destination"
    }

    $file = Get-Item -LiteralPath $Destination

    if ($file.Length -le 0) {
        throw "ไฟล์ที่ดาวน์โหลดมีขนาด 0 ไบต์: $Destination"
    }

    Write-Host "ดาวน์โหลดสำเร็จ: $($file.Name)" -ForegroundColor Green
}

# ==========================================
# Helper: Run installer and wait
# ==========================================

function Start-VisibleInstaller {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "ไม่พบตัวติดตั้ง ${Name}: $Path"
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
    $roots = New-Object 'System.Collections.Generic.List[string]'

    $registryPaths = @(
        "HKCU:\Software\Valve\Steam",
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam"
    )

    foreach ($registryPath in $registryPaths) {
        if (Test-Path -LiteralPath $registryPath) {
            $reg = Get-ItemProperty `
                -LiteralPath $registryPath `
                -ErrorAction SilentlyContinue

            if ($null -ne $reg) {
                foreach ($valueName in @("SteamPath", "InstallPath")) {
                    $value = $reg.$valueName

                    if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
                        $roots.Add(([string]$value).Replace("/", "\"))
                    }
                }
            }
        }
    }

    if ($env:ProgramFiles) {
        $roots.Add((Join-Path $env:ProgramFiles "Steam"))
    }

    if (${env:ProgramFiles(x86)}) {
        $roots.Add((Join-Path ${env:ProgramFiles(x86)} "Steam"))
    }

    $roots.Add("C:\Steam")
    $roots.Add("D:\Steam")
    $roots.Add("E:\Steam")

    # Dictionary นี้ไม่แยกตัวพิมพ์เล็กและใหญ่
    $unique = New-Object 'System.Collections.Generic.Dictionary[string,string]' (
        [System.StringComparer]::OrdinalIgnoreCase
    )

    foreach ($root in $roots) {
        if ([string]::IsNullOrWhiteSpace($root)) {
            continue
        }

        if (Test-Path -LiteralPath $root -PathType Container) {
            $fullPath = (Get-Item -LiteralPath $root).FullName.TrimEnd("\")

            if (-not $unique.ContainsKey($fullPath)) {
                $unique.Add($fullPath, $fullPath)
            }
        }
    }

    return @($unique.Values)
}

# ==========================================
# Find or prepare Millennium plugins directory
# ==========================================

function Find-MillenniumPlugins {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$SteamRoots
    )

    $unique = New-Object 'System.Collections.Generic.Dictionary[string,string]' (
        [System.StringComparer]::OrdinalIgnoreCase
    )

    foreach ($root in $SteamRoots) {
        $millenniumDir = Join-Path $root "millennium"
        $candidate = Join-Path $millenniumDir "plugins"

        # ใช้เฉพาะตำแหน่งที่มีโฟลเดอร์ Millennium จริง
        if (Test-Path -LiteralPath $millenniumDir -PathType Container) {
            if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
                Write-Host "ไม่พบโฟลเดอร์ plugins กำลังสร้าง..." -ForegroundColor Yellow
                New-Item -ItemType Directory -Path $candidate -Force | Out-Null
            }

            $fullPath = (Get-Item -LiteralPath $candidate).FullName.TrimEnd("\")

            if (-not $unique.ContainsKey($fullPath)) {
                $unique.Add($fullPath, $fullPath)
            }
        }
    }

    $found = @($unique.Values)

    if ($found.Count -eq 0) {
        throw "ไม่พบโฟลเดอร์ Millennium ในตำแหน่ง Steam ที่ตรวจพบ กรุณาตรวจสอบว่าติดตั้ง Millennium สำเร็จแล้ว"
    }

    if ($found.Count -eq 1) {
        return $found[0]
    }

    Write-Host ""
    Write-Host "พบโฟลเดอร์ Millennium หลายตำแหน่ง:" -ForegroundColor Yellow

    for ($i = 0; $i -lt $found.Count; $i++) {
        Write-Host "[$($i + 1)] $($found[$i])"
    }

    $selection = Read-Host "เลือกหมายเลขตำแหน่งที่จะติดตั้ง"

    $number = 0

    if (
        -not [int]::TryParse($selection, [ref]$number) -or
        $number -lt 1 -or
        $number -gt $found.Count
    ) {
        throw "หมายเลขไม่ถูกต้อง ยกเลิกการติดตั้ง"
    }

    return $found[$number - 1]
}

# ==========================================
# Main
# ==========================================

try {
    New-Item -ItemType Directory -Path $folder -Force | Out-Null

    Write-Host ""
    Write-Host "====================================" -ForegroundColor Cyan
    Write-Host "       License Manager Setup        " -ForegroundColor Cyan
    Write-Host "====================================" -ForegroundColor Cyan

    # 1. Download files
    Download-File -Url $steamToolUrl -Destination $steamToolPath
    Download-File -Url $millenniumUrl -Destination $millenniumPath
    Download-File -Url $pluginUrl -Destination $pluginPath

    # 2. Run installers one at a time
    Start-VisibleInstaller -Path $steamToolPath -Name "SteamTool"
    Start-VisibleInstaller -Path $millenniumPath -Name "Millennium"

    # 3. Ask user to open Steam
    Write-Host ""
    Write-Host "====================================" -ForegroundColor Cyan
    Write-Host "          ขั้นตอนถัดไป              " -ForegroundColor Cyan
    Write-Host "====================================" -ForegroundColor Cyan
    Write-Host "1. เปิด Steam ด้วยตัวเอง"
    Write-Host "2. รอให้ Steam เปิดเรียบร้อย"
    Write-Host "3. กลับมาที่หน้าต่างนี้แล้วกด Enter"

    Read-Host "เมื่อเปิด Steam แล้ว กด Enter เพื่อดำเนินการต่อ"

    $steamProcess = Get-Process -Name "steam" -ErrorAction SilentlyContinue

    if (-not $steamProcess) {
        throw "ยังไม่พบโปรเซส Steam กรุณาเปิด Steam แล้วรันสคริปต์อีกครั้ง"
    }

    Write-Host "ตรวจพบ Steam กำลังทำงาน" -ForegroundColor Green

    # 4. Validate plugin file
    if (-not (Test-Path -LiteralPath $pluginPath -PathType Leaf)) {
        throw "ไม่พบไฟล์ปลั๊กอิน: $pluginPath"
    }

    if ((Get-Item -LiteralPath $pluginPath).Length -le 0) {
        throw "ไฟล์ปลั๊กอินมีขนาด 0 ไบต์"
    }

    # 5. Find Steam
    $steamRoots = @(Get-SteamRoots)

    if ($steamRoots.Count -eq 0) {
        throw "ไม่พบตำแหน่งติดตั้ง Steam กรุณาตรวจสอบการติดตั้ง Steam"
    }

    Write-Host ""
    Write-Host "ตำแหน่ง Steam ที่ตรวจพบ:" -ForegroundColor Cyan

    foreach ($root in $steamRoots) {
        Write-Host " - $root"
    }

    # 6. Find Millennium plugins directory
    $pluginDir = Find-MillenniumPlugins -SteamRoots $steamRoots

    Write-Host ""
    Write-Host "โฟลเดอร์ปลั๊กอิน: $pluginDir" -ForegroundColor Green

    # 7. Copy plugin
    $destination = Join-Path $pluginDir "com.yun119boy.licensemanager.star"

    Copy-Item `
        -LiteralPath $pluginPath `
        -Destination $destination `
        -Force `
        -ErrorAction Stop

    if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
        throw "ไม่พบไฟล์ปลั๊กอินที่ปลายทางหลังคัดลอก"
    }

    if ((Get-Item -LiteralPath $destination).Length -le 0) {
        throw "ไฟล์ปลั๊กอินปลายทางมีขนาด 0 ไบต์"
    }

    Write-Host ""
    Write-Host "====================================" -ForegroundColor Green
    Write-Host "       ติดตั้งปลั๊กอินสำเร็จ!       " -ForegroundColor Green
    Write-Host "====================================" -ForegroundColor Green
    Write-Host "ตำแหน่ง: $destination"
}
catch {
    Write-Host ""
    Write-Host "====================================" -ForegroundColor Red
    Write-Host "เกิดข้อผิดพลาด:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
finally {
    Write-Host ""
    Read-Host "กด Enter เพื่อปิดหน้าต่าง"
}

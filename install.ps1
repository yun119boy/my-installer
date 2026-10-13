
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

# ตั้งค่าภาษาไทยในหน้าต่าง PowerShell
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch {}

# ==========================================
# Download files
# ==========================================

function Download-File {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Destination
    )

    Write-Host "กำลังดาวน์โหลด $(Split-Path $Destination -Leaf)..." -ForegroundColor Yellow

    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing

    if (!(Test-Path -LiteralPath $Destination -PathType Leaf)) {
        throw "ดาวน์โหลดไฟล์ไม่สำเร็จ: $Destination"
    }

    if ((Get-Item -LiteralPath $Destination).Length -eq 0) {
        throw "ไฟล์ที่ดาวน์โหลดมีขนาด 0 ไบต์: $Destination"
    }

    Write-Host "ดาวน์โหลดสำเร็จ" -ForegroundColor Green
}

# ==========================================
# Run visible installers
# ==========================================

function Start-VisibleInstaller {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )

    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "ไม่พบตัวติดตั้ง ${Name}: $Path"
    }

    Write-Host ""
    Write-Host "กำลังเปิดตัวติดตั้ง $Name" -ForegroundColor Cyan
    Write-Host "ทำตามขั้นตอนในหน้าต่างตัวติดตั้งให้เสร็จ"

    $process = Start-Process -FilePath $Path -Wait -PassThru

    if ($null -ne $process.ExitCode -and $process.ExitCode -ne 0) {
        throw "$Name ปิดด้วยรหัส $($process.ExitCode) กรุณาตรวจสอบการติดตั้ง"
    }

    Write-Host "$Name ปิดตัวติดตั้งแล้ว" -ForegroundColor Green
}

# ==========================================
# Find Steam installation directories
# ==========================================

function Get-SteamRoots {
    $roots = [System.Collections.Generic.List[string]]::new()

    $registryPaths = @(
        "HKCU:\Software\Valve\Steam",
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam"
    )

    foreach ($registryPath in $registryPaths) {
        if (Test-Path -LiteralPath $registryPath) {
            $reg = Get-ItemProperty -LiteralPath $registryPath -ErrorAction SilentlyContinue

            foreach ($valueName in @("SteamPath", "InstallPath")) {
                $value = $reg.$valueName

                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $normalized = $value -replace "/", "\"
                    $roots.Add($normalized)
                }
            }
        }
    }

    $roots.Add("$env:ProgramFiles\Steam")

    if (${env:ProgramFiles(x86)}) {
        $roots.Add("${env:ProgramFiles(x86)}\Steam")
    }

    $roots.Add("C:\Steam")
    $roots.Add("D:\Steam")
    $roots.Add("E:\Steam")

    $unique = [System.Collections.Generic.Dictionary[string,string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    foreach ($root in $roots) {
        if ([string]::IsNullOrWhiteSpace($root)) {
            continue
        }

        if (Test-Path -LiteralPath $root -PathType Container) {
            $fullPath = (Get-Item -LiteralPath $root).FullName.TrimEnd("\")

            if (!$unique.ContainsKey($fullPath)) {
                $unique[$fullPath] = $fullPath
            }
        }
    }

    return @($unique.Values)
}

# ==========================================
# Find Millennium plugins directory
# ==========================================

function Find-MillenniumPlugins {
    param([string[]]$SteamRoots)

    $unique = [System.Collections.Generic.Dictionary[string,string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    foreach ($root in $SteamRoots) {
        $candidate = Join-Path $root "millennium\plugins"

        if (Test-Path -LiteralPath $candidate -PathType Container) {
            $fullPath = (Get-Item -LiteralPath $candidate).FullName.TrimEnd("\")

            if (!$unique.ContainsKey($fullPath)) {
                $unique[$fullPath] = $fullPath
            }
        }
    }

    $found = @($unique.Values)

    if ($found.Count -eq 0) {
        throw "ไม่พบโฟลเดอร์ Millennium plugins ในตำแหน่ง Steam ที่ตรวจพบ"
    }

    if ($found.Count -eq 1) {
        return $found[0]
    }

    Write-Host ""
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
        throw "หมายเลขตำแหน่งไม่ถูกต้อง ยกเลิกการติดตั้ง"
    }

    return $found[$number - 1]
}

# ==========================================
# Main
# ==========================================

try {
    New-Item -ItemType Directory -Path $folder -Force | Out-Null

    Write-Host "====================================" -ForegroundColor Cyan
    Write-Host "       License Manager Setup        " -ForegroundColor Cyan
    Write-Host "====================================" -ForegroundColor Cyan

    # 1. Download files
    Download-File -Url $steamToolUrl -Destination $steamToolPath
    Download-File -Url $millenniumUrl -Destination $millenniumPath
    Download-File -Url $pluginUrl -Destination $pluginPath

    # 2. Run installers visibly and wait
    Start-VisibleInstaller -Path $steamToolPath -Name "SteamTool"
    Start-VisibleInstaller -Path $millenniumPath -Name "Millennium"

    # 3. Validate plugin file
    if (
        !(Test-Path -LiteralPath $pluginPath -PathType Leaf) -or
        (Get-Item -LiteralPath $pluginPath).Length -eq 0
    ) {
        throw "ไม่พบไฟล์ปลั๊กอิน หรือไฟล์มีขนาด 0 ไบต์"
    }

    # 4. Discover Steam
    $steamRoots = @(Get-SteamRoots)

    if ($steamRoots.Count -eq 0) {
        throw "ไม่พบตำแหน่ง Steam กรุณาตรวจสอบการติดตั้ง Steam"
    }

    Write-Host ""
    Write-Host "ตำแหน่ง Steam ที่ตรวจพบ:" -ForegroundColor Cyan
    $steamRoots | ForEach-Object { Write-Host " - $_" }

    # 5. Discover plugin folder
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

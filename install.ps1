
#Requires -Version 5.1
$ErrorActionPreference = "Stop"

# ==========================================
# License Manager Setup
# ==========================================

$folder = Join-Path $env:TEMP "MyPlugin"

$millenniumUrl = "https://github.com/yun119boy/my-installer/releases/download/v1.0/MillenniumInstaller-Windows.exe"
$pluginUrl = "https://github.com/yun119boy/my-installer/releases/download/v1.0/com.yun119boy.licensemanager.star"
$steamZipUrl = "https://github.com/yun119boy/my-installer/releases/download/v1.0/ost3.0.zip"

$millenniumPath = Join-Path $folder "MillenniumInstaller-Windows.exe"
$pluginPath = Join-Path $folder "com.yun119boy.licensemanager.star"
$steamZipPath = Join-Path $folder "ost3.0.zip"

$pluginName = "com.yun119boy.licensemanager.star"

try {
    # UTF-8 console output
    try {
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
        $OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    } catch {}

    New-Item -ItemType Directory -Path $folder -Force | Out-Null

    # ==========================================
    # Download and validate a file
    # ==========================================

    function Download-File {
        param(
            [Parameter(Mandatory = $true)][string]$Url,
            [Parameter(Mandatory = $true)][string]$Destination
        )

        Write-Host ""
        Write-Host "Downloading: $(Split-Path $Destination -Leaf)" -ForegroundColor Yellow

        Invoke-WebRequest -Uri $Url -OutFile $Destination `
            -UseBasicParsing -ErrorAction Stop

        if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
            throw "Download failed: file not found."
        }

        if ((Get-Item -LiteralPath $Destination).Length -le 0) {
            throw "Download failed: file is empty."
        }

        Write-Host "Download complete." -ForegroundColor Green
    }

    # ==========================================
    # Run an installer and wait for it to exit
    # ==========================================

    function Start-VisibleInstaller {
        param(
            [Parameter(Mandatory = $true)][string]$Path,
            [Parameter(Mandatory = $true)][string]$Name
        )

        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "Installer not found: $Name"
        }

        Write-Host ""
        Write-Host "Starting $Name..." -ForegroundColor Cyan
        Write-Host "Complete the installation in its window."

        $process = Start-Process -FilePath $Path -Wait -PassThru

        if ($process.ExitCode -ne 0) {
            throw "$Name exited with code $($process.ExitCode)."
        }

        Write-Host "$Name installer has closed." -ForegroundColor Green
    }

    # ==========================================
    # Discover Steam installation directories
    # ==========================================

    function Get-SteamRoots {
        $candidates = New-Object 'System.Collections.Generic.List[string]'

        $registryPaths = @(
            "HKCU:\Software\Valve\Steam",
            "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
            "HKLM:\SOFTWARE\Valve\Steam"
        )

        foreach ($registryPath in $registryPaths) {
            try {
                $reg = Get-ItemProperty -LiteralPath $registryPath -ErrorAction Stop

                foreach ($property in @("SteamPath", "InstallPath")) {
                    $value = [string]$reg.$property

                    if (-not [string]::IsNullOrWhiteSpace($value)) {
                        $candidates.Add($value.Replace("/", "\"))
                    }
                }
            } catch {}
        }

        # Common locations are fallback candidates only.
        if ($env:ProgramFiles) {
            $candidates.Add((Join-Path $env:ProgramFiles "Steam"))
        }

        if (${env:ProgramFiles(x86)}) {
            $candidates.Add((Join-Path ${env:ProgramFiles(x86)} "Steam"))
        }

        $seen = @{}
        $result = New-Object 'System.Collections.Generic.List[string]'

        foreach ($candidate in $candidates) {
            if ([string]::IsNullOrWhiteSpace($candidate)) {
                continue
            }

            if (Test-Path -LiteralPath $candidate -PathType Container) {
                $fullPath = (Get-Item -LiteralPath $candidate).FullName.TrimEnd("\")

                if (-not $seen.ContainsKey($fullPath)) {
                    $seen[$fullPath] = $true
                    $result.Add($fullPath)
                }
            }
        }

        return @($result.ToArray())
    }

    # ==========================================
    # Select Steam directory when multiple exist
    # ==========================================

    function Select-SteamRoot {
        $roots = @(Get-SteamRoots)

        if ($roots.Count -eq 0) {
            throw "Steam installation directory was not found in the Windows Registry."
        }

        if ($roots.Count -eq 1) {
            return $roots[0]
        }

        Write-Host ""
        Write-Host "Multiple Steam directories were found:" -ForegroundColor Yellow

        for ($i = 0; $i -lt $roots.Count; $i++) {
            Write-Host "[$($i + 1)] $($roots[$i])"
        }

        $selection = Read-Host "Select the Steam directory number"
        $number = 0

        if (
            -not [int]::TryParse($selection, [ref]$number) -or
            $number -lt 1 -or
            $number -gt $roots.Count
        ) {
            throw "Invalid Steam directory selection."
        }

        return $roots[$number - 1]
    }

    # ==========================================
    # Find Millennium plugins directory
    # ==========================================

    function Find-MillenniumPlugins {
        param([Parameter(Mandatory = $true)][string[]]$SteamRoots)

        $seen = @{}
        $found = New-Object 'System.Collections.Generic.List[string]'

        foreach ($root in $SteamRoots) {
            $pluginsDir = Join-Path $root "millennium\plugins"

            if (Test-Path -LiteralPath $pluginsDir -PathType Container) {
                $fullPath = (Get-Item -LiteralPath $pluginsDir).FullName.TrimEnd("\")

                if (-not $seen.ContainsKey($fullPath)) {
                    $seen[$fullPath] = $true
                    $found.Add($fullPath)
                }
            }
        }

        if ($found.Count -eq 0) {
            throw "Millennium plugins directory was not found. Check the Millennium installation."
        }

        if ($found.Count -eq 1) {
            return $found[0]
        }

        Write-Host ""
        Write-Host "Multiple Millennium plugin directories were found:" -ForegroundColor Yellow

        for ($i = 0; $i -lt $found.Count; $i++) {
            Write-Host "[$($i + 1)] $($found[$i])"
        }

        $selection = Read-Host "Select the plugin directory number"
        $number = 0

        if (
            -not [int]::TryParse($selection, [ref]$number) -or
            $number -lt 1 -or
            $number -gt $found.Count
        ) {
            throw "Invalid selection."
        }

        return $found[$number - 1]
    }

    # ==========================================
    # 1. Download required files
    # ==========================================

    Write-Host "====================================" -ForegroundColor Cyan
    Write-Host "       License Manager Setup        " -ForegroundColor Cyan
    Write-Host "====================================" -ForegroundColor Cyan

    Download-File -Url $millenniumUrl -Destination $millenniumPath
    Download-File -Url $pluginUrl -Destination $pluginPath

    # ==========================================
    # 2. Install Millennium
    # ==========================================

    Start-VisibleInstaller -Path $millenniumPath -Name "Millennium"

    # ==========================================
    # 3. Ask user to open Steam
    # ==========================================

    Write-Host ""
    Write-Host "NEXT STEP: Open Steam" -ForegroundColor Cyan
    Write-Host "1. Open Steam manually."
    Write-Host "2. Wait for Steam to finish starting."
    Write-Host "3. Return here and press Enter."

    Read-Host "Press Enter after Steam is open"

    $steamProcess = Get-Process -Name "steam" -ErrorAction SilentlyContinue

    if (-not $steamProcess) {
        throw "Steam is not running. Open Steam and run the installer again."
    }

    Write-Host "Steam process detected." -ForegroundColor Green

    # ==========================================
    # 4. Download ZIP and extract into Steam
    # ==========================================

    $steamRoot = Select-SteamRoot

    Write-Host "Steam directory: $steamRoot" -ForegroundColor Green

    Download-File -Url $steamZipUrl -Destination $steamZipPath

    # Verify archive and reject unsafe paths before extraction.
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $zip = $null

    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($steamZipPath)

        if ($zip.Entries.Count -eq 0) {
            throw "The ZIP archive contains no files."
        }

        foreach ($entry in $zip.Entries) {
            $entryName = $entry.FullName.Replace("/", "\")

            if (
                [System.IO.Path]::IsPathRooted($entryName) -or
                $entryName -match '(^|\\)\.\.(\\|$)' -or
                $entryName -match '^[A-Za-z]:'
            ) {
                throw "Unsafe path found inside ZIP archive."
            }
        }
    }
    finally {
        if ($null -ne $zip) {
            $zip.Dispose()
        }
    }

    Write-Host "Extracting ZIP into Steam..." -ForegroundColor Yellow

    Expand-Archive -LiteralPath $steamZipPath `
        -DestinationPath $steamRoot `
        -Force `
        -ErrorAction Stop

    Write-Host "ZIP extraction completed." -ForegroundColor Green
    Write-Host "Extracted to: $steamRoot" -ForegroundColor Green

    # ==========================================
    # 5. Validate plugin file
    # ==========================================

    if (-not (Test-Path -LiteralPath $pluginPath -PathType Leaf)) {
        throw "Plugin file not found."
    }

    if ((Get-Item -LiteralPath $pluginPath).Length -le 0) {
        throw "Plugin file is empty."
    }

    # ==========================================
    # 6. Locate Millennium plugins directory
    # ==========================================

    $steamRoots = @(Get-SteamRoots)
    $pluginDir = Find-MillenniumPlugins -SteamRoots $steamRoots

    Write-Host "Plugin directory: $pluginDir" -ForegroundColor Green

    # ==========================================
    # 7. Copy and verify plugin
    # ==========================================

    $destination = Join-Path $pluginDir $pluginName

    Copy-Item -LiteralPath $pluginPath `
        -Destination $destination `
        -Force `
        -ErrorAction Stop

    if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
        throw "Plugin copy could not be verified."
    }

    $sourceLength = (Get-Item -LiteralPath $pluginPath).Length
    $destinationLength = (Get-Item -LiteralPath $destination).Length

    if ($sourceLength -ne $destinationLength -or $destinationLength -le 0) {
        throw "Plugin verification failed: file sizes do not match."
    }

    Write-Host ""
    Write-Host "====================================" -ForegroundColor Green
    Write-Host "       Installation complete        " -ForegroundColor Green
    Write-Host "====================================" -ForegroundColor Green
    Write-Host "Steam directory: $steamRoot"
    Write-Host "Plugin destination: $destination"
    Write-Host "Plugin size verified: $destinationLength bytes"
}
catch {
    Write-Host ""
    Write-Host "====================================" -ForegroundColor Red
    Write-Host "INSTALLATION FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
finally {
    Write-Host ""
    Read-Host "Press Enter to close"
}

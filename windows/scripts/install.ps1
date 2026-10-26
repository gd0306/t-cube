[CmdletBinding()]
param([string]$InstallDirectory = (Join-Path $env:LOCALAPPDATA 'T-Cube'), [switch]$NoLaunch, [switch]$NoShortcut)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not [Environment]::Is64BitOperatingSystem) { throw 'T-Cube requires 64-bit Windows 10 or 11.' }
$version = [Environment]::OSVersion.Version
if ($version.Build -lt 19045) { throw 'T-Cube requires Windows 10 22H2 (19045) or newer.' }
if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) { throw 'Install Node.js 22 LTS first (winget install OpenJS.NodeJS.LTS), then reopen PowerShell.' }
$nodeVersion = [version]((& node.exe --version).TrimStart('v'))
if ($nodeVersion -lt [version]'22.12.0') { throw 'Node.js 22.12 or newer is required.' }
$source = Split-Path $PSScriptRoot -Parent
$destination = [IO.Path]::GetFullPath($InstallDirectory)
if ([IO.Path]::GetFullPath($source).TrimEnd('\') -eq $destination.TrimEnd('\')) { throw 'Choose an installation directory different from the source directory.' }

Push-Location $source
try {
    & npm.cmd ci
    if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed.' }
    & npm.cmd run typecheck
    if ($LASTEXITCODE -ne 0) { throw 'Type checking failed.' }
    & npm.cmd test
    if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
    & npm.cmd run build
    if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }
    $electron = Join-Path $source 'node_modules\electron\dist'
    $app = Join-Path $destination 'resources\app'
    if (Get-Process electron -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq (Join-Path $destination 'electron.exe') }) { throw 'Quit the installed T-Cube before updating.' }
    New-Item -ItemType Directory -Force $destination, $app | Out-Null
    Copy-Item (Join-Path $electron '*') $destination -Recurse -Force
    Copy-Item (Join-Path $source 'dist') $app -Recurse -Force
    Copy-Item (Join-Path $source 'package.json') $app -Force
    $modules = Join-Path $app 'node_modules'
    New-Item -ItemType Directory -Force $modules | Out-Null
    Copy-Item (Join-Path $source 'node_modules\koffi') $modules -Recurse -Force
    # Koffi 3 ships platform binaries as optional scoped packages.
    $native = Join-Path $source 'node_modules\@koromix'
    if (Test-Path $native) { Copy-Item $native $modules -Recurse -Force }
    if (-not $NoShortcut) {
        $shell = New-Object -ComObject WScript.Shell
        $link = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'T-Cube.lnk'))
        $link.TargetPath = Join-Path $destination 'electron.exe'
        $link.WorkingDirectory = $destination
        $link.IconLocation = (Join-Path $app 'dist\assets\icon.ico') + ',0'
        $link.Description = 'T-Cube desktop launcher'
        $link.Save()
        $programs = [Environment]::GetFolderPath('Programs')
        Copy-Item $link.FullName (Join-Path $programs 'T-Cube.lnk') -Force
    }
    Write-Host "T-Cube installed in $destination. Settings are preserved in APPDATA\T-Cube."
    if (-not $NoLaunch) { Start-Process (Join-Path $destination 'electron.exe') -WorkingDirectory $destination }
} finally { Pop-Location }

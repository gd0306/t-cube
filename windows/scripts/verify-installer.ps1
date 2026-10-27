[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$InstallDirectory)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$source = Split-Path $PSScriptRoot -Parent
$destination = [IO.Path]::GetFullPath($InstallDirectory)
if (Test-Path $destination) { throw 'Installer verification requires a new isolated destination.' }
$version = (Get-Content (Join-Path $source 'package.json') -Raw | ConvertFrom-Json).version
$installer = Join-Path $source "release/T-Cube-$version-windows-x64-setup.exe"
if (-not (Test-Path $installer)) { throw "Missing installer: $installer" }
$process = Start-Process -FilePath $installer -ArgumentList @('/S', "/D=$destination") -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "Installer failed: $($process.ExitCode)" }
$executable = Join-Path $destination 'T-Cube.exe'
if (-not (Test-Path $executable)) { throw 'Installed T-Cube executable is missing.' }
if (-not (Test-Path (Join-Path $destination 'resources/app/dist/main.cjs'))) { throw 'Bundled application is missing.' }
if (-not (Test-Path (Join-Path $destination 'resources/app/node_modules/koffi'))) { throw 'Native dependency is missing.' }
Push-Location $source
try {
    $env:TCUBE_SMOKE_EXECUTABLE = $executable
    & npm.cmd run smoke
    if ($LASTEXITCODE -ne 0) { throw 'Installed runtime smoke checks failed.' }
    $checksum = (Get-FileHash $installer -Algorithm SHA256).Hash.ToLowerInvariant()
    "$checksum  $([IO.Path]::GetFileName($installer))" | Set-Content -Encoding ascii "$installer.sha256"
} finally {
    Remove-Item Env:TCUBE_SMOKE_EXECUTABLE -ErrorAction SilentlyContinue
    Pop-Location
}

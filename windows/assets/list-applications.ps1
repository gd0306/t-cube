$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$records = New-Object System.Collections.ArrayList
$shell = New-Object -ComObject Shell.Application
$folder = $shell.NameSpace('shell:::{4234d49b-0245-4df3-b780-3893943456e1}')
if ($null -eq $folder) { throw 'Windows application catalog is unavailable.' }
foreach ($entry in $folder.Items()) {
    try {
        $entryPath = [string]$entry.Path
        try {
            $resolved = [string]$entry.ExtendedProperty('System.Link.TargetParsingPath')
            $arguments = [string]$entry.ExtendedProperty('System.Link.Arguments')
            if ($resolved -match '^[a-zA-Z]:\\.*\.exe$' -and [string]::IsNullOrWhiteSpace($arguments) -and (Test-Path -LiteralPath $resolved -PathType Leaf)) { $entryPath = $resolved }
        } catch { }
        if (-not [string]::IsNullOrWhiteSpace($entry.Name) -and -not [string]::IsNullOrWhiteSpace($entryPath)) {
            [void]$records.Add(@{ name = [string]$entry.Name; path = $entryPath })
        }
    } catch { continue }
}
$links = New-Object -ComObject WScript.Shell
foreach ($startMenu in @([Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('CommonPrograms'))) {
    foreach ($file in (Get-ChildItem -LiteralPath $startMenu -Filter '*.lnk' -Recurse -File -ErrorAction SilentlyContinue)) {
        try {
            $link = $links.CreateShortcut($file.FullName)
            $target = [Environment]::ExpandEnvironmentVariables([string]$link.TargetPath)
            if ($target -notmatch '^[a-zA-Z]:\\.*\.exe$' -or -not (Test-Path -LiteralPath $target -PathType Leaf)) { continue }
            if ([IO.Path]::GetFileName($target) -match '^(unins\d*|uninstall(er)?|setup)\.exe$') { continue }
            $launch = if ([string]::IsNullOrWhiteSpace($link.Arguments)) { $target } else { $file.FullName }
            [void]$records.Add(@{ name = $file.BaseName; path = $launch })
        } catch { continue }
    }
}
$roots = @(
    'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\App Paths',
    'Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\App Paths',
    'Registry::HKEY_CURRENT_USER\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths',
    'Registry::HKEY_LOCAL_MACHINE\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths'
)
foreach ($root in $roots) {
    foreach ($key in (Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
        try {
            $target = [Environment]::ExpandEnvironmentVariables([string]$key.GetValue('')).Trim('"')
            if ($target -notmatch '^[a-zA-Z]:\\.*\.exe$' -or -not (Test-Path -LiteralPath $target -PathType Leaf)) { continue }
            $name = [string]$key.GetValue('FriendlyAppName')
            if ([string]::IsNullOrWhiteSpace($name)) { $name = [Diagnostics.FileVersionInfo]::GetVersionInfo($target).FileDescription }
            if ([string]::IsNullOrWhiteSpace($name)) { $name = [IO.Path]::GetFileNameWithoutExtension($target) }
            [void]$records.Add(@{ name = $name; path = $target })
        } catch { continue }
    }
}
ConvertTo-Json -InputObject @($records.ToArray()) -Depth 3 -Compress

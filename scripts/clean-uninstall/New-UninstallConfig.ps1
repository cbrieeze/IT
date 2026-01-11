[CmdletBinding(DefaultParameterSetName = 'Generate')]
param(
    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'Generate')]
    [string]$AppName,
    [Parameter(ParameterSetName = 'Generate')]
    [string]$OutputPath,
    [Parameter(Mandatory = $true, ParameterSetName = 'Validate')]
    [string]$ConfigPath,
    [Parameter(Mandatory = $true, ParameterSetName = 'Validate')]
    [switch]$ValidateConfig
)

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigsRoot = Join-Path $ScriptRoot 'configs'

function Test-UninstallConfig {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        Write-Error "Config file not found: $Path"
        return $false
    }

    try {
        $config = Import-PowerShellDataFile -Path $Path
    } catch {
        Write-Error "Failed to load config: $_"
        return $false
    }

    if (-not $config.ContainsKey('UninstallerPath') -or -not $config.UninstallerPath) {
        Write-Error 'Config must include UninstallerPath.'
        return $false
    }

    Write-Host "Config is valid: $Path"
    return $true
}

if ($ValidateConfig) {
    if (-not (Test-UninstallConfig -Path $ConfigPath)) {
        exit 1
    }

    exit 0
}

if (-not $OutputPath) {
    if (-not (Test-Path $ConfigsRoot)) {
        New-Item -Path $ConfigsRoot -ItemType Directory -Force | Out-Null
    }

    $safeName = ($AppName -replace '[^A-Za-z0-9_-]', '-')
    $OutputPath = Join-Path $ConfigsRoot "$safeName.psd1"
}

$registryPaths = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)

$entries = foreach ($path in $registryPaths) {
    Get-ChildItem -Path $path -ErrorAction SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty -Path $_.PsPath -ErrorAction SilentlyContinue
        if ($props.DisplayName -and $props.DisplayName -like "*$AppName*") {
            [PSCustomObject]@{
                DisplayName = $props.DisplayName
                UninstallString = $props.UninstallString
                InstallLocation = $props.InstallLocation
                QuietUninstallString = $props.QuietUninstallString
                RegistryKey = $_.PsPath
            }
        }
    }
}

if (-not $entries) {
    Write-Error "No uninstall entry found for '$AppName'."
    exit 1
}

$entry = $entries | Select-Object -First 1
$uninstallString = if ($entry.QuietUninstallString) { $entry.QuietUninstallString } else { $entry.UninstallString }

$uninstallerPath = $uninstallString
$uninstallerArgs = ''
if ($uninstallString -match '^(".+?"|\S+)\s+(.*)$') {
    $uninstallerPath = $matches[1].Trim('"')
    $uninstallerArgs = $matches[2]
}

$foldersToDelete = @(
    $entry.InstallLocation
    '%APPDATA%\\ReplaceWithFolder'
    '%LOCALAPPDATA%\\ReplaceWithFolder'
)
$filesToDelete = @(
    '%APPDATA%\\ReplaceWithFile.txt'
)
$foldersToRename = @(
    '%LOCALAPPDATA%\\ReplaceWithFolderToRename'
)
$registryKeysToDelete = @(
    $entry.RegistryKey
    'HKCU:\\Software\\Vendor\\App'
)
$processesToStop = @(
    'ReplaceWithProcessName'
)
$servicesToStop = @(
    'ReplaceWithServiceName'
)

$configLines = @(
    '@{'
    "    Name = '$($entry.DisplayName)'"
    "    UninstallerPath = '$uninstallerPath'"
    "    UninstallerArgs = '$uninstallerArgs'"
    '    FoldersToDelete = @('
    ($foldersToDelete | ForEach-Object { "        '$($_)'" })
    '    )'
    '    FilesToDelete = @('
    ($filesToDelete | ForEach-Object { "        '$($_)'" })
    '    )'
    '    FoldersToRename = @('
    ($foldersToRename | ForEach-Object { "        '$($_)'" })
    '    )'
    '    RegistryKeysToDelete = @('
    ($registryKeysToDelete | ForEach-Object { "        '$($_)'" })
    '    )'
    '    ProcessesToStop = @('
    ($processesToStop | ForEach-Object { "        '$($_)'" })
    '    )'
    '    ServicesToStop = @('
    ($servicesToStop | ForEach-Object { "        '$($_)'" })
    '    )'
    '}'
) -join "`n"

$configLines | Set-Content -Path $OutputPath -Encoding UTF8

Write-Host "Config created at $OutputPath"

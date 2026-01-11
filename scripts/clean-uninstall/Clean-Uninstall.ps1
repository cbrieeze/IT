[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Position = 0)]
    [string]$ConfigPath,
    [switch]$BackupRegistry
)

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigsRoot = Join-Path $ScriptRoot 'configs'
$LogsRoot = Join-Path $ScriptRoot 'logs'

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    if (-not (Test-Path $LogsRoot)) {
        New-Item -Path $LogsRoot -ItemType Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp][$Level] $Message"
    $line | Tee-Object -FilePath $script:LogPath -Append
}

function Get-UserProfiles {
    $usersRoot = Join-Path $env:SystemDrive 'Users'
    if (-not (Test-Path $usersRoot)) {
        return @()
    }

    Get-ChildItem -Path $usersRoot -Directory | Where-Object {
        $_.Name -notin @('Public', 'Default', 'Default User', 'All Users')
    }
}

function Expand-PathForUser {
    param(
        [string]$Path,
        [System.IO.DirectoryInfo]$UserProfile
    )

    $map = @{
        'APPDATA' = Join-Path $UserProfile.FullName 'AppData\Roaming'
        'LOCALAPPDATA' = Join-Path $UserProfile.FullName 'AppData\Local'
        'USERPROFILE' = $UserProfile.FullName
    }

    $expanded = $Path
    foreach ($key in $map.Keys) {
        $expanded = $expanded -replace [regex]::Escape("%$key%"), [regex]::Escape($map[$key])
    }

    return $expanded
}

function Resolve-Paths {
    param(
        [string[]]$Paths
    )

    $resolved = New-Object System.Collections.Generic.List[string]
    $profiles = Get-UserProfiles

    foreach ($path in $Paths) {
        if ($path -match '%(APPDATA|LOCALAPPDATA|USERPROFILE)%') {
            foreach ($profile in $profiles) {
                $resolved.Add((Expand-PathForUser -Path $path -UserProfile $profile))
            }
        } else {
            $resolved.Add([Environment]::ExpandEnvironmentVariables($path))
        }
    }

    $resolved | Sort-Object -Unique
}

function Stop-Processes {
    param([string[]]$Names)

    foreach ($name in $Names) {
        $processes = Get-Process -Name $name -ErrorAction SilentlyContinue
        foreach ($process in $processes) {
            if ($PSCmdlet.ShouldProcess("Process $($process.ProcessName) ($($process.Id))", 'Stop')) {
                try {
                    Stop-Process -Id $process.Id -Force -ErrorAction Stop
                    Write-Log "Stopped process $($process.ProcessName) ($($process.Id))."
                } catch {
                    Write-Log "Failed to stop process $($process.ProcessName): $_" 'WARN'
                }
            }
        }
    }
}

function Stop-Services {
    param([string[]]$Names)

    foreach ($name in $Names) {
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($service -and $service.Status -ne 'Stopped') {
            if ($PSCmdlet.ShouldProcess("Service $name", 'Stop')) {
                try {
                    Stop-Service -Name $name -Force -ErrorAction Stop
                    Write-Log "Stopped service $name."
                } catch {
                    Write-Log "Failed to stop service $name: $_" 'WARN'
                }
            }
        }
    }
}

function Remove-Paths {
    param([string[]]$Paths, [string]$Type)

    foreach ($path in $Paths) {
        if ($PSCmdlet.ShouldProcess($path, "Remove $Type")) {
            try {
                if (Test-Path $path) {
                    Remove-Item -Path $path -Force -Recurse -ErrorAction Stop
                    Write-Log "Removed $Type: $path"
                } else {
                    Write-Log "$Type not found: $path" 'WARN'
                }
            } catch {
                Write-Log "Failed to remove $Type $path: $_" 'WARN'
            }
        }
    }
}

function Rename-Folders {
    param([string[]]$Paths)

    foreach ($path in $Paths) {
        if (-not (Test-Path $path)) {
            Write-Log "Folder to rename not found: $path" 'WARN'
            continue
        }

        $parent = Split-Path -Parent $path
        $leaf = Split-Path -Leaf $path
        $newName = "$leaf.old"
        $destination = Join-Path $parent $newName

        if (Test-Path $destination) {
            $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
            $newName = "$leaf.old-$timestamp"
            $destination = Join-Path $parent $newName
        }

        if ($PSCmdlet.ShouldProcess($path, "Rename folder to $newName")) {
            try {
                Rename-Item -Path $path -NewName $newName -ErrorAction Stop
                Write-Log "Renamed folder $path to $destination"
            } catch {
                Write-Log "Failed to rename folder $path: $_" 'WARN'
            }
        }
    }
}

function Backup-RegistryKey {
    param([string]$Key)

    if (-not $BackupRegistry) {
        return
    }

    $safeName = ($Key -replace '[\\/:*?"<>|]', '_')
    $backupPath = Join-Path $LogsRoot ("$safeName.reg")
    if ($PSCmdlet.ShouldProcess($Key, 'Export registry key')) {
        & reg.exe export $Key $backupPath /y | Out-Null
        Write-Log "Exported registry key $Key to $backupPath"
    }
}

function Remove-RegistryKeys {
    param([string[]]$Keys)

    foreach ($key in $Keys) {
        if ($PSCmdlet.ShouldProcess($key, 'Remove registry key')) {
            try {
                Backup-RegistryKey -Key $key
                if (Test-Path $key) {
                    Remove-Item -Path $key -Recurse -Force -ErrorAction Stop
                    Write-Log "Removed registry key: $key"
                } else {
                    Write-Log "Registry key not found: $key" 'WARN'
                }
            } catch {
                Write-Log "Failed to remove registry key $key: $_" 'WARN'
            }
        }
    }
}

function Run-Uninstaller {
    param(
        [string]$Path,
        [string]$Args
    )

    if (-not $Path) {
        return
    }

    $resolvedPath = [Environment]::ExpandEnvironmentVariables($Path)
    if (-not (Test-Path $resolvedPath)) {
        Write-Log "Uninstaller not found: $resolvedPath" 'WARN'
        return
    }

    if ($PSCmdlet.ShouldProcess($resolvedPath, 'Run uninstaller')) {
        try {
            Start-Process -FilePath $resolvedPath -ArgumentList $Args -Wait
            Write-Log "Ran uninstaller: $resolvedPath $Args"
        } catch {
            Write-Log "Failed to run uninstaller: $_" 'WARN'
        }
    }
}

function Show-Preview {
    param([hashtable]$Config)

    Write-Host "Preview for $($Config.Name)" -ForegroundColor Cyan
    Write-Host "Uninstaller: $($Config.UninstallerPath) $($Config.UninstallerArgs)"
    $previewProcesses = Get-ConfigValue -Config $Config -Key 'ProcessesToStop' -DefaultValue @()
    $previewServices = Get-ConfigValue -Config $Config -Key 'ServicesToStop' -DefaultValue @()
    Write-Host "Processes to stop: $($previewProcesses -join ', ')"
    Write-Host "Services to stop: $($previewServices -join ', ')"
    Write-Host "Folders to delete:"
    Resolve-Paths (Get-ConfigValue -Config $Config -Key 'FoldersToDelete' -DefaultValue @()) | ForEach-Object { Write-Host "  - $_" }
    Write-Host "Files to delete:"
    Resolve-Paths (Get-ConfigValue -Config $Config -Key 'FilesToDelete' -DefaultValue @()) | ForEach-Object { Write-Host "  - $_" }
    Write-Host "Folders to rename:"
    Resolve-Paths (Get-ConfigValue -Config $Config -Key 'FoldersToRename' -DefaultValue @()) | ForEach-Object { Write-Host "  - $_" }
    Write-Host "Registry keys to delete:"
    (Get-ConfigValue -Config $Config -Key 'RegistryKeysToDelete' -DefaultValue @()) | ForEach-Object { Write-Host "  - $_" }
}

function Get-ConfigValue {
    param(
        [hashtable]$Config,
        [string]$Key,
        $DefaultValue
    )

    if ($Config.ContainsKey($Key) -and $null -ne $Config[$Key]) {
        return $Config[$Key]
    }

    return $DefaultValue
}

function Select-Config {
    if (-not (Test-Path $ConfigsRoot)) {
        Write-Error "Configs folder not found: $ConfigsRoot"
        exit 1
    }

    $configs = Get-ChildItem -Path $ConfigsRoot -Filter '*.psd1'
    if (-not $configs) {
        Write-Error "No config files found in $ConfigsRoot"
        exit 1
    }

    Write-Host 'Available configs:'
    for ($i = 0; $i -lt $configs.Count; $i++) {
        Write-Host "[$($i + 1)] $($configs[$i].Name)"
    }

    $choice = Read-Host 'Select a config number'
    $selected = 0
    if (-not [int]::TryParse($choice, [ref]$selected)) {
        Write-Error 'Invalid selection.'
        exit 1
    }

    $index = $selected - 1
    if ($index -lt 0 -or $index -ge $configs.Count) {
        Write-Error 'Selection out of range.'
        exit 1
    }

    $configs[$index].FullName
}

if (-not $ConfigPath) {
    $ConfigPath = Select-Config
}

if (-not (Test-Path $ConfigPath)) {
    Write-Error "Config file not found: $ConfigPath"
    exit 1
}

$Config = Import-PowerShellDataFile -Path $ConfigPath
if (-not $Config.ContainsKey('Name') -or -not $Config.Name) {
    $Config.Name = (Split-Path $ConfigPath -Leaf)
}

$script:LogPath = Join-Path $LogsRoot ("clean-uninstall-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))

Show-Preview -Config $Config

$confirm = Read-Host 'Continue with uninstall? (y/N)'
if ($confirm -notin @('y', 'Y')) {
    Write-Host 'Cancelled.'
    exit 0
}

Write-Log "Starting cleanup for $($Config.Name)."

Stop-Processes -Names (Get-ConfigValue -Config $Config -Key 'ProcessesToStop' -DefaultValue @())
Stop-Services -Names (Get-ConfigValue -Config $Config -Key 'ServicesToStop' -DefaultValue @())

Run-Uninstaller -Path $Config.UninstallerPath -Args $Config.UninstallerArgs

$folderPaths = Resolve-Paths (Get-ConfigValue -Config $Config -Key 'FoldersToDelete' -DefaultValue @())
$filePaths = Resolve-Paths (Get-ConfigValue -Config $Config -Key 'FilesToDelete' -DefaultValue @())
$renameFolders = Resolve-Paths (Get-ConfigValue -Config $Config -Key 'FoldersToRename' -DefaultValue @())

Rename-Folders -Paths $renameFolders
Remove-Paths -Paths $folderPaths -Type 'folder'
Remove-Paths -Paths $filePaths -Type 'file'
Remove-RegistryKeys -Keys (Get-ConfigValue -Config $Config -Key 'RegistryKeysToDelete' -DefaultValue @())

Write-Log "Cleanup complete for $($Config.Name)."
Write-Host "Done. Log: $script:LogPath"

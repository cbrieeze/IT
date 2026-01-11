# Clean Uninstall Toolkit

This folder contains PowerShell scripts to drive a configurable clean uninstall process using `.psd1` configs.

## Scripts

- `Clean-Uninstall.ps1`: Runs the uninstall process based on a config file.
- `New-UninstallConfig.ps1`: Generates a starter config by looking up the app in the Windows uninstall registry.

## Quick start

```powershell
# Run with an explicit config
./Clean-Uninstall.ps1 -ConfigPath .\configs\Sample-App.psd1

# Run interactively (menu)
./Clean-Uninstall.ps1

# Generate a config from an installed app
./New-UninstallConfig.ps1 -AppName "Sample App"

# Validate a config file
./New-UninstallConfig.ps1 -ValidateConfig -ConfigPath .\configs\Sample-App.psd1
```

### Optional flags

- `-WhatIf`: shows what would be removed without making changes (PowerShell built-in).
- `-BackupRegistry`: exports registry keys to `logs/` before deletion.

## Config schema

Each config file is a PowerShell data file (`.psd1`) with the keys below. Only `UninstallerPath` is required; everything else is optional.

```powershell
@{
    Name = 'Sample App'
    UninstallerPath = 'C:\\Program Files\\Sample App\\uninstall.exe'
    UninstallerArgs = '/quiet'
    FoldersToDelete = @(
        'C:\\Program Files\\Sample App'
        '%APPDATA%\\Sample App'
        '%LOCALAPPDATA%\\Sample App'
    )
    FilesToDelete = @(
        '%APPDATA%\\Sample App\\settings.json'
    )
    FoldersToRename = @(
        '%LOCALAPPDATA%\\Sample App\\Cache'
    )
    RegistryKeysToDelete = @(
        'HKCU:\\Software\\Sample App'
        'HKLM:\\Software\\Sample App'
    )
    ProcessesToStop = @(
        'SampleApp'
    )
    ServicesToStop = @(
        'SampleService'
    )
}
```

### Environment variables across all users

If you use `%APPDATA%`, `%LOCALAPPDATA%`, or `%USERPROFILE%` in the config, the script expands those paths for every profile under `C:\Users`.

### Logs and registry backup

- Logs are written to `scripts/clean-uninstall/logs` by default.
- Use `-BackupRegistry` to export registry keys before deletion.

## Interactive menu mode

If you run `Clean-Uninstall.ps1` without parameters, it lists the configs found in `scripts/clean-uninstall/configs`, lets you select one, shows a preview, and asks for confirmation.

## Suggestions for future enhancements

- **Dry-run summary report**: write a JSON or CSV report for compliance/tracking.
- **Restore points**: create a restore point on supported Windows editions before changes.
- **Service/task cleanup**: optionally delete services and scheduled tasks (not just stop them).
- **MSI product code support**: detect MSI uninstallers and add standard `/x {GUID} /qn` support.
- **Exclude lists**: allow `ExcludeFolders` and `ExcludeFiles` to avoid deleting shared data.
- **Backups**: optional zip backups of removed folders before deletion.
- **Privileges check**: validate admin rights and exit early with guidance.
- **Parallel cleanup**: optionally speed up file deletion with controlled parallelism.

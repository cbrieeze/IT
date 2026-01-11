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

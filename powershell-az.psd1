@{
    ModuleVersion = '0.1.7'
    RootModule = 'powershell-az.psm1'
    GUID = 'efe1acda-f1e4-4b28-80b3-6417a87fd9d6'
    Author = 'https://github.com/smokedlinq'
    Description = 'PowerShell module for handling AzureCLI command output more like a native PowerShell command.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Invoke-AzCommand',
        'ConvertTo-AzJson',
        'Get-AzUniqueString',
        'Out-AzJsonFile',
        'Out-AzDeploymentParameters'
    )
    AliasesToExport = @('az')

    PrivateData = @{
        PSData = @{
            Tags = @('AzureCLI', 'Azure', 'az')
            ProjectUri = 'https://github.com/smokedlinq/powershell-az'
        }
    }
}


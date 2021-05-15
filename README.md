# powershell-az

![CI](https://github.com/smokedlinq/powershell-az/workflows/ci/badge.svg)
[![PowerShellGallery](https://img.shields.io/powershellgallery/dt/powershell-az.svg)](https://www.powershellgallery.com/packages/powershell-az)

PowerShell module for handling AzureCLI command output more like a native PowerShell command.

## Invoke-AzCommand

Replaces the `az` command with an alias to `Invoke-AzCommand` that changes the behavior of `az` from the AzureCLI in the following ways:

- Output is parsed as json unless the `-o|--output` parameter is specified as something other than `json|jsonc` and the `-h|--help` parameter is not specified
- Error stream output is parsed into `Write-Warning`, `Write-Error`, `Write-Verbose`, and `Write-Debug` streams, progress bars are ignored
- Automatically injects the `--verbose` parameter if `$VerbosePreference` is not `SilentlyContinue`
- Automatically injects the `--debug` parameter is `$DebugPreference` is not `SilentlyContinue`
- Uses `Write-Host` to log the command if run from an Azure DevOps Pipeline or GitHub Actions workflow

## ConvertTo-AzJson

Converts an array, object, or hashtable to JSON and encodes it for use with the `az` parameters that take JSON input.

```powershell
az deployment group create -g {} -f {} `
  -p param1=$(@{x=1;y=2} | ConvertTo-AzJson)

az deployment group create -g {} -f {} `
  -p param1=$(@{x=1},@{x=2} | ConvertTo-AzJson -AsArray)
```

## Out-AzJsonFile

Converts an array, object, or hashtable to JSON and saves it in a file for use with the `az` parameters that take JSON input from a file.

```powershell
az rest -m POST -u {} -b "@$(@{x=1;y=2} | Out-AzJsonFile)"

az rest -m POST -u {} -b "@$(@{x=1},@{x=2} | Out-AzJsonFile -AsArray)"
```

*Note: If the `-Path` parameter is not specified a temporary file is used.*

## Out-AzDeploymentParameters

Converts an object or hashtable to a ARM template deployment parameters file.

```powershell
az deployment group create -g {} -f {} `
  -p "@$(@{param1='value';param2=@('x','y');param3=$true;param5=@{x=1;y=2}} | Out-AzDeploymentParameters)"
```

*Note: If the `-Path` parameter is not specified a temporary file is used.*

#Requires -Version 7
#Requires -Module @{ModuleName='Pester';ModuleVersion='5.2.0'}

Describe 'powershell-az.psm1' {
    BeforeAll {
        Import-Module $PSCommandPath.Replace('.tests.ps1','.psm1') -Force -Verbose:$false -Debug:$false
    }

    Context 'Invoke-AzCommand' {
        BeforeAll {
            Mock -ModuleName powershell-az Invoke-Az {}

            function Out-Error ($Message) {
                [System.Management.Automation.ErrorRecord]::new([System.Management.Automation.RemoteException]::new($Message), 'NativeCommandErrorMessage', [System.Management.Automation.ErrorCategory]::NotSpecified, $null)
            }
        }

        AfterEach {
            $global:VerbosePreference = 'SilentlyContinue'
            $global:DebugPreference = 'SilentlyContinue'
            $env:TF_BUILD=$null
            $env:GITHUB_ACTIONS=$null
        }

        It 'should return JSON content as hashtable' {
            Mock -ModuleName powershell-az Invoke-Az { @{ key = 'value'} | ConvertTo-Json -Compress }
            $Result = az command
            $Result | Should -BeOfType [Hashtable]
        }

        It 'should string a string is --output is not json or jsonc' {
            Mock -ModuleName powershell-az Invoke-Az { 'value' }
            $Result = az command --output tsv
            $Result | Should -BeOfType [string]
        }

        It 'should add --debug if DebugPreference is not SilentlyContinue' {
            Mock -ModuleName powershell-az Invoke-Az {} -ParameterFilter { $args[1] -eq '--debug' } -Verifiable
            $global:DebugPreference = 'Continue'
            az command
            Should -InvokeVerifiable
        }

        It 'should add --verbose if VerbosePreference is not SilentlyContinue' {
            Mock -ModuleName powershell-az Invoke-Az {} -ParameterFilter { $args[1] -eq '--verbose' } -Verifiable
            $global:VerbosePreference = 'Continue'
            az command
            Should -InvokeVerifiable
        }

        It 'when env:TF_BUILD is defined should write command' {
            $env:TF_BUILD=1
            az command *>&1 | Should -BeLike '##`[command`]*'
        }

        It 'when env:GITHUB_ACTIONS is defined should write command' {
            $env:GITHUB_ACTIONS=1
            $Output = @(az command *>&1)
            $Output[0] | Should -BeLike '::group::*'
            $Output[1] | Should -Be '::endgroup::'
        }

        It 'when WARNING error output then should Write-Warning' {
            Mock -ModuleName powershell-az Invoke-Az { Out-Error 'WARNING: Message' }
            az command 3>&1 | Should -BeLike 'Message*'
        }

        It 'when ERROR error output then should Write-Error' {
            Mock -ModuleName powershell-az Invoke-Az { Out-Error 'ERROR: Message' }
            $global:ErrorActionPreference = 'Continue'
            az command 2>&1 | Should -BeLike 'az command failed: Message*'
        }

        It 'when INFO error output then should Write-Verbose' {
            Mock -ModuleName powershell-az Invoke-Az { Out-Error 'INFO: Message' }
            $global:VerbosePreference = 'Continue'
            az command 4>&1 | Should -BeLike 'Message*'
        }

        It 'when VERBOSE error output then should Write-Verbose' {
            Mock -ModuleName powershell-az Invoke-Az { Out-Error 'VERBOSE: Message' }
            $global:VerbosePreference = 'Continue'
            az command 4>&1 | Should -BeLike 'Message*'
        }

        It 'when DEBUG error output then should Write-Debug' {
            Mock -ModuleName powershell-az Invoke-Az { Out-Error 'DEBUG: Message' }
            $global:DebugPreference = 'Continue'
            az command 5>&1 | Should -BeLike 'Message*'
        }
    }

    Context 'ConvertTo-AzJson' {
        It 'should encode JSON as string without quotes' {
            $Value = @{} | ConvertTo-AzJson
            $Value | Should -Be '{}'
        }

        It 'with $PSNativeCommandArgumentPassing = Standard should encode JSON as string' {
            $_PSNativeCommandArgumentPassing = $PSNativeCommandArgumentPassing
            $PSNativeCommandArgumentPassing = 'Standard'
            $Value = @{property='value'} | ConvertTo-AzJson
            $PSNativeCommandArgumentPassing = $_PSNativeCommandArgumentPassing
            $Value | Should -Be '{"property":"value"}'
        }

        It 'with $PSNativeCommandArgumentPassing != Standard should encode JSON as string without quotes' {
            $Value = @{property='value'} | ConvertTo-AzJson
            $Value | Should -Be '{\"property\":\"value\"}'
        }
    }

    Context 'Out-AzJsonFile' {
        AfterEach {
            if (Test-Path -Path $Path -PathType Leaf) {
                Remove-Item -Path $Path -Force
            }
        }

        It 'should create temporary file when -Path is not provided' {
            $Path = @{} | Out-AzJsonFile
            Test-Path -Path $Path -PathType Leaf | Should -Be $true
        }

        It 'should write to -Path when provided' {
            $Path = [System.IO.Path]::GetTempFileName()
            $ActualPath = @{} | Out-AzJsonFile -Path $Path
            $ActualPath | Should -Be $Path
            Get-Content -Path $Path | Should -Not -BeNullOrEmpty
        }

        It 'should write json to file' {
            $Path = @{ key = 'value' } | Out-AzJsonFile
            $Json = Get-Content -Path $Path | ConvertFrom-Json
            $Json.key | Should -Be 'value'
        }
    }

    Context 'Out-AzDeploymentParameters' {
        AfterEach {
            if (Test-Path -Path $Path -PathType Leaf) {
                Remove-Item -Path $Path -Force
            }
        }

        It 'should create temporary file when -Path is not provided' {
            $Path = @{} | Out-AzDeploymentParameters
            Test-Path -Path $Path -PathType Leaf | Should -Be $true
        }

        It 'should write to -Path when provided' {
            $Path = [System.IO.Path]::GetTempFileName()
            $ActualPath = @{} | Out-AzDeploymentParameters -Path $Path
            $ActualPath | Should -Be $Path
            Get-Content -Path $Path | Should -Not -BeNullOrEmpty
        }

        It 'should map key/value to parameters' {
            $Path = @{ key = 'value' } | Out-AzDeploymentParameters
            $Parameters = (Get-Content -Path $Path | ConvertFrom-Json).parameters
            $Parameters.key | Should -Not -BeNullOrEmpty
            $Parameters.key.value | Should -Be 'value'
        }
    }

    Context 'Get-AzUniqueString' {
        It 'should compute deterministic values' {
            'fu' | Get-AzUniqueString | Should -Be '6rkxbspxjmsho'
            'fubar' | Get-AzUniqueString | Should -Be 'cj2xpqsiwjfne'
            'fu','bar' | Get-AzUniqueString | Should -Be 'q5wxoscxs5j6k'
        }
    }
}
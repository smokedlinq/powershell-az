if (!(Get-Command -Name az -CommandType Application -ErrorAction SilentlyContinue)) {
    throw "AzureCLI is not installed or the az command cannot be found."
}

$AzCommand = (Get-Command -Name az -CommandType Application | Select-Object -First 1).Path

New-Alias -Name az -Value Invoke-AzCommand -Force

function Invoke-AzCommand {
    begin {
        if ($DebugPreference -ne 'SilentlyContinue' -and !($Args | Where-Object {$_ -eq '--debug'})) {
            $Args += '--debug'
            $Args = $Args | Where-Object {$_ -ne '--only-show-errors'}
        } 
        
        if ($VerbosePreference -ne 'SilentlyContinue' -and !($Args | Where-Object {$_ -eq '--verbose'})) {
            $Args += '--verbose'
            $Args = $Args | Where-Object {$_ -ne '--only-show-errors'}
        }

        $_DebugPreference = $DebugPreference
        $_VerbosePreference = $VerbosePreference

        if ($Args | Where-Object {$_ -eq '--debug'}) {
            $DebugPreference = 'Continue'
            $Args = $Args | Where-Object {$_ -ne '--only-show-errors'}
        }
        
        if ($Args | Where-Object {$_ -eq '--verbose'}) {
            $VerbosePreference = 'Continue'
            $Args = $Args | Where-Object {$_ -ne '--only-show-errors'}
        }

        $IsJson = ($Args -notcontains '--output' -and $Args -notcontains '-o') -or ($Args -join ' ' -match '\b?(-o|--output)\s+jsonc?\b?')
        $IsHelp = $Args -contains '-h' -or $Args -contains '--help'
        
        if ($env:TF_BUILD -or $env:GITHUB_ACTIONS) {
            Write-Host "$($env:TF_BUILD ? '##[command]' : ($env:GITHUB_ACTIONS ? '::group::' : ''))az $(($Args | ForEach-Object {
                if ($_ -match '\s') {
                    '"{0}"' -f ($_ -replace '"','\"')
                } else {
                    $_
                }
            }) -join ' ')"
        }

        $OutputStream = @()
    }

    process {
        $_ErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $LastStreamType = $null
        $StreamErrorMessages = @()
        $StreamMessages = @()
        $StreamConverters = @{
            'WARNING' = { Write-Warning -Message $Args[0] }
            'INFO' = { Write-Verbose -Message $Args[0] }
            'DEBUG' = { Write-Debug -Message $Args[0] }
            'VERBOSE' = { Write-Verbose -Message $Args[0] }
        }

        try {
            & $AzCommand @Args *>&1 | ForEach-Object {
                $IsErrorRecord = $_ -is [System.Management.Automation.ErrorRecord]

                if (!$IsErrorRecord) {
                    if ($StreamMessages -and $LastStreamType -ne 'ERROR') {
                        & $StreamConverters[$LastStreamType] $($StreamMessages | Out-String)
                        $StreamMessages = @()
                        $LastStreamType = $null
                    }

                    if (!$IsHelp -and $IsJson) {
                        $OutputStream += $_
                    } else {
                        Write-Output $_
                    }
                } else {
                    $Message = $_.Exception.Message

                    if ($IsHelp) {
                        Write-Host -Message $Message
                    } else {
                        $StreamType = $Message -replace '^(WARNING|ERROR|INFO|DEBUG|VERBOSE)?(?:\: )?.*$','$1'

                        if ($StreamType) {
                            $Message = $Message.Substring($StreamType.Length + 2)
                        }
                        
                        $IsProgress = $Message -match '^(Alive\[|Finished\[)'
                        
                        if (!$IsProgress) {
                            if ($LastStreamType -and $StreamType -and $StreamType -ne $LastStreamType -and $StreamMessages -and $LastStreamType -ne 'ERROR') {
                                & $StreamConverters[$LastStreamType] $($StreamMessages | Out-String)
                                $StreamMessages = @()
                            } 

                            if (!$StreamType -or $StreamType -ne 'ERROR') {
                                $StreamMessages += $Message
                            } else {
                                $StreamErrorMessages += $Message
                            }

                            if ($StreamType) {
                                $LastStreamType = $StreamType
                            }
                        }
                    }
                }
            }
        } finally {
            try {
                if ($StreamMessages) {
                    if ($LastStreamType -eq 'ERROR') {
                        $StreamErrorMessages += $StreamMessages
                    } else {
                        & $StreamConverters[$LastStreamType] $($StreamMessages | Out-String)
                    }
                }
                
                if ($StreamErrorMessages) {
                    if ($Args) {
                        $FirstArg = $Args | Where-Object {$_ -like '-*'} | Select-Object -First 1
                        $FirstArgIndex = $Args.IndexOf($FirstArg)
                        if ($FirstArgIndex -lt 0) {
                            $FirstArgIndex = $Args.Length
                        }
                        $TargetCommand = $Args[0..($FirstArgIndex-1)]
                    } else {
                        $TargetCommand = @()
                    }
                    $Command = "az $($TargetCommand)"
                    $Message = "$Command failed:`n$($StreamErrorMessages -join "`n")"
                    $ErrorRecord = [System.Management.Automation.ErrorRecord]::new([System.Management.Automation.RemoteException]::new($Message), "NativeCommandErrorMessage", [System.Management.Automation.ErrorCategory]::NotSpecified, $Command)
                    Write-Error -ErrorRecord $ErrorRecord -ErrorAction $_ErrorActionPreference
                }
            } finally {
                $DebugPreference = $_DebugPreference
                $VerbosePreference = $_VerbosePreference

                if ($env:GITHUB_ACTIONS) {
                    Write-Host '::endgroup::'
                }
            }
        }
    }

    end {
        if ($IsJson -and $OutputStream) {
            try {
                $OutputStream | ConvertFrom-Json
            } catch {
                $OutputStream | Write-Output
            }
        }
    }
}

function ConvertTo-AzJson {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position=0, ValueFromPipeline)]
        $InputObject,

        [ValidateRange(1, 100)]
        [int] $Depth = 100,

        [switch] $AsArray = $false
    )

    begin {
        $Items = @()
    }

    process {
        $Items += $InputObject
    }

    end {
        ($Items | ConvertTo-Json -AsArray:$AsArray -Compress -Depth $Depth | ConvertTo-Json) -replace '^"|"$'
    }
}

function Out-AzJsonFile {
    [CmdletBinding(SupportsShouldProcess)]
    param
    (
        [Parameter(Mandatory, Position=0, ValueFromPipeline)]
        $InputObject,

        [ValidateNotNullOrEmpty()]
        [string] $Path = $([System.IO.Path]::GetTempFileName()),

        [ValidateRange(1, 100)]
        [int] $Depth = 100,

        [switch] $AsArray = $false
    )

    begin {
        $Items = @()
    }

    process {
        $Items += $InputObject
    }

    end {
        $Items | ConvertTo-Json -AsArray:$AsArray -Depth $Depth | Out-File -FilePath $Path -Encoding utf8
        $Path
    }
}

function Out-AzDeploymentParameters {
    [CmdletBinding(SupportsShouldProcess)]
    param
    (
        [Parameter(Mandatory, Position=0, ValueFromPipeline)]
        $InputObject,

        [ValidateNotNullOrEmpty()]
        [string] $Path = $([System.IO.Path]::GetTempFileName()),

        [ValidateRange(1, 100)]
        [int] $Depth = 100
    )

    begin {
        $Values = @{}
    }

    process {
        $InputObject.GetEnumerator() | ForEach-Object {
            $Values[$_.Key] = @{value=$_.Value}
        }
    }

    end {
        @{
            '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
            contentVersion = '1.0.0.0'
            parameters = $Values
        } | ConvertTo-Json -Depth $Depth | Out-File -FilePath $Path -Encoding utf8
        
        $Path
    }
}

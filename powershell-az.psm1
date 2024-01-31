if (!(Get-Command -Name az -CommandType Application -ErrorAction SilentlyContinue)) {
    throw "AzureCLI is not installed or the az command cannot be found."
}

$AzCommand = (Get-Command -Name az -CommandType Application | Select-Object -First 1).Path

New-Alias -Name az -Value Invoke-AzCommand -Force

function Invoke-Az {
    & $AzCommand $args *>&1
}

function Invoke-AzCommand {
    begin {
        if ($DebugPreference -ne 'SilentlyContinue' -and !($args | Where-Object {$_ -eq '--debug'})) {
            $args += '--debug'
            $args = $args | Where-Object {$_ -ne '--only-show-errors'}
        } 
        
        if ($VerbosePreference -ne 'SilentlyContinue' -and !($args | Where-Object {$_ -eq '--verbose'})) {
            $args += '--verbose'
            $args = $args | Where-Object {$_ -ne '--only-show-errors'}
        }

        $_DebugPreference = $DebugPreference
        $_VerbosePreference = $VerbosePreference

        if ($args | Where-Object {$_ -eq '--debug'}) {
            $DebugPreference = 'Continue'
            $args = $args | Where-Object {$_ -ne '--only-show-errors'}
        }
        
        if ($args | Where-Object {$_ -eq '--verbose'}) {
            $VerbosePreference = 'Continue'
            $args = $args | Where-Object {$_ -ne '--only-show-errors'}
        }

        $IsJson = ($args -notcontains '--output' -and $args -notcontains '-o') -or ($args -join ' ' -match '\b?(-o|--output)\s+jsonc?\b?')
        $IsHelp = $args -contains '-h' -or $args -contains '--help'
        
        if ($env:TF_BUILD -or $env:GITHUB_ACTIONS) {
            Write-Host "$($env:TF_BUILD ? '##[command]' : ($env:GITHUB_ACTIONS ? '::group::' : ''))az $(($args | ForEach-Object {
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
            'WARNING' = { Write-Warning -Message $args[0] }
            'INFO' = { Write-Verbose -Message $args[0] }
            'DEBUG' = { Write-Debug -Message $args[0] }
            'VERBOSE' = { Write-Verbose -Message $args[0] }
        }

        try {
            Invoke-Az @Args | ForEach-Object {
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
                    if ($args) {
                        $FirstArg = $args | Where-Object {$_ -like '-*'} | Select-Object -First 1
                        $FirstArgIndex = $args.IndexOf($FirstArg)
                        if ($FirstArgIndex -lt 0) {
                            $FirstArgIndex = $args.Length
                        }
                        $TargetCommand = $args[0..($FirstArgIndex-1)]
                    } else {
                        $TargetCommand = @()
                    }
                    $Command = "az $($TargetCommand)"
                    $Message = "$Command failed: $($StreamErrorMessages -join "`n")"
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
                $OutputStream | ConvertFrom-Json -AsHashtable
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
        if ($PSNativeCommandArgumentPassing -in ('Legacy', 'Windows', '', $null)) {
            ($Items | ConvertTo-Json -AsArray:$AsArray -Compress -Depth $Depth | ConvertTo-Json) -replace '^"|"$'
        } else {
            ($Items | ConvertTo-Json -AsArray:$AsArray -Compress -Depth $Depth)
        }
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

function Get-AzUniqueString {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position=0, ValueFromPipeline)]
        [string] $InputObject,

        [ValidateRange(1, [byte]::MaxValue)]
        [byte] $Length = 13
    )

    begin {
        $Strings = @()
    }

    process {
        $Strings += $InputObject
    }

    end {
        $Value = $Strings -join '-'

        if ($Value.Length -gt 131072) {
            throw 'Literal limit exceeded maximum length of 131,072 characters.'
        }

        [Azure.BuiltinFunctions]::UniqueString($Value)
    }
}

$BuiltinFunctionsCSharp = @'
using System;
using System.Text;

namespace Azure
{
    public static class BuiltinFunctions
    {
        public static string UniqueString(string text)
        {
            return Base32Encode(MurmurHash64(text));
        }

        private static string Base32Encode(ulong input)
        {
            string text = "abcdefghijklmnopqrstuvwxyz234567";
            StringBuilder stringBuilder = new StringBuilder();
            for (int i = 0; i < 13; i++)
            {
                stringBuilder.Append(text[(int)(input >> 59)]);
                input <<= 5;
            }
            return stringBuilder.ToString();
        }

        private static ulong MurmurHash64(string str, uint seed = 0u)
        {
            return MurmurHash64(Encoding.UTF8.GetBytes(str), seed);
        }

        private static ulong MurmurHash64(byte[] data, uint seed = 0u)
        {
            int length = data.Length;
            uint h1 = seed;
            uint h2 = seed;
            int index;
            for (index = 0; index + 7 < length; index += 8)
            {
                uint k1 = (uint)(data[index] | (data[index + 1] << 8) | (data[index + 2] << 16) | (data[index + 3] << 24));
                uint k3 = (uint)(data[index + 4] | (data[index + 5] << 8) | (data[index + 6] << 16) | (data[index + 7] << 24));
                k1 *= 597399067;
                k1 = k1.RotateLeft32(15);
                k1 *= 2869860233u;
                h1 ^= k1;
                h1 = h1.RotateLeft32(19);
                h1 += h2;
                h1 = h1 * 5 + 1444728091;
                k3 *= 2869860233u;
                k3 = k3.RotateLeft32(17);
                k3 *= 597399067;
                h2 ^= k3;
                h2 = h2.RotateLeft32(13);
                h2 += h1;
                h2 = h2 * 5 + 197830471;
            }
            int tail = length - index;
            if (tail > 0)
            {
                uint k2 = ((tail >= 4) ? ((uint)(data[index] | (data[index + 1] << 8) | (data[index + 2] << 16) | (data[index + 3] << 24))) : (tail switch
                {
                    2 => (uint)(data[index] | (data[index + 1] << 8)), 
                    3 => (uint)(data[index] | (data[index + 1] << 8) | (data[index + 2] << 16)), 
                    _ => data[index], 
                }));
                k2 *= 597399067;
                k2 = k2.RotateLeft32(15);
                k2 *= 2869860233u;
                h1 ^= k2;
                if (tail > 4)
                {
                    uint k4 = (uint)(tail switch
                    {
                        6 => data[index + 4] | (data[index + 5] << 8), 
                        7 => data[index + 4] | (data[index + 5] << 8) | (data[index + 6] << 16), 
                        _ => data[index + 4], 
                    } * -1425107063);
                    k4 = k4.RotateLeft32(17);
                    k4 *= 597399067;
                    h2 ^= k4;
                }
            }
            h1 ^= (uint)length;
            h2 ^= (uint)length;
            h1 += h2;
            h2 += h1;
            h1 ^= h1 >> 16;
            h1 *= 2246822507u;
            h1 ^= h1 >> 13;
            h1 *= 3266489909u;
            h1 ^= h1 >> 16;
            h2 ^= h2 >> 16;
            h2 *= 2246822507u;
            h2 ^= h2 >> 13;
            h2 *= 3266489909u;
            h2 ^= h2 >> 16;
            h1 += h2;
            h2 += h1;
            return ((ulong)h2 << 32) | h1;
        }

        private static uint RotateLeft32(this uint value, int count)
        {
            return (value << count) | (value >> 32 - count);
        }
    }
}
'@

Add-Type -TypeDefinition $BuiltinFunctionsCSharp -Language CSharp
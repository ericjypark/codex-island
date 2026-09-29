param([Parameter(Mandatory=$true)][string]$Snapshot)
$ErrorActionPreference='Stop'
$env:DOTNET_CLI_TELEMETRY_OPTOUT='1'
$root=Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype'
$stamp=Split-Path $Snapshot -Leaf
$profile=Join-Path $root ('mac-history-check\'+$stamp+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
$source=Join-Path $profile 'source'
$input=Join-Path $profile 'input'
New-Item -ItemType Directory -Force (Join-Path $source 'tests\mac-history'),$input|Out-Null
Copy-Item (Join-Path $PSScriptRoot '..\IslandPrototype') $source -Recurse -Force
Copy-Item (Join-Path $PSScriptRoot 'mac-history\*') (Join-Path $source 'tests\mac-history') -Force
foreach($file in @('mac-usage-history.sqlite3','model-prices-payload.json','manifest.json','mac-reference.json')) {
    Copy-Item (Join-Path $Snapshot $file) (Join-Path $input $file)
    if((Get-FileHash (Join-Path $Snapshot $file) -Algorithm SHA256).Hash -ne (Get-FileHash (Join-Path $input $file) -Algorithm SHA256).Hash){throw "Copy verification failed: $file"}
}
$output=Join-Path $Snapshot ('windows-check-'+(Split-Path $profile -Leaf))
New-Item -ItemType Directory -Force $output|Out-Null
@{profile=$profile;input=$input;output=$output}|ConvertTo-Json|Set-Content (Join-Path $Snapshot 'windows-profile.json')
& (Join-Path $root 'dotnet\dotnet.exe') run --project (Join-Path $source 'tests\mac-history\MacHistoryTests.csproj') -c Release -- $input $profile $output
if($LASTEXITCODE -ne 0){throw 'Mac history comparison failed. See windows-history-results.json.'}

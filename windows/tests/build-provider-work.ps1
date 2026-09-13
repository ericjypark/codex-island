$ErrorActionPreference='Stop'
$env:DOTNET_CLI_TELEMETRY_OPTOUT='1'
$root=Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype'
$source=Join-Path $root 'provider-work-source'
New-Item -ItemType Directory -Force $source|Out-Null
Copy-Item (Join-Path $PSScriptRoot '..\IslandPrototype\*') $source -Recurse -Force
& (Join-Path $root 'dotnet\dotnet.exe') build (Join-Path $source 'IslandPrototype.csproj') -c Release --nologo
if($LASTEXITCODE -ne 0){throw 'Provider work build failed.'}

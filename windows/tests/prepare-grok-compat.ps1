$ErrorActionPreference='Stop'
$env:DOTNET_CLI_TELEMETRY_OPTOUT='1'
$root=Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype'
$source=Join-Path $root 'grok-compat-source'
New-Item -ItemType Directory -Force (Join-Path $source 'tests\grok-compat'),(Join-Path $source 'IslandPrototype')|Out-Null
Copy-Item (Join-Path $PSScriptRoot 'grok-compat\*') (Join-Path $source 'tests\grok-compat') -Force
Copy-Item (Join-Path $PSScriptRoot '..\IslandPrototype\GrokCompatibility.cs') (Join-Path $source 'IslandPrototype') -Force
& (Join-Path $root 'dotnet\dotnet.exe') run --project (Join-Path $source 'tests\grok-compat\GrokCompatibilityCheck.csproj') -c Release
if($LASTEXITCODE -ne 0){throw 'Grok compatibility check failed.'}

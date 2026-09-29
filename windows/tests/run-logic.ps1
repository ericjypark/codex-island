$ErrorActionPreference='Stop'
$env:DOTNET_CLI_TELEMETRY_OPTOUT='1'
$root=Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype'
$testRoot=Join-Path $root 'logic-source'
New-Item -ItemType Directory -Force (Join-Path $testRoot 'tests\logic')|Out-Null
Copy-Item (Join-Path $PSScriptRoot '..\IslandPrototype') $testRoot -Recurse -Force
Copy-Item (Join-Path $PSScriptRoot 'logic\*') (Join-Path $testRoot 'tests\logic') -Force
& (Join-Path $root 'dotnet\dotnet.exe') run --project (Join-Path $testRoot 'tests\logic\LogicTests.csproj') -c Release
if($LASTEXITCODE -ne 0){throw 'Logic checks failed.'}

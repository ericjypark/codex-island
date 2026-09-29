param([string]$OutputName='swipe-render-results.json')
$ErrorActionPreference='Stop'
$env:DOTNET_CLI_TELEMETRY_OPTOUT='1'
$root=Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype'
$testRoot=Join-Path $root 'swipe-render-source'
New-Item -ItemType Directory -Force (Join-Path $testRoot 'tests\swipe-render')|Out-Null
Copy-Item (Join-Path $PSScriptRoot '..\IslandPrototype') $testRoot -Recurse -Force
Copy-Item (Join-Path $PSScriptRoot 'swipe-render\*') (Join-Path $testRoot 'tests\swipe-render') -Force
& (Join-Path $root 'dotnet\dotnet.exe') run --project (Join-Path $testRoot 'tests\swipe-render\SwipeRenderTests.csproj') -c Release -- (Join-Path (Join-Path $PSScriptRoot '..\artifacts') $OutputName)
if($LASTEXITCODE -ne 0){throw 'Overview swipe rendering checks failed.'}

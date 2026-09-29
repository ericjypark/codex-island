param([string]$OutputName='counter-render-results.json',[switch]$ProbeCache)
$ErrorActionPreference='Stop'
$env:DOTNET_CLI_TELEMETRY_OPTOUT='1'
$root=Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype'
$testRoot=Join-Path $root 'render-source'
New-Item -ItemType Directory -Force (Join-Path $testRoot 'tests\render')|Out-Null
Copy-Item (Join-Path $PSScriptRoot '..\IslandPrototype') $testRoot -Recurse -Force
Copy-Item (Join-Path $PSScriptRoot 'render\*') (Join-Path $testRoot 'tests\render') -Force
$output=Join-Path (Join-Path $PSScriptRoot '..\artifacts') $OutputName
$testArgs=@($output)
if($ProbeCache){$testArgs+='--probe-cache'}
& (Join-Path $root 'dotnet\dotnet.exe') run --project (Join-Path $testRoot 'tests\render\RenderTests.csproj') -c Release -- @testArgs
if($LASTEXITCODE -ne 0){throw 'Rendering checks failed.'}

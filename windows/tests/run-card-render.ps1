$ErrorActionPreference='Stop'
$env:DOTNET_CLI_TELEMETRY_OPTOUT='1'
$root=Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype'
$testRoot=Join-Path $root 'card-render-source'
New-Item -ItemType Directory -Force (Join-Path $testRoot 'tests\card-render')|Out-Null
Copy-Item (Join-Path $PSScriptRoot '..\IslandPrototype') $testRoot -Recurse -Force
Copy-Item (Join-Path $PSScriptRoot 'card-render\*') (Join-Path $testRoot 'tests\card-render') -Force
$output=Join-Path $PSScriptRoot '..\artifacts\card-after'
& (Join-Path $root 'dotnet\dotnet.exe') run --project (Join-Path $testRoot 'tests\card-render\CardRenderTests.csproj') -c Release -- $output
if($LASTEXITCODE -ne 0){throw 'Card rendering checks failed.'}

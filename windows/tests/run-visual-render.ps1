param([string]$OutputName='visual-after',[switch]$PillOnly)
$ErrorActionPreference='Stop'
$env:DOTNET_CLI_TELEMETRY_OPTOUT='1'
$root=Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype'
$testRoot=Join-Path $root ('visual-source-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force (Join-Path $testRoot 'tests\visual-render')|Out-Null
Copy-Item (Join-Path $PSScriptRoot '..\IslandPrototype') $testRoot -Recurse -Force
Copy-Item (Join-Path $PSScriptRoot 'visual-render\*') (Join-Path $testRoot 'tests\visual-render') -Force
Copy-Item (Join-Path $PSScriptRoot '..\artifacts\mac-reference\fixture.json') (Join-Path $testRoot 'IslandPrototype\Assets\mac-fixture.json') -Force
$output=Join-Path (Join-Path $PSScriptRoot '..\artifacts') $OutputName
$arguments=@($output)
if($PillOnly){$arguments+='--pill-only'}
$version=(Get-Content (Join-Path $PSScriptRoot '..\..\VERSION') -Raw).Trim()
& (Join-Path $root 'dotnet\dotnet.exe') run --project (Join-Path $testRoot 'tests\visual-render\VisualRenderTests.csproj') -c Release -p:Version=$version -- @arguments
if($LASTEXITCODE -ne 0){throw 'Visual rendering failed.'}

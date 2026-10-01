$ErrorActionPreference='Stop'
$root=Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype'
$source=Join-Path $root 'presentation-probe-source'
New-Item -ItemType Directory -Force (Join-Path $source 'tests\presentation-probe'),(Join-Path $source 'IslandPrototype')|Out-Null
Copy-Item (Join-Path $PSScriptRoot 'presentation-probe\*') (Join-Path $source 'tests\presentation-probe') -Force
Copy-Item (Join-Path $PSScriptRoot '..\IslandPrototype\app.manifest') (Join-Path $source 'IslandPrototype') -Force
& (Join-Path $root 'dotnet\dotnet.exe') run --project (Join-Path $source 'tests\presentation-probe\PresentationProbe.csproj') -c Release -- (Join-Path $PSScriptRoot '..\artifacts\responsiveness-confirmed')
if($LASTEXITCODE -ne 0){throw 'Presentation probe failed.'}

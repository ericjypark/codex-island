param([switch]$Software,[switch]$HoldCapture,[string]$MacQuota,[switch]$FooterOnly,[switch]$SettingsOnly)
$ErrorActionPreference='Stop'
$env:DOTNET_CLI_TELEMETRY_OPTOUT='1'
$root=Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype'
$testRoot=Join-Path $root 'live-render-source'
New-Item -ItemType Directory -Force (Join-Path $testRoot 'tests\live-render')|Out-Null
Copy-Item (Join-Path $PSScriptRoot '..\IslandPrototype') $testRoot -Recurse -Force
Copy-Item (Join-Path $PSScriptRoot 'live-render\*') (Join-Path $testRoot 'tests\live-render') -Force
$output=Join-Path $PSScriptRoot '..\artifacts'
$arguments=@($output)
if($Software){$output=Join-Path $output 'live-software-probe';New-Item -ItemType Directory -Force $output|Out-Null;$arguments=@($output,'--software')}
if($HoldCapture){$arguments+='--hold-capture'}
if($MacQuota){$arguments+=@('--mac-quota',$MacQuota)}
if($FooterOnly){$arguments+='--footer-only'}
if($SettingsOnly){$arguments+='--settings-only'}
$version=(Get-Content (Join-Path $PSScriptRoot '..\..\VERSION') -Raw).Trim()
& (Join-Path $root 'dotnet\dotnet.exe') run --project (Join-Path $testRoot 'tests\live-render\LiveRenderTests.csproj') -c Release -p:Version=$version -- @arguments
if($LASTEXITCODE -ne 0){throw 'Live rendering checks failed.'}

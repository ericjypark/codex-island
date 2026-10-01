$ErrorActionPreference='Stop'
$root=Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype'
$assembly=Join-Path $root 'logic-source\tests\logic\bin\Release\net10.0-windows\LogicTests.dll'
$result=& (Join-Path $root 'dotnet\dotnet.exe') $assembly --codex-live
if($LASTEXITCODE -ne 0){throw ('The CLI account read did not succeed: '+($result -join "`n"))}
$result|Set-Content (Join-Path $PSScriptRoot '..\artifacts\codex-account-read.json')
Write-Output $result

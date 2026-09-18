param([Parameter(Mandatory=$true)][string]$Snapshot)
$ErrorActionPreference='Stop'
$env:DOTNET_CLI_TELEMETRY_OPTOUT='1'
$root=Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype'
$profile=Get-Content (Join-Path $Snapshot 'interactive-profile.json') -Raw|ConvertFrom-Json
$verified=Get-Content (Join-Path $Snapshot 'windows-profile.json') -Raw|ConvertFrom-Json
$report=Get-Content (Join-Path $verified.output 'windows-history-results.json') -Raw|ConvertFrom-Json
if($report.failures -ne 0){throw 'The source comparison must pass before updating the preview.'}
$source=Join-Path $profile.profile ('update-source-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory $source|Out-Null
Copy-Item (Join-Path $PSScriptRoot '..\IslandPrototype\*') $source -Recurse -Force
$version=(Get-Content (Join-Path $PSScriptRoot '..\..\VERSION') -Raw).Trim()
$staged=Join-Path $profile.profile 'staged-app'
& (Join-Path $root 'dotnet\dotnet.exe') publish (Join-Path $source 'IslandPrototype.csproj') -c Release -r win-arm64 --self-contained true -p:Version=$version -o $staged --nologo
if($LASTEXITCODE -ne 0){throw 'The update build failed; the running preview is unchanged.'}
$process=Get-Process CodexIslandPrototype|Where-Object {$_.Path -eq $profile.executable}|Select-Object -First 1
if(!$process){throw 'The intended history preview is not running.'}
Add-Type @'
using System;using System.Runtime.InteropServices;
public static class HistoryClose { [DllImport("user32.dll")]public static extern bool PostMessage(IntPtr window,uint message,IntPtr w,IntPtr l); }
'@
$statePath=Join-Path $profile.profile 'state.json'
$state=Get-Content $statePath -Raw|ConvertFrom-Json
[HistoryClose]::PostMessage([IntPtr]$state.window,0x0010,[IntPtr]::Zero,[IntPtr]::Zero)|Out-Null
if(!$process.WaitForExit(5000)){throw 'The preview has not closed; the staged update is preserved.'}
Copy-Item (Join-Path $staged '*') (Split-Path $profile.executable) -Recurse -Force
$started=[DateTimeOffset]::UtcNow
Start-Process -FilePath $profile.executable -ArgumentList @('--live','--data-dir',('"'+$profile.profile+'"'))
$deadline=(Get-Date).AddSeconds(30)
do {
 Start-Sleep -Milliseconds 250
 try{$state=Get-Content $statePath -Raw|ConvertFrom-Json}catch{$state=$null}
}while((!$state -or [DateTimeOffset]$state.updatedAt -le $started) -and (Get-Date) -lt $deadline)
if(!$state -or [DateTimeOffset]$state.updatedAt -le $started){throw 'The updated profile did not report a fresh startup.'}
$profile.build=$state.build;$profile.verifiedOutput=$verified.output
$profile|ConvertTo-Json|Set-Content (Join-Path $Snapshot 'interactive-profile.json')
Write-Output ('Updated the separate Mac history preview: '+$state.build)

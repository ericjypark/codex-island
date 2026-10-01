param([Parameter(Mandatory=$true)][string]$Snapshot)
$ErrorActionPreference='Stop'
$env:DOTNET_CLI_TELEMETRY_OPTOUT='1'
$root=Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype'
$verified=Get-Content (Join-Path $Snapshot 'windows-profile.json') -Raw|ConvertFrom-Json
$report=Get-Content (Join-Path $verified.output 'windows-history-results.json') -Raw|ConvertFrom-Json
if($report.failures -ne 0 -or $report.totalChecks -lt 1770){throw 'The history comparison must pass before opening the preview.'}
$profile=Join-Path $verified.profile 'interactive'
if(Test-Path $profile){throw 'This interactive profile already exists; preserve it and reuse its desktop shortcut.'}
New-Item -ItemType Directory $profile|Out-Null
Copy-Item (Join-Path $verified.profile 'preview-history.sqlite3') (Join-Path $profile 'usage-history.sqlite3')
Copy-Item (Join-Path $verified.profile 'prices.json') (Join-Path $profile 'model-prices.json')
$normalPreferences=Join-Path $root 'preferences.json'
$before=if(Test-Path $normalPreferences){(Get-FileHash $normalPreferences -Algorithm SHA256).Hash}else{$null}
$preferences=[ordered]@{LiveMode=$true;Page=2;LeftProvider='claude';RightProvider='codex';AlwaysShowUsage=$true;SettingsTab='general';HasNavigated=$true;HasCycledCost=$true;HasCycledChart=$true;Language='en';Spacing='reference';RefreshSeconds=300}
$preferences|ConvertTo-Json|Set-Content (Join-Path $profile 'preferences.json')
$source=Join-Path $profile 'source'
New-Item -ItemType Directory $source|Out-Null
Copy-Item (Join-Path $PSScriptRoot '..\IslandPrototype\*') $source -Recurse -Force
$version=(Get-Content (Join-Path $PSScriptRoot '..\..\VERSION') -Raw).Trim()
& (Join-Path $root 'dotnet\dotnet.exe') publish (Join-Path $source 'IslandPrototype.csproj') -c Release -r win-arm64 --self-contained true -p:Version=$version -o (Join-Path $profile 'app') --nologo
if($LASTEXITCODE -ne 0){throw 'The interactive history preview did not build.'}
foreach($process in @(Get-Process CodexIslandPrototype -ErrorAction SilentlyContinue)){
    if($process.Path -ne (Join-Path $root 'app\CodexIslandPrototype.exe')){throw 'A different prototype instance is running; it has been preserved.'}
    Stop-Process -Id $process.Id
}
$executable=Join-Path $profile 'app\CodexIslandPrototype.exe'
$shortcut=(New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'CodexIsland Mac history.lnk'))
$shortcut.TargetPath=$executable
$shortcut.Arguments='--live --data-dir "'+$profile+'"'
$shortcut.WorkingDirectory=Split-Path $executable
$shortcut.Save()
Start-Process -FilePath $executable -ArgumentList @('--live','--data-dir',('"'+$profile+'"'))
$deadline=(Get-Date).AddSeconds(30)
do {Start-Sleep -Milliseconds 250}while(!(Test-Path (Join-Path $profile 'state.json')) -and (Get-Date) -lt $deadline)
if(!(Test-Path (Join-Path $profile 'state.json'))){throw 'The interactive profile did not start.'}
$after=if(Test-Path $normalPreferences){(Get-FileHash $normalPreferences -Algorithm SHA256).Hash}else{$null}
if($before -ne $after){throw 'The normal profile preferences changed unexpectedly.'}
$state=Get-Content (Join-Path $profile 'state.json') -Raw|ConvertFrom-Json
@{profile=$profile;executable=$executable;normalPreferencesUnchanged=$true;build=$state.build;sampleData=$state.sampleData;verifiedOutput=$verified.output}|ConvertTo-Json|Set-Content (Join-Path $Snapshot 'interactive-profile.json')
Write-Output ('Opened the isolated Mac-history preview: '+$profile)

$ErrorActionPreference='Stop'
$root=Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype'
$prefsPath=Join-Path $root 'preferences.json';$statePath=Join-Path $root 'state.json'
$saved=[IO.File]::ReadAllText($prefsPath);$initial=Get-Content $statePath -Raw|ConvertFrom-Json
$executable=Join-Path $root 'app\CodexIslandPrototype.exe'
Add-Type @'
using System;using System.Runtime.InteropServices;
public static class CardCheckHost {
 [DllImport("user32.dll")]public static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
}
'@
function CloseCardCheckApp {
 $running=@(Get-Process CodexIslandPrototype -ErrorAction SilentlyContinue);if(!$running.Count){return}
 $current=Get-Content $statePath -Raw|ConvertFrom-Json
 [CardCheckHost]::PostMessage([IntPtr]$current.window,16,[IntPtr]::Zero,[IntPtr]::Zero)|Out-Null
 foreach($process in $running){if(!$process.WaitForExit(5000)){throw 'The card test could not close the app gracefully.'}}
}
function StartCardCheckApp([string]$mode) {
 $start=New-Object Diagnostics.ProcessStartInfo;$start.FileName=$executable;$start.Arguments=$mode;$start.UseShellExecute=$false
 $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 $process=[Diagnostics.Process]::Start($start);$process.Dispose();Start-Sleep -Milliseconds 1500
}
try {
 CloseCardCheckApp
 $prefs=$saved|ConvertFrom-Json;$prefs.Language='en';$prefs.CardFormat='Feed';$prefs.CardMetric='apiValue'
 $prefs|ConvertTo-Json|Set-Content $prefsPath
 StartCardCheckApp '--demo'
 & (Join-Path $PSScriptRoot 'check-card.ps1')
 if(!$?){throw 'Installed card interaction checks failed.'}
 $current=Get-Content $statePath -Raw|ConvertFrom-Json
 $checks=Get-Content (Join-Path $PSScriptRoot '..\artifacts\card-results.json') -Raw
 $report='{"build":"'+$current.build+'","checks":'+$checks+'}'
 [IO.File]::WriteAllText((Join-Path $PSScriptRoot '..\artifacts\card-installed-results.json'),$report)
}finally {
 CloseCardCheckApp
 [IO.File]::WriteAllText($prefsPath,$saved)
 StartCardCheckApp $(if($initial.sampleData){'--demo'}else{'--live'})
}

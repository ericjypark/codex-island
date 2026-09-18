param([Parameter(Mandatory=$true)][string]$Snapshot,[switch]$Restart)
$ErrorActionPreference='Stop'
$profile=Get-Content (Join-Path $Snapshot 'interactive-profile.json') -Raw|ConvertFrom-Json
$statePath=Join-Path $profile.profile 'state.json'
$cachePath=Join-Path $profile.profile 'quota-history.json'
function State {try{Get-Content $statePath -Raw|ConvertFrom-Json}catch{$null}}
function Cache {try{Get-Content $cachePath -Raw|ConvertFrom-Json}catch{$null}}
function WaitForCache {
 $deadline=(Get-Date).AddSeconds(30)
 do {$cache=Cache;if(!$cache -or !@($cache.Accounts|Where-Object {$_.Provider -eq 'codex'}).Count){Start-Sleep -Milliseconds 250}}while((!$cache -or !@($cache.Accounts|Where-Object {$_.Provider -eq 'codex'}).Count) -and (Get-Date) -lt $deadline)
 if(!$cache -or !@($cache.Accounts|Where-Object {$_.Provider -eq 'codex'}).Count){throw 'The preview did not save Codex quota history.'}
 $cache
}
$process=Get-Process CodexIslandPrototype|Where-Object {$_.Path -eq $profile.executable}|Select-Object -First 1
if(!$process){throw 'The intended history preview is not running.'}
$before=WaitForCache
$beforePoints=@(foreach($account in $before.Accounts){foreach($series in $account.Series){foreach($point in $series.Samples){$account.Provider+'|'+$account.AccountKey+'|'+$series.GroupId+'|'+$series.MetricId+'|'+$point.At+'|'+$point.Used}}})
if(!$beforePoints.Count){throw 'Quota history has no observations to verify.'}
$sawCached=$false
if($Restart){
 Add-Type @'
using System;using System.Runtime.InteropServices;
public static class QuotaClose {[DllImport("user32.dll")]public static extern bool PostMessage(IntPtr window,uint message,IntPtr w,IntPtr l);}
'@
 [QuotaClose]::PostMessage([IntPtr](State).window,0x0010,[IntPtr]::Zero,[IntPtr]::Zero)|Out-Null
 if(!$process.WaitForExit(5000)){throw 'The isolated preview did not close.'}
 $started=[DateTimeOffset]::UtcNow
 Start-Process -FilePath $profile.executable -ArgumentList @('--live','--data-dir',('"'+$profile.profile+'"'))
 $deadline=(Get-Date).AddSeconds(30)
 do {
  Start-Sleep -Milliseconds 30
  $state=State
  if($state -and [DateTimeOffset]$state.updatedAt -gt $started){
   if(@($state.providerStatus|Where-Object {$_.id -eq 'codex' -and $_.status -eq 'Cached'}).Count){$sawCached=$true}
   if(!$state.usageLoading -and @($state.providerStatus|Where-Object {$_.id -eq 'codex' -and $_.status -eq 'Ready'}).Count){break}
  }
 }while((Get-Date) -lt $deadline)
 if(!$state -or [DateTimeOffset]$state.updatedAt -le $started -or $state.usageLoading -or !@($state.providerStatus|Where-Object {$_.id -eq 'codex' -and $_.status -eq 'Ready'}).Count){throw 'The restarted preview did not finish a successful live Codex refresh.'}
}
$after=WaitForCache
$afterPoints=@(foreach($account in $after.Accounts){foreach($series in $account.Series){foreach($point in $series.Samples){$account.Provider+'|'+$account.AccountKey+'|'+$series.GroupId+'|'+$series.MetricId+'|'+$point.At+'|'+$point.Used}}})
$missing=@($beforePoints|Where-Object {$_ -notin $afterPoints})
if($missing.Count){throw 'Previously captured quota observations did not survive restart.'}
$state=State
if($state.sampleData){throw 'The preview restarted in sample mode.'}
$report=[pscustomobject]@{build=$state.build;sampleData=$state.sampleData;restarted=[bool]$Restart;seededStateObserved=$sawCached;priorObservations=$beforePoints.Count;observationsAfter=$afterPoints.Count;priorObservationsPreserved=$true;accounts=@($after.Accounts|ForEach-Object {[pscustomobject]@{provider=$_.Provider;windows=@($_.Windows|ForEach-Object {[pscustomobject]@{label=$_.Label;used=$_.Used;resetAt=$_.ResetAt;spanSeconds=$_.SpanSeconds}});series=@($_.Series|ForEach-Object {[pscustomobject]@{group=$_.GroupId;metric=$_.MetricId;samples=$_.Samples.Count}})}});verifiedAt=[DateTimeOffset]::UtcNow}
$report|ConvertTo-Json -Depth 7|Set-Content (Join-Path $PSScriptRoot '..\artifacts\quota-profile-results.json')
Write-Output ('Verified quota persistence on build '+$state.build+'; '+$beforePoints.Count+' prior observations, '+$afterPoints.Count+' after; cached launch observed: '+$sawCached)

param([Parameter(Mandatory=$true)][string]$Snapshot)
$ErrorActionPreference='Stop'
$profile=Get-Content (Join-Path $Snapshot 'interactive-profile.json') -Raw|ConvertFrom-Json
$statePath=Join-Path $profile.profile 'state.json'
$app=Get-Process CodexIslandPrototype|Where-Object {$_.Path -eq $profile.executable}|Select-Object -First 1
if(!$app){throw 'The intended history preview is not running.'}
Add-Type @'
using System;using System.Text;using System.Collections.Generic;using System.Runtime.InteropServices;
public static class WakeInput {
 private delegate bool EnumProc(IntPtr window,IntPtr parameter);
 [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc callback,IntPtr parameter);
 [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window,out uint process);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] private static extern int GetClassName(IntPtr window,StringBuilder name,int capacity);
 [DllImport("user32.dll")] private static extern IntPtr SendMessageTimeout(IntPtr window,uint message,IntPtr w,IntPtr l,uint flags,uint milliseconds,out IntPtr result);
 public static IntPtr Find(uint process) {
  IntPtr found=IntPtr.Zero;
  EnumWindows((window,_)=>{uint owner;GetWindowThreadProcessId(window,out owner);if(owner==process){var name=new StringBuilder(256);GetClassName(window,name,name.Capacity);if(name.ToString().StartsWith(".NET-BroadcastEventWindow.",StringComparison.Ordinal)){found=window;return false;}}return true;},IntPtr.Zero);
  return found;
 }
 public static void Send(IntPtr window,uint process,int mode) {
  uint owner;GetWindowThreadProcessId(window,out owner);
  if(owner!=process)throw new InvalidOperationException("The preview event window is no longer owned by the target process.");
  IntPtr result;if(SendMessageTimeout(window,0x0218,new IntPtr(mode),IntPtr.Zero,2,2000,out result)==IntPtr.Zero)throw new InvalidOperationException("The preview did not accept the simulated power notification.");
 }
}
'@
function State {try{Get-Content $statePath -Raw|ConvertFrom-Json}catch{$null}}
function Attempts($state){@($state.providerStatus|Sort-Object id|ForEach-Object {$_.id+'|'+$_.attemptedAt}) -join ';'}
function WaitFor([scriptblock]$condition,[string]$failure,[int]$seconds=5){
 $deadline=(Get-Date).AddSeconds($seconds)
 do{$state=State;if($state -and (& $condition $state)){return $state};Start-Sleep -Milliseconds 30}while((Get-Date) -lt $deadline)
 throw $failure
}
$before=WaitFor {param($s) !$s.usageLoading -and !$s.wakeGrace -and @($s.providerStatus|Where-Object {$_.id -eq 'codex' -and $_.status -eq 'Ready'}).Count -gt 0} 'The live preview did not finish connecting.' 30
if($before.sampleData -or !$before.networkEventsRegistered){throw 'Live mode with network event registration is required.'}
if([DateTimeOffset]$before.nextExpectedRefresh -lt [DateTimeOffset]::UtcNow.AddSeconds(75)){throw 'The regular poll is too close to isolate a short-wake check. Run just after it finishes.'}
$eventWindow=[WakeInput]::Find($app.Id)
if($eventWindow -eq [IntPtr]::Zero){throw 'The preview-owned system-event window is unavailable.'}
$checks=[Collections.Generic.List[object]]::new()
function Check([string]$name,[bool]$pass){$checks.Add([pscustomobject]@{check=$name;pass=$pass});if(!$pass){throw $name};Write-Output ('PASS: '+$name)}
$suspendSent=$false
try {
 [WakeInput]::Send($eventWindow,$app.Id,4);$suspendSent=$true
 $sleep=WaitFor {param($s) $s.suspended -and $s.contextSuppressed -and !$s.usageLoading} 'The native suspend event did not reach the preview.'
 Check 'A native suspend notification suppresses the preview and clears request loading' ($sleep.state -eq 'Hidden')
 Start-Sleep -Milliseconds 250
 [WakeInput]::Send($eventWindow,$app.Id,7);$suspendSent=$false
 $wake=WaitFor {param($s) !$s.suspended -and $s.wakeGrace -and $s.automaticRetryAt} 'The native resume event did not arm wake recovery.'
 $grace=[DateTimeOffset]$wake.automaticRetryAt
 Check 'Resume arms the source one-minute grace in the running app' (($grace-[DateTimeOffset]::UtcNow).TotalSeconds -gt 55 -and ($grace-[DateTimeOffset]::UtcNow).TotalSeconds -le 61)
 Check 'A short resume preserves the pending regular poll deadline' ($wake.nextExpectedRefresh -eq $before.nextExpectedRefresh)
 $initialAttempts=Attempts $before
 $changedDuringGrace=$false
 while([DateTimeOffset]::UtcNow -lt $grace){
  $state=State
  if($state -and ((Attempts $state) -ne $initialAttempts -or $state.usageLoading)){$changedDuringGrace=$true}
  Start-Sleep -Milliseconds 100
 }
 $after=WaitFor {param($s) !$s.wakeGrace -and !$s.usageLoading -and !$s.automaticRetryAt} 'The wake retry did not finish its freshness decision.' 5
 Check 'Automatic usage requests stay out of the whole wake grace period' (!$changedDuringGrace)
 Check 'A short sleep does not cause a duplicate live quota request after grace' ((Attempts $after) -eq $initialAttempts)
 Check 'The normal cadence survives the deferred freshness check' ($after.nextExpectedRefresh -eq $before.nextExpectedRefresh)
 Check 'Wake recovery leaves the real account connected' (@($after.providerStatus|Where-Object {$_.id -eq 'codex' -and $_.status -eq 'Ready'}).Count -eq 1)
 [pscustomobject]@{build=$after.build;sampleData=$after.sampleData;networkEventsRegistered=$after.networkEventsRegistered;eventSource='Simulated WM_POWERBROADCAST sent only to the preview-owned system-event window';physicalSuspend=$false;graceSeconds=60;checks=$checks.ToArray();verifiedAt=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $PSScriptRoot '..\artifacts\native-wake-results.json')
}finally{
 if($suspendSent -or (State).suspended){[WakeInput]::Send($eventWindow,$app.Id,7)}
}

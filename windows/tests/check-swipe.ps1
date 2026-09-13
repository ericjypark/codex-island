param([string]$OutputName='swipe-results',[switch]$RequirePass)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;using System.Runtime.InteropServices;
public static class SwipeInput {
 [DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")]public static extern bool PostMessage(IntPtr h,uint message,IntPtr w,IntPtr l);
 [DllImport("user32.dll")]public static extern IntPtr SendMessageTimeout(IntPtr h,uint message,UIntPtr w,IntPtr l,uint flags,uint timeout,out UIntPtr result);
 [DllImport("user32.dll")]public static extern void mouse_event(uint flags,uint x,uint y,uint data,UIntPtr extra);
 [DllImport("user32.dll")]public static extern void keybd_event(byte key,byte scan,uint flags,UIntPtr extra);
 [DllImport("user32.dll")]public static extern int GetSystemMetrics(int n);
 [DllImport("user32.dll")]public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr h);
 public static void Move(int x,int y){mouse_event(0x8001,(uint)(x*65535.0/(GetSystemMetrics(0)-1)),(uint)(y*65535.0/(GetSystemMetrics(1)-1)),0,UIntPtr.Zero);}
 public static double Respond(IntPtr h){UIntPtr r;var watch=System.Diagnostics.Stopwatch.StartNew();var result=SendMessageTimeout(h,0,UIntPtr.Zero,IntPtr.Zero,2,1000,out r);return result==IntPtr.Zero?1000:watch.Elapsed.TotalMilliseconds;}
}
'@
[SwipeInput]::SetThreadDpiAwarenessContext([IntPtr](-4))|Out-Null
$root=Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype'
$statePath=Join-Path $root 'state.json'
$executable=Join-Path $root 'app\CodexIslandPrototype.exe'
$artifacts=Join-Path $PSScriptRoot '..\artifacts'
function WaitUI([int]$ms){$watch=[Diagnostics.Stopwatch]::StartNew();while($watch.ElapsedMilliseconds -lt $ms){[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 5}}
function State {for($i=0;$i -lt 20;$i++){try{return Get-Content $statePath -Raw|ConvertFrom-Json}catch{WaitUI 5}};throw 'No readable application state.'}
function Key([byte]$key){[SwipeInput]::keybd_event($key,0,0,[UIntPtr]::Zero);[SwipeInput]::keybd_event($key,0,2,[UIntPtr]::Zero)}
function Chord([byte]$key){[SwipeInput]::keybd_event(17,0,0,[UIntPtr]::Zero);Key $key;[SwipeInput]::keybd_event(17,0,2,[UIntPtr]::Zero)}
function StartApp([string]$arguments){$info=New-Object Diagnostics.ProcessStartInfo;$info.FileName=$executable;$info.Arguments=$arguments;$info.WorkingDirectory=Split-Path $executable;$info.UseShellExecute=$false;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;return [Diagnostics.Process]::Start($info)}
function CloseApp([Diagnostics.Process]$process,[IntPtr]$window){[SwipeInput]::PostMessage($window,0x10,[IntPtr]::Zero,[IntPtr]::Zero)|Out-Null;for($i=0;$i -lt 100 -and !$process.HasExited;$i++){WaitUI 50};if(!$process.HasExited){throw 'Application did not close gracefully.'}}
$initial=State
$original=Get-Process CodexIslandPrototype|Select-Object -First 1
$originalMode=if($initial.sampleData){'--demo'}else{'--live'}
$restore=$true
$results=[Collections.Generic.List[object]]::new()
$measure=$null
try {
 CloseApp $original ([IntPtr]$initial.window)
 [SwipeInput]::Move(500,900)
 $measure=StartApp (($originalMode+' --trace-frames').Trim());WaitUI 1500
 $state=State;$handle=[IntPtr]$state.window;$cx=[int]($state.screen.Width/2)
 [SwipeInput]::keybd_event(17,0,0,[UIntPtr]::Zero);[SwipeInput]::keybd_event(18,0,0,[UIntPtr]::Zero);Key 73;[SwipeInput]::keybd_event(18,0,2,[UIntPtr]::Zero);[SwipeInput]::keybd_event(17,0,2,[UIntPtr]::Zero)
 WaitUI 700;[SwipeInput]::Move($cx,100);[SwipeInput]::SetForegroundWindow($handle)|Out-Null;WaitUI 200
 if((State).state -ne 'Expanded'){throw 'Could not expand the app for swipe measurements.'}
 function Scenario([string]$name,[uint32]$message,[int]$delta,[int]$packets,[int]$gap,[int]$expected){
  Chord 49;WaitUI 750
  $latencies=[Collections.Generic.List[double]]::new();$clock=[Diagnostics.Stopwatch]::StartNew();$a=(Get-Process -Id $measure.Id).TotalProcessorTime.TotalMilliseconds
  [SwipeInput]::Move($cx,100);[SwipeInput]::SetForegroundWindow($handle)|Out-Null;WaitUI 100
  for($i=0;$i -lt $packets;$i++){
   $flags=if($message -eq 0x20E){0x1000}else{0x0800}
   $data=[BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$delta),0)
   [SwipeInput]::mouse_event($flags,0,0,$data,[UIntPtr]::Zero)
   WaitUI $gap;$latencies.Add([SwipeInput]::Respond($handle))
  }
  WaitUI 650;$observed=(State).page;$b=(Get-Process -Id $measure.Id).TotalProcessorTime.TotalMilliseconds;$elapsed=$clock.Elapsed.TotalMilliseconds;$ordered=@($latencies|Sort-Object)
  $results.Add([pscustomobject]@{scenario=$name;state=(State).state;expectedPage=$expected;observedPage=$observed;pass=$observed -eq $expected;packets=$packets;delta=$delta;gapMs=$gap;elapsedMs=$elapsed;cpuOneCorePercent=($b-$a)/$elapsed*100;responseP95ms=$ordered[[Math]::Min($ordered.Count-1,[int]($ordered.Count*.95))];responseMaxMs=$ordered[-1]})
 }
 Scenario 'one-wheel-notch' 0x20A -120 1 16 1
 Scenario 'one-high-resolution-wheel-burst' 0x20A -15 8 16 1
 Scenario 'one-horizontal-swipe-burst' 0x20E 15 8 16 1
 for($round=0;$round -lt 3;$round++){
  Chord 49;WaitUI 650
  foreach($key in @(50,51,50,49)){Chord ([byte]$key);WaitUI 420}
 }
 Chord ([byte](49+[int]$initial.page));WaitUI 700
 CloseApp $measure $handle;$measure=$null
 $trace=Get-Content (Join-Path $root 'frame-trace.json') -Raw|ConvertFrom-Json
 $trace|ConvertTo-Json -Depth 6|Set-Content (Join-Path $artifacts ($OutputName+'-trace.json'))
 $timings=@()
 foreach($kind in @('island','frame','glow-sweep')){
  $samples=@($trace.samples|Where-Object {$_.Kind -eq $kind}|Sort-Object Milliseconds)
  if($samples.Count){$timings+=[pscustomobject]@{kind=$kind;count=$samples.Count;medianMs=$samples[[int]($samples.Count*.5)].Milliseconds;p95Ms=$samples[[Math]::Min($samples.Count-1,[int]($samples.Count*.95))].Milliseconds;maxMs=$samples[-1].Milliseconds}}
 }
 $result=[pscustomobject]@{build=$trace.build;sampleData=$initial.sampleData;scale=$initial.scale;preferences=$initial.preferences;checks=$results;timings=$timings}
 $result|ConvertTo-Json -Depth 8|Set-Content (Join-Path $artifacts ($OutputName+'.json'))
 $result|ConvertTo-Json -Depth 8
}finally{
 if($measure -and !$measure.HasExited){try{CloseApp $measure ([IntPtr](State).window)}catch{Write-Warning $_}}
 if($restore -and !(Get-Process CodexIslandPrototype -ErrorAction SilentlyContinue)){[SwipeInput]::Move(500,900);$normal=StartApp $originalMode;$normal.Dispose()}
}
if($RequirePass -and @($results|Where-Object {!$_.pass}).Count){throw 'Swipe navigation regression failed.'}

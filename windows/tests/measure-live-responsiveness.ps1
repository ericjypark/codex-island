param([Parameter(Mandatory=$true)][string]$Snapshot,[string]$Name='baseline',[switch]$ReduceMotionProbe,[switch]$PointerOnly,[switch]$RawClicks,[string]$ProbeExecutable)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Windows.Forms,System.Drawing
Add-Type @'
using System;using System.Runtime.InteropServices;using System.Diagnostics;
public static class ResponseInput {
 [DllImport("user32.dll")]public static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
 [DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")]public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr h);
 [DllImport("user32.dll")]public static extern int GetSystemMetrics(int n);
 [DllImport("user32.dll")]public static extern void mouse_event(uint f,uint x,uint y,uint d,UIntPtr e);
 [DllImport("user32.dll")]public static extern void keybd_event(byte k,byte s,uint f,UIntPtr e);
 [DllImport("user32.dll")]public static extern IntPtr SendMessageTimeout(IntPtr h,uint m,UIntPtr w,IntPtr l,uint f,uint timeout,out UIntPtr r);
 public static void Move(int x,int y){mouse_event(0x8001,(uint)(x*65535.0/(GetSystemMetrics(0)-1)),(uint)(y*65535.0/(GetSystemMetrics(1)-1)),0,UIntPtr.Zero);}
 public static double Respond(IntPtr h){UIntPtr r;var s=Stopwatch.StartNew();return SendMessageTimeout(h,0,UIntPtr.Zero,IntPtr.Zero,2,1000,out r)==IntPtr.Zero?1000:s.Elapsed.TotalMilliseconds;}
}
'@
[ResponseInput]::SetThreadDpiAwarenessContext([IntPtr](-4))|Out-Null
$profile=Get-Content (Join-Path $Snapshot 'interactive-profile.json') -Raw|ConvertFrom-Json
$originalExecutable=$profile.executable
$statePath=Join-Path $profile.profile 'state.json'
$prefsPath=Join-Path $profile.profile 'preferences.json'
$savedPrefs=[IO.File]::ReadAllBytes($prefsPath)
$output=Join-Path $PSScriptRoot ('..\artifacts\responsiveness-'+$Name)
New-Item -ItemType Directory -Force $output|Out-Null
function State {for($retry=0;$retry -lt 20;$retry++){try{$value=Get-Content $statePath -Raw|ConvertFrom-Json;if($value.updatedAt){return $value}}catch{};Start-Sleep -Milliseconds 10};throw 'No readable profile state.'}
function Key([byte]$key){[ResponseInput]::keybd_event($key,0,0,[UIntPtr]::Zero);[ResponseInput]::keybd_event($key,0,2,[UIntPtr]::Zero)}
function Chord([byte]$key){[ResponseInput]::keybd_event(17,0,0,[UIntPtr]::Zero);Key $key;[ResponseInput]::keybd_event(17,0,2,[UIntPtr]::Zero)}
function ClosePreview($process){[ResponseInput]::PostMessage([IntPtr](State).window,16,[IntPtr]::Zero,[IntPtr]::Zero)|Out-Null;if(!$process.WaitForExit(5000)){throw 'The intended preview did not close gracefully.'}}
function StartPreview([bool]$trace){
 $started=[DateTimeOffset]::UtcNow;$arguments=@('--live','--data-dir',('"'+$profile.profile+'"'));if($trace){$arguments+='--trace-frames'}
 $p=Start-Process $profile.executable -ArgumentList $arguments -PassThru
 $deadline=(Get-Date).AddSeconds(20)
 do{Start-Sleep -Milliseconds 100;$s=State}while([DateTimeOffset]$s.updatedAt -le $started -and (Get-Date) -lt $deadline)
 if([DateTimeOffset]$s.updatedAt -le $started){throw 'Preview did not start.'};return $p
}
$initial=State
if($initial.sampleData){throw 'This measurement requires the real history preview.'}
$original=Get-Process CodexIslandPrototype|Where-Object {$_.Path -eq $profile.executable}|Select-Object -First 1
if(!$original){throw 'The intended preview is not running.'}
$measure=$null;$results=[Collections.Generic.List[object]]::new()
try {
 ClosePreview $original
 if($ProbeExecutable){$profile.executable=$ProbeExecutable}
 if($ReduceMotionProbe){$probePrefs=[Text.Encoding]::UTF8.GetString($savedPrefs)|ConvertFrom-Json;$probePrefs.ReduceMotion=$true;$probePrefs|ConvertTo-Json -Depth 12|Set-Content $prefsPath}
 [ResponseInput]::Move(500,900)
 $measure=StartPreview $true;Start-Sleep -Milliseconds 2000
 $s=State;$h=[IntPtr]$s.window;$cx=[int]($s.screen.X+$s.screen.Width/2);$scale=$s.scale
 [ResponseInput]::keybd_event(17,0,0,[UIntPtr]::Zero);[ResponseInput]::keybd_event(18,0,0,[UIntPtr]::Zero);Key 73
 [ResponseInput]::keybd_event(18,0,2,[UIntPtr]::Zero);[ResponseInput]::keybd_event(17,0,2,[UIntPtr]::Zero)
 [ResponseInput]::Move($cx,[int](50*$scale));Start-Sleep -Milliseconds 900
 [ResponseInput]::SetForegroundWindow($h)|Out-Null
 if((State).state -ne 'Expanded'){throw 'Preview did not expand.'}
 if($PointerOnly){
  & (Join-Path $PSScriptRoot 'check-live-pointer.ps1') -Snapshot $Snapshot -OutputName $Name -RawClicks:$RawClicks -Executable $profile.executable
  ClosePreview $measure;$measure=$null
  Copy-Item (Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype\frame-trace.json') (Join-Path $output 'trace.json')
  return
 }
 $window=[Windows.Automation.AutomationElement]::FromHandle($h)
 function Elements {$window.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)}
 function RunScenario([string]$scenario,[int]$page,[bool]$hover,[bool]$navigate){
  Chord ([byte](49+$page));Start-Sleep -Milliseconds 900
  $surface=Elements|Where-Object {$_.Current.ClassName -eq 'CodexIsland'}|Select-Object -First 1
  $bounds=$surface.Current.BoundingRectangle
  $points=@(@([int]($bounds.X+30*$scale),[int]($bounds.Bottom-22*$scale)),@([int]($bounds.Right-85*$scale),[int]($bounds.Bottom-22*$scale)),@([int]($bounds.X+400*$scale),[int]($bounds.Y+25*$scale)))
  $latencies=[Collections.Generic.List[double]]::new();$cpu=(Get-Process -Id $measure.Id).TotalProcessorTime.TotalMilliseconds;$watch=[Diagnostics.Stopwatch]::StartNew()
  for($i=0;$i -lt 120;$i++){
   if($navigate -and $i%12 -eq 0){Chord ([byte](49+(($i/12)%3)))}
   elseif($hover){$point=$points[[int]($i/3)%$points.Count];[ResponseInput]::Move($point[0],$point[1])}
   Start-Sleep -Milliseconds 25;$latencies.Add([ResponseInput]::Respond($h))
  }
  $elapsed=$watch.Elapsed.TotalMilliseconds;$end=(Get-Process -Id $measure.Id).TotalProcessorTime.TotalMilliseconds;$ordered=@($latencies|Sort-Object)
  $result=[pscustomobject]@{scenario=$scenario;page=$page;elapsedMs=$elapsed;cpuOneCorePercent=($end-$cpu)/$elapsed*100;responseMedianMs=$ordered[60];responseP95Ms=$ordered[114];responseMaxMs=$ordered[-1]}
  $results.Add($result);$result|ConvertTo-Json -Compress|Write-Output
 }
 RunScenario 'overview-settled' 2 $false $false
 RunScenario 'overview-hover-controls' 2 $true $false
 RunScenario 'usage-hover-controls' 0 $true $false
 RunScenario 'cost-hover-controls' 1 $true $false
 RunScenario 'navigation' 2 $false $true
 ClosePreview $measure;$measure=$null
 $trace=Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype\frame-trace.json'
 Copy-Item $trace (Join-Path $output 'trace.json')
 $data=Get-Content $trace -Raw|ConvertFrom-Json
 $timings=@();foreach($kind in @('island','navigation','frame','glow-sweep')){foreach($page in 0..2){
  $samples=@($data.samples|Where-Object {$_.Kind -eq $kind -and $_.Page -eq $page}|Sort-Object Milliseconds)
  if($samples.Count){$timings+=[pscustomobject]@{kind=$kind;page=$page;count=$samples.Count;medianMs=$samples[[int]($samples.Count*.5)].Milliseconds;p95Ms=$samples[[Math]::Min($samples.Count-1,[int]($samples.Count*.95))].Milliseconds;maxMs=$samples[-1].Milliseconds}}
 }}
 @{build=$data.build;scale=$s.scale;screen=$s.screen;preferences=$s.preferences;reduceMotionProbe=[bool]$ReduceMotionProbe;scenarios=$results;timings=$timings;scope='WPF callback and UI-thread measurements; not physical presentation latency'}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $output 'results.json')
 $timings|ConvertTo-Json
}finally{
 if($measure -and !$measure.HasExited){ClosePreview $measure}
 $profile.executable=$originalExecutable
 [IO.File]::WriteAllBytes($prefsPath,$savedPrefs)
 if(!(Get-Process CodexIslandPrototype -ErrorAction SilentlyContinue|Where-Object {$_.Path -eq $profile.executable})){
  [ResponseInput]::Move(500,900);$restored=StartPreview $false;$restored.Dispose()
 }
}

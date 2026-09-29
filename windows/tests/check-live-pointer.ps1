param([Parameter(Mandatory=$true)][string]$Snapshot,[string]$OutputName='pointer-results',[switch]$RawClicks,[string]$Executable)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Drawing
Add-Type @'
using System;using System.Runtime.InteropServices;using System.Diagnostics;using System.Threading;
public static class LivePointer {
 public static System.Collections.Generic.List<long> Started=new System.Collections.Generic.List<long>(),Visible=new System.Collections.Generic.List<long>();
 [DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")]public static extern int GetSystemMetrics(int n);
 public static bool SetCursorPos(int x,int y){mouse_event(0x8001,(uint)(x*65535.0/(GetSystemMetrics(0)-1)),(uint)(y*65535.0/(GetSystemMetrics(1)-1)),0,UIntPtr.Zero);return true;}
 [DllImport("user32.dll")]public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr h);
 [DllImport("user32.dll")]public static extern void mouse_event(uint f,uint x,uint y,uint d,UIntPtr e);
 [DllImport("user32.dll")]public static extern void keybd_event(byte k,byte s,uint f,UIntPtr e);
 [DllImport("user32.dll")]static extern IntPtr GetDC(IntPtr h);
 [DllImport("user32.dll")]static extern int ReleaseDC(IntPtr h,IntPtr dc);
 [DllImport("gdi32.dll")]static extern uint GetPixel(IntPtr dc,int x,int y);
 public static double ClickUntilBright(int x,int y){
  IntPtr dc=GetDC(IntPtr.Zero);try{uint before=GetPixel(dc,x,y)&255;if(before>130)throw new Exception("The destination page dot was already selected.");
   var watch=Stopwatch.StartNew();Started.Add(Stopwatch.GetTimestamp());mouse_event(2,0,0,0,UIntPtr.Zero);mouse_event(4,0,0,0,UIntPtr.Zero);
   while(watch.ElapsedMilliseconds<1000){if((GetPixel(dc,x,y)&255)>150){Visible.Add(Stopwatch.GetTimestamp());return watch.Elapsed.TotalMilliseconds;}Thread.Sleep(1);}Visible.Add(Stopwatch.GetTimestamp());return 1000;
  }finally{ReleaseDC(IntPtr.Zero,dc);}
 }
}
'@
[LivePointer]::SetThreadDpiAwarenessContext([IntPtr](-4))|Out-Null
$profile=Get-Content (Join-Path $Snapshot 'interactive-profile.json') -Raw|ConvertFrom-Json
$statePath=Join-Path $profile.profile 'state.json'
function State {for($retry=0;$retry -lt 20;$retry++){try{$value=Get-Content $statePath -Raw|ConvertFrom-Json;if($value.updatedAt){return $value}}catch{};Start-Sleep -Milliseconds 10};throw 'No readable profile state.'}
function Key([byte]$key){[LivePointer]::keybd_event($key,0,0,[UIntPtr]::Zero);[LivePointer]::keybd_event($key,0,2,[UIntPtr]::Zero)}
function Chord([byte]$key){[LivePointer]::keybd_event(17,0,0,[UIntPtr]::Zero);Key $key;[LivePointer]::keybd_event(17,0,2,[UIntPtr]::Zero)}
$initial=State
$expectedExecutable=if($Executable){$Executable}else{$profile.executable}
if($initial.sampleData -or !(Get-Process CodexIslandPrototype|Where-Object {$_.Path -eq $expectedExecutable})){throw 'The intended live preview is unavailable.'}
$scale=$initial.scale;$cx=[int]($initial.screen.X+$initial.screen.Width/2)
[LivePointer]::SetCursorPos($cx,[int](50*$scale))|Out-Null
if($initial.state -ne 'Expanded'){
 [LivePointer]::keybd_event(17,0,0,[UIntPtr]::Zero);[LivePointer]::keybd_event(18,0,0,[UIntPtr]::Zero);Key 73
 [LivePointer]::keybd_event(18,0,2,[UIntPtr]::Zero);[LivePointer]::keybd_event(17,0,2,[UIntPtr]::Zero)
}
Start-Sleep -Milliseconds 800
[LivePointer]::SetForegroundWindow([IntPtr](State).window)|Out-Null
$window=if(!$RawClicks){[Windows.Automation.AutomationElement]::FromHandle([IntPtr](State).window)}else{$null}
function Elements {$window.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)}
function Surface {Elements|Where-Object {$_.Current.ClassName -eq 'CodexIsland'}|Select-Object -First 1}
$output=Join-Path $PSScriptRoot '..\artifacts\responsiveness-confirmed';New-Item -ItemType Directory -Force $output|Out-Null
function Capture([string]$name){$bounds=(Surface).Current.BoundingRectangle;$bitmap=New-Object Drawing.Bitmap ([int]$bounds.Width),([int]$bounds.Height+60);$graphics=[Drawing.Graphics]::FromImage($bitmap);try{$graphics.CopyFromScreen([int]$bounds.X,[int]$bounds.Y,0,0,$bitmap.Size);$bitmap.Save((Join-Path $output ($name+'.png')))}finally{$graphics.Dispose();$bitmap.Dispose()}}
try{
 if(!$RawClicks){
 Chord 51;Start-Sleep -Milliseconds 800
 if(!(Surface).Current.Name.Contains('14,061,868,359 tokens')){throw 'The imported history total changed.'}
 $page=Elements|Where-Object {$_.Current.AutomationId -eq 'island-Overview (Ctrl+3)'}|Select-Object -First 1
 $page.SetFocus();Start-Sleep -Milliseconds 150
 if(!$page.Current.HasKeyboardFocus){throw 'Keyboard focus did not reach the page control.'}
 Capture 'keyboard-focus'
 [LivePointer]::SetCursorPos($cx+100,[int](50*$scale))|Out-Null;Start-Sleep -Milliseconds 200
 Capture 'pointer-normal'
 $page=Elements|Where-Object {$_.Current.AutomationId -eq 'island-Overview (Ctrl+3)'}|Select-Object -First 1
 if([Windows.Automation.AutomationElement]::FocusedElement.Current.AutomationId -ne 'Surface'){throw 'Pointer input did not return focus to the panel.'}
 $usage=Elements|Where-Object {$_.Current.AutomationId -eq 'island-Usage (Ctrl+1)'}|Select-Object -First 1
 $usage.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke();Start-Sleep -Milliseconds 900
 }else{Chord 49;Start-Sleep -Milliseconds 900}
 if((State).page -ne 0){throw 'The click measurement did not start on Usage.'}
 $bounds=if(!$RawClicks){(Surface).Current.BoundingRectangle}else{[pscustomobject]@{X=$cx-400*$scale;Y=$initial.screen.Y}}
 $latencies=[Collections.Generic.List[double]]::new()
 for($i=0;$i -lt 12;$i++){
  $destination=1-$i%2;$x=[int]($bounds.X+(390+10*$destination)*$scale);$y=[int]($bounds.Y+204.5*$scale)
  [LivePointer]::SetCursorPos($x,$y)|Out-Null;Start-Sleep -Milliseconds 100
  $latencies.Add([LivePointer]::ClickUntilBright($x,$y));Start-Sleep -Milliseconds 600
  if((State).page -ne $destination){if(!$RawClicks){Capture 'click-failure'};throw ('A native page click was lost: expected '+$destination+', observed '+(State).page+', at '+$x+','+$y+', pixel response '+$latencies[-1])}
 }
 $ordered=@($latencies|Sort-Object)
 if($RawClicks){
  $bitmap=New-Object Drawing.Bitmap ([int](800*$scale)),([int]((State).panelHeight*$scale+60));$graphics=[Drawing.Graphics]::FromImage($bitmap)
  try{$graphics.CopyFromScreen([int]$bounds.X,[int]$bounds.Y,0,0,$bitmap.Size);$bitmap.Save((Join-Path $output ($OutputName+'.png')))}finally{$graphics.Dispose();$bitmap.Dispose()}
 }
 @{build=(State).build;scale=$scale;reduceMotion=(State).reducedMotion;uiaInspection=!$RawClicks;yearTokens=14061868359;focusChecked=!$RawClicks;nativePageClicks=$latencies;startedTicks=[LivePointer]::Started;visibleTicks=[LivePointer]::Visible;tickFrequency=[Diagnostics.Stopwatch]::Frequency;medianMs=$ordered[6];p95Ms=$ordered[11];maxMs=$ordered[-1];scope='Injected native click to selected-dot pixels in the Windows guest desktop; excludes host display and physical input latency'}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $output ($OutputName+'.json'))
 Write-Output ('Verified pointer focus and 12 visible page clicks: median '+$ordered[6]+' ms, maximum '+$ordered[-1]+' ms.')
}finally{
 Chord ([byte](49+$initial.page));Start-Sleep -Milliseconds 800
 [LivePointer]::SetCursorPos($cx+100,[int](50*$scale))|Out-Null
}

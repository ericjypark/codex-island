$ErrorActionPreference = 'Stop'
$artifacts = Join-Path $PSScriptRoot '..\artifacts'
New-Item -ItemType Directory -Force $artifacts | Out-Null
$appRoot=Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype'
$executable=Join-Path $appRoot 'app\CodexIslandPrototype.exe'
Get-Process CodexIslandPrototype -ErrorAction SilentlyContinue|Stop-Process
Start-Sleep -Milliseconds 400
Start-Process $executable -ArgumentList '--trace-frames'
Start-Sleep -Milliseconds 2000
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class CheckInput {
 [DllImport("user32.dll")] public static extern int GetSystemMetrics(int metric);
 public static void Move(int x,int y) {
  mouse_event(0x8001,(uint)(x*65535.0/(GetSystemMetrics(0)-1)),(uint)(y*65535.0/(GetSystemMetrics(1)-1)),0,UIntPtr.Zero);
 }
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h,uint msg,IntPtr w,IntPtr l);
 [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr h);
 [DllImport("user32.dll")] public static extern void mouse_event(uint flags,uint x,uint y,uint data,UIntPtr extra);
 [DllImport("user32.dll")] public static extern void keybd_event(byte key,byte scan,uint flags,UIntPtr extra);
}
'@
[CheckInput]::SetThreadDpiAwarenessContext([IntPtr](-4)) | Out-Null
$statePath = "$env:LOCALAPPDATA\CodexIslandPrototype\state.json"
$results = [System.Collections.Generic.List[object]]::new()
function Wait-UI([int]$ms) {
 $watch = [Diagnostics.Stopwatch]::StartNew()
 while ($watch.ElapsedMilliseconds -lt $ms) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 10 }
}
function State { return (Get-Content $statePath -Raw | ConvertFrom-Json).state }
function Check([string]$name,[bool]$pass) {
 $results.Add([pscustomobject]@{check=$name;pass=$pass;state=(State)})
}
function Click {
 [CheckInput]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
 [CheckInput]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
 Wait-UI 120
}
function Capture([string]$name) {
 $bmp = New-Object Drawing.Bitmap 1800,760
 $gfx = [Drawing.Graphics]::FromImage($bmp)
 $gfx.CopyFromScreen($cx-900,0,0,0,$bmp.Size)
 $bmp.Save((Join-Path $artifacts "$name.png"),[Drawing.Imaging.ImageFormat]::Png)
 $gfx.Dispose(); $bmp.Dispose()
}
$initial = Get-Content $statePath -Raw | ConvertFrom-Json
if ($initial.scale -ne 2) { throw 'These capture coordinates require 200 percent display scaling.' }
$cx = [int]($initial.screen.Width/2)

function Key([byte]$key) {
 [CheckInput]::keybd_event($key,0,0,[UIntPtr]::Zero)
 [CheckInput]::keybd_event($key,0,2,[UIntPtr]::Zero)
}
function Chord([byte]$key) {
 [CheckInput]::keybd_event(17,0,0,[UIntPtr]::Zero)
 Key $key
 [CheckInput]::keybd_event(17,0,2,[UIntPtr]::Zero)
 Wait-UI 900
}
function PanelCapture([string]$name,[int]$height) {
 $bmp=New-Object Drawing.Bitmap 1600,$height
 $gfx=[Drawing.Graphics]::FromImage($bmp)
 $gfx.CopyFromScreen($cx-800,0,0,0,$bmp.Size)
 $bmp.Save((Join-Path $artifacts "$name.png"),[Drawing.Imaging.ImageFormat]::Png)
 $gfx.Dispose();$bmp.Dispose()
}
Key 27
[CheckInput]::Move($cx,800);Wait-UI 500
[CheckInput]::Move($cx,1);Wait-UI 900
if((State) -eq 'Peek'){Click;Wait-UI 1000}
if((State) -ne 'Expanded'){
 [CheckInput]::keybd_event(17,0,0,[UIntPtr]::Zero);[CheckInput]::keybd_event(18,0,0,[UIntPtr]::Zero);Key 73;[CheckInput]::keybd_event(18,0,2,[UIntPtr]::Zero);[CheckInput]::keybd_event(17,0,2,[UIntPtr]::Zero);Wait-UI 1000
}
[CheckInput]::SetForegroundWindow([IntPtr]$initial.window)|Out-Null
Wait-UI 250
if((State) -ne 'Expanded'){throw 'The motion capture did not expand the island.'}
foreach($page in 0..2){Chord ([byte](49+$page));Wait-UI 4000}
[CheckInput]::PostMessage([IntPtr]$initial.window,0x10,[IntPtr]::Zero,[IntPtr]::Zero)|Out-Null
Wait-UI 1200
$trace=Join-Path $appRoot 'frame-trace.json'
if(!(Test-Path $trace)){throw 'The frame trace was not written.'}
Copy-Item $trace (Join-Path $artifacts 'render-cost-trace.json')
$data=Get-Content $trace -Raw|ConvertFrom-Json
foreach($page in 0..2){
 $samples=@($data.samples|Where-Object {$_.Kind -eq 'island' -and $_.Page -eq $page -and $_.Progress -eq 1}|Sort-Object Milliseconds)
 if($samples.Count -gt 0){[pscustomobject]@{page=$page;settledDraws=$samples.Count;median=$samples[[int]($samples.Count*.5)].Milliseconds;p95=$samples[[Math]::Min($samples.Count-1,[int]($samples.Count*.95))].Milliseconds;max=$samples[-1].Milliseconds;build=$data.build}|ConvertTo-Json}
}
$samples=@($data.samples|Where-Object {$_.Kind -eq 'glow-sweep'}|Sort-Object Milliseconds)
[pscustomobject]@{glowDraws=$samples.Count;median=$samples[[int]($samples.Count*.5)].Milliseconds;p95=$samples[[int]($samples.Count*.95)].Milliseconds;max=$samples[-1].Milliseconds}|ConvertTo-Json
Start-Process $executable

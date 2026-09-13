$ErrorActionPreference = 'Stop'
$artifacts = Join-Path $PSScriptRoot '..\artifacts'
New-Item -ItemType Directory -Force $artifacts | Out-Null
if (!(Get-Process CodexIslandPrototype -ErrorAction SilentlyContinue)) { throw 'The prototype must be running before input verification.' }
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
[CheckInput]::Move($cx,800)
Wait-UI 450
[CheckInput]::Move($cx,1)
Wait-UI 700
if((State) -eq 'Peek'){Click;Wait-UI 850}
if((State) -ne 'Expanded'){
 [CheckInput]::keybd_event(17,0,0,[UIntPtr]::Zero);[CheckInput]::keybd_event(18,0,0,[UIntPtr]::Zero);Key 73;[CheckInput]::keybd_event(18,0,2,[UIntPtr]::Zero);[CheckInput]::keybd_event(17,0,2,[UIntPtr]::Zero);Wait-UI 900
}
[CheckInput]::SetForegroundWindow([IntPtr]$initial.window)|Out-Null
Wait-UI 250
if((State) -ne 'Expanded'){throw 'The capture could not expand the island.'}
Chord 49
PanelCapture 'win-usage-spark' 452
[CheckInput]::Move(($cx-650),408)
Click
Wait-UI 250
PanelCapture 'win-usage-ring' 452
foreach($style in @('bar','stepped','numeric','spark')) { Click; Wait-UI 300; PanelCapture "win-usage-$style" 452 }
Check 'Style control cycles through all five charts' ((Get-Content $statePath -Raw | ConvertFrom-Json).chartStyle -eq 4)
Chord 50
Check 'Cost page keyboard navigation' ((Get-Content $statePath -Raw | ConvertFrom-Json).page -eq 1)
PanelCapture 'win-cost-dollar' 452
foreach($style in @('multi','tokens','spark')) { Click; Wait-UI 900; PanelCapture "win-cost-$style" 452 }
Click
Wait-UI 300
Chord 51
Check 'Overview page keyboard navigation' ((Get-Content $statePath -Raw | ConvertFrom-Json).page -eq 2)
PanelCapture 'win-overview' 554
$fixture=Get-Content (Join-Path $PSScriptRoot '..\IslandPrototype\Assets\mac-fixture.json') -Raw|ConvertFrom-Json
$selected=([DateTimeOffset]::Parse($fixture.date)).LocalDateTime.Date
$first=Get-Date -Year $selected.Year -Month 1 -Day 1 -Hour 0 -Minute 0 -Second 0
$start=$first.Date.AddDays(-[int]$first.DayOfWeek)
$offset=($selected-$start).Days
[CheckInput]::Move([int]($cx-800+2*(16+[Math]::Floor($offset/7)*13.95+5.8)),[int](2*(38+81+($offset%7)*13.95+5.8)))
Click
Wait-UI 800
Check 'Selecting a date expands detail' ((Get-Content $statePath -Raw | ConvertFrom-Json).panelHeight -eq 335)
PanelCapture 'win-overview-detail' 670
Click
Wait-UI 800
Check 'Selecting date again closes detail' ((Get-Content $statePath -Raw | ConvertFrom-Json).panelHeight -eq 277)
$results | ConvertTo-Json | Set-Content (Join-Path $artifacts 'parity-interaction-results.json')
$results | ConvertTo-Json
Chord 49

if($results.Where({!$_.pass}).Count -gt 0){throw 'Panel parity interactions failed.'}

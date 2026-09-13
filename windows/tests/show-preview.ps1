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
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string cls,string title);
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
 Wait-UI 600
}
function PanelCapture([string]$name,[int]$height) {
 $bmp=New-Object Drawing.Bitmap 1600,$height
 $gfx=[Drawing.Graphics]::FromImage($bmp)
 $gfx.CopyFromScreen($cx-800,0,0,0,$bmp.Size)
 $bmp.Save((Join-Path $artifacts "$name.png"),[Drawing.Imaging.ImageFormat]::Png)
 $gfx.Dispose();$bmp.Dispose()
}


$preview = Get-Process CodexIslandPrototype
if ($preview.MainWindowTitle -eq 'CodexIsland Settings') { $preview.CloseMainWindow() | Out-Null; Wait-UI 500 }
if ((State) -eq 'Hidden') {
 [CheckInput]::keybd_event(17,0,0,[UIntPtr]::Zero)
 [CheckInput]::keybd_event(18,0,0,[UIntPtr]::Zero)
 Key 73
 [CheckInput]::keybd_event(18,0,2,[UIntPtr]::Zero)
 [CheckInput]::keybd_event(17,0,2,[UIntPtr]::Zero)
 Wait-UI 800
}
[CheckInput]::SetForegroundWindow([IntPtr]$initial.window) | Out-Null
Chord 49
Write-Output ('Preview left on Usage: ' + (State))

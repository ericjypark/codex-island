param([string]$Snapshot,[string]$OutputName='interaction')
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
 [StructLayout(LayoutKind.Sequential)] public struct Point { public int X,Y; }
 [DllImport("user32.dll")] public static extern bool GetCursorPos(out Point point);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")] public static extern int GetSystemMetrics(int metric);
 public static void Move(int x,int y) {
  SetCursorPos(x,y);
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
$checkedProcess=Get-Process CodexIslandPrototype|Select-Object -First 1
if($Snapshot){
 $profile=Get-Content (Join-Path $Snapshot 'interactive-profile.json') -Raw|ConvertFrom-Json
 $statePath=Join-Path $profile.profile 'state.json'
 $checkedProcess=Get-Process CodexIslandPrototype|Where-Object {$_.Path -eq $profile.executable}|Select-Object -First 1
 if(!$checkedProcess){throw 'The specified history preview is not running.'}
}
$results = [System.Collections.Generic.List[object]]::new()
function Wait-UI([int]$ms) {
 $watch = [Diagnostics.Stopwatch]::StartNew()
 while ($watch.ElapsedMilliseconds -lt $ms) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 10 }
}
function State { return (Get-Content $statePath -Raw | ConvertFrom-Json).state }
function Check([string]$name,[bool]$pass) {
 $pointer=New-Object CheckInput+Point
 [CheckInput]::GetCursorPos([ref]$pointer)|Out-Null
 $results.Add([pscustomobject]@{check=$name;pass=$pass;state=(State);pointer=$pointer;build=$initial.build;alwaysShowUsage=$initial.preferences.AlwaysShowUsage})
}
function Click {
 [CheckInput]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
 [CheckInput]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
 Wait-UI 120
}
function MoveIntoPill {
 $pillY=if($null -ne $initial.panelTop){($initial.panelTop+26)*$initial.scale}else{19*$initial.scale}
 [CheckInput]::Move($cx,[int]$pillY)|Out-Null
 Wait-UI 80
}
function Capture([string]$name) {
 $bmp = New-Object Drawing.Bitmap 1800,760
 $gfx = [Drawing.Graphics]::FromImage($bmp)
 $gfx.CopyFromScreen($cx-900,0,0,0,$bmp.Size)
 $captureName=if($OutputName -eq 'interaction'){$name}else{"$OutputName-$name"}
 $bmp.Save((Join-Path $artifacts "$captureName.png"),[Drawing.Imaging.ImageFormat]::Png)
 $gfx.Dispose(); $bmp.Dispose()
}
$initial = Get-Content $statePath -Raw | ConvertFrom-Json
$restState=if($initial.preferences.AlwaysShowUsage){'Peek'}else{'Hidden'}
if ($initial.scale -ne 2) { throw 'These capture coordinates require 200 percent display scaling.' }
$cx = [int]($initial.screen.Width/2)
$form = New-Object Windows.Forms.Form
$form.Text = 'CodexIsland interaction check'
$form.StartPosition = 'Manual'
$form.Location = New-Object Drawing.Point ($cx-800),110
$form.Size = New-Object Drawing.Size 1700,760
$input = New-Object Windows.Forms.TextBox
$input.Multiline = $true
$input.Dock = 'Fill'
$input.Font = New-Object Drawing.Font 'Segoe UI',18
$input.Text = 'Temporary focus and click-through check. This window closes automatically.'
$form.Controls.Add($input)
try {
 $form.Show(); $form.Activate(); $input.Focus() | Out-Null
 [CheckInput]::Move($cx,800) | Out-Null
 Click
 Wait-UI 700
 Check 'Initially follows the configured rest visibility' ((State) -eq $restState)
 $focusBefore = [CheckInput]::GetForegroundWindow()
 [CheckInput]::Move($cx,1) | Out-Null
 Wait-UI 60
 [CheckInput]::Move($cx,800) | Out-Null
 Wait-UI 350
 Check 'Quick edge pass preserves the configured rest state' ((State) -eq $restState)
 [CheckInput]::Move($cx,1) | Out-Null
 Wait-UI 650
 Check 'Dwell reveals peek' ((State) -eq 'Peek')
 Check 'Hover preserves foreground' ([CheckInput]::GetForegroundWindow() -eq $focusBefore)
 Capture 'peek'
 MoveIntoPill
 Click
 Wait-UI 500
 Check 'Stationary cursor click expands' ((State) -eq 'Expanded')
 Capture 'expanded'
 [CheckInput]::keybd_event(27,0,0,[UIntPtr]::Zero)
 [CheckInput]::keybd_event(27,0,2,[UIntPtr]::Zero)
 Wait-UI 450
 Check 'Escape returns to the configured rest state' ((State) -eq $restState)
 Check 'Escape restores previous focus' ([CheckInput]::GetForegroundWindow() -eq $focusBefore)
 Wait-UI 400
 Check 'Dismissal stays at rest under stationary cursor' ((State) -eq $restState)
 [CheckInput]::Move($cx,800) | Out-Null
 Wait-UI 80
 [CheckInput]::Move($cx,1) | Out-Null
 Wait-UI 600
 [CheckInput]::Move($cx,60) | Out-Null
 Wait-UI 600
 Check 'Moving into peek keeps it open' ((State) -eq 'Peek')
 [CheckInput]::Move($cx,800) | Out-Null
 Wait-UI 170
 Check 'Exit grace keeps peek briefly' ((State) -eq 'Peek')
 Wait-UI 400
 Check 'Leaving returns to the configured rest state' ((State) -eq $restState)
 [CheckInput]::Move($cx,1) | Out-Null
 Wait-UI 650
 Check 'Re-entering immediately after timed dismissal reveals peek' ((State) -eq 'Peek')
 MoveIntoPill
 Click
 Wait-UI 450
 Check 'Re-entered peek expands before outside-click verification' ((State) -eq 'Expanded')
 [CheckInput]::Move($cx+850,220) | Out-Null
 Wait-UI 100
 Click
 Wait-UI 450
 Check 'Outside click dismisses expanded panel' ((State) -eq $restState)
 Check 'Click passes through empty overlay area' ([CheckInput]::GetForegroundWindow() -eq $form.Handle)
 $before = (Get-Process -Id $checkedProcess.Id).TotalProcessorTime.TotalMilliseconds
 Wait-UI 5000
 $after = (Get-Process -Id $checkedProcess.Id).TotalProcessorTime.TotalMilliseconds
 $results.Add([pscustomobject]@{check="$restState rest CPU over 5 seconds";cpuMilliseconds=($after-$before);oneCorePercent=([math]::Round(($after-$before)/50,3));build=$initial.build})
 $results | ConvertTo-Json | Set-Content (Join-Path $artifacts "$OutputName-results.json")
 $results | ConvertTo-Json
} finally {
 $form.Close(); $form.Dispose()
 [CheckInput]::Move($cx,800) | Out-Null
}
if($results.Where({$_.PSObject.Properties.Name -contains 'pass' -and !$_.pass}).Count -gt 0){throw 'Island interaction checks failed.'}

$ErrorActionPreference = 'Stop'
$artifacts = Join-Path $PSScriptRoot '..\artifacts'
New-Item -ItemType Directory -Force $artifacts | Out-Null
if (!(Get-Process CodexIslandPrototype -ErrorAction SilentlyContinue)) { throw 'The prototype must be running before input verification.' }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
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

function AppWindow([string]$title) {
 $pidApp=(Get-Process CodexIslandPrototype|Select-Object -First 1).Id
 $condition=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ProcessIdProperty),$pidApp
 return ([Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,$condition)|Where-Object {$_.Current.Name -eq $title}|Select-Object -First 1)
}
function IslandControl([string]$name) {
 $window=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$initial.window)
 $condition=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::NameProperty),$name
 return $window.FindFirst([Windows.Automation.TreeScope]::Descendants,$condition)
}
function Expand {
 [CheckInput]::Move($cx,800);Wait-UI 500
 [CheckInput]::Move($cx,1);Wait-UI 700
 if((State) -eq 'Peek'){Click;Wait-UI 1000}
 [CheckInput]::SetForegroundWindow([IntPtr]$initial.window)|Out-Null
 Wait-UI 250
}
Expand
Chord 49
$window=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$initial.window)
$all=$window.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)
$usage=$all|Where-Object {$_.Current.Name.StartsWith('CodexIsland Usage.')}|Select-Object -First 1
Check 'Usage values are exposed to accessibility' ($null -ne $usage -and $usage.Current.Name.Contains('Codex:') -and $usage.Current.Name.Contains('Antigravity:'))
$cost=IslandControl 'Cost (Ctrl+2)'
Check 'Page control has an accessible invocation' ($null -ne $cost)
$cost.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke();Wait-UI 1000
Check 'Accessibility invocation changes page' ((Get-Content $statePath -Raw|ConvertFrom-Json).page -eq 1)
$overview=IslandControl 'Overview (Ctrl+3)'
$overview.SetFocus();Key 13;Wait-UI 1000
Check 'Keyboard activation of focused page changes page' ((Get-Content $statePath -Raw|ConvertFrom-Json).page -eq 2)
$window=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$initial.window)
$all=$window.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)
$overviewValues=$all|Where-Object {$_.Current.Name.StartsWith('CodexIsland Overview.')}|Select-Object -First 1
Check 'Overview exposes token totals and provenance' ($null -ne $overviewValues -and $overviewValues.Current.Name.Contains('tokens.') -and $overviewValues.Current.Name.Contains('Demo data.'))
(IslandControl 'Settings').GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke();Wait-UI 1000
$settings=AppWindow 'CodexIsland Settings'
Check 'Accessible Settings action opens window and hides island' ($null -ne $settings -and (State) -eq 'Hidden')
if($settings){$settings.GetCurrentPattern([Windows.Automation.WindowPattern]::Pattern).Close();Wait-UI 450}
Expand
Chord 188
$settings=AppWindow 'CodexIsland Settings'
Check 'Ctrl comma opens Settings' ($null -ne $settings -and (State) -eq 'Hidden')
if($settings){$settings.GetCurrentPattern([Windows.Automation.WindowPattern]::Pattern).Close();Wait-UI 450}
Expand
Chord 49
(IslandControl 'Settings').SetFocus();Key 9;Key 13;Wait-UI 700
Check 'Tab and Enter reach the visualization control' ((Get-Content $statePath -Raw|ConvertFrom-Json).chartStyle -eq 0)
(IslandControl 'Cycle visualization (Ctrl+click)').GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke();Wait-UI 300
foreach($i in 1..3){(IslandControl 'Cycle visualization (Ctrl+click)').GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke();Wait-UI 300}
$results|ConvertTo-Json|Set-Content (Join-Path $artifacts 'settings-results.json')
$results|ConvertTo-Json
(IslandControl 'Settings').GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke();Wait-UI 700
if($results.Where({!$_.pass}).Count -gt 0){throw 'Accessibility or keyboard checks failed.'}

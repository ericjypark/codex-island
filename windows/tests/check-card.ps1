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
function AppWindow([string]$name) {
 $pidApp=(Get-Process CodexIslandPrototype|Select-Object -First 1).Id
 $condition=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ProcessIdProperty),$pidApp
 $windows=[Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,$condition)
 return ($windows|Where-Object {$_.Current.Name -eq $name}|Select-Object -First 1)
}
function FindControl([string]$name) {
 $condition=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::NameProperty),$name
 $found=(AppWindow 'Usage card').FindAll([Windows.Automation.TreeScope]::Descendants,$condition)
 return ($found|Where-Object {$_.Current.ControlType -ne [Windows.Automation.ControlType]::Text}|Select-Object -First 1)
}
function InvokeControl([string]$name) {
 $control=FindControl $name;if(!$control){throw "Control not found: $name"}
 $control.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke();Wait-UI 300
}
function ChooseMenu([string]$prefix) {
 $pidApp=(Get-Process CodexIslandPrototype|Select-Object -First 1).Id
 $condition=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ProcessIdProperty),$pidApp
 $items=[Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Descendants,$condition)
 $item=$items|Where-Object {$_.Current.ControlType -eq [Windows.Automation.ControlType]::MenuItem -and $_.Current.Name.StartsWith($prefix)}|Select-Object -First 1
 if(!$item){throw "Menu item not found: $prefix"}
 $item.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke();Wait-UI 400
}
function CaptureWindow([string]$name) {
 $w=AppWindow 'Usage card'
 [CheckInput]::SetForegroundWindow([IntPtr]$w.Current.NativeWindowHandle)|Out-Null
 Wait-UI 300
 $r=$w.Current.BoundingRectangle
 $bmp=New-Object Drawing.Bitmap ([int]$r.Width),([int]$r.Height)
 $g=[Drawing.Graphics]::FromImage($bmp);$g.CopyFromScreen([int]$r.X,[int]$r.Y,0,0,$bmp.Size)
 $bmp.Save((Join-Path $artifacts "$name.png"));$g.Dispose();$bmp.Dispose()
}
function ExportCard([string]$name,[int]$expectedHeight) {
 $w=AppWindow 'Usage card'
 [CheckInput]::SetForegroundWindow([IntPtr]$w.Current.NativeWindowHandle)|Out-Null
 Chord 83
 Wait-UI 300
 $export=Join-Path $env:LOCALAPPDATA ('CodexIslandPrototype\'+$name+'-'+[Guid]::NewGuid().ToString('N')+'.png')
 [Windows.Forms.SendKeys]::SendWait('^a');[Windows.Forms.SendKeys]::SendWait($export);Key 13
 Wait-UI 700
 if(!(Test-Path $export)){throw 'Export did not create an image.'}
 $image=[Drawing.Image]::FromFile($export)
 Check "$name exports at source pixel dimensions" ($image.Width -eq 1080 -and $image.Height -eq $expectedHeight)
 $image.Dispose();Copy-Item $export (Join-Path $artifacts "$name.png")
}
if((State) -ne 'Expanded'){
 [CheckInput]::keybd_event(17,0,0,[UIntPtr]::Zero);[CheckInput]::keybd_event(18,0,0,[UIntPtr]::Zero);Key 73;[CheckInput]::keybd_event(18,0,2,[UIntPtr]::Zero);[CheckInput]::keybd_event(17,0,2,[UIntPtr]::Zero);Wait-UI 900
}
[CheckInput]::Move($cx,100)
[CheckInput]::SetForegroundWindow([IntPtr]$initial.window)|Out-Null
Wait-UI 250
Chord 51
if((Get-Content $statePath -Raw|ConvertFrom-Json).page -ne 2){throw 'Overview did not open for the card check.'}
$panel=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$initial.window)
$condition=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::NameProperty),'Create your usage card'
$share=$panel.FindFirst([Windows.Automation.TreeScope]::Descendants,$condition)
if(!$share){throw 'The accessible usage-card action was not found.'}
$share.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke();Wait-UI 900
$w=AppWindow 'Usage card'
Check 'Overview opens usage-card studio' ($null -ne $w)
if(!$w){throw 'Card studio did not open.'}
[CheckInput]::SetForegroundWindow([IntPtr]$w.Current.NativeWindowHandle)|Out-Null
InvokeControl 'Show, API value'
CaptureWindow 'win-card-studio'
ExportCard 'win-card-feed-apiValue' 1350
InvokeControl 'Format';ChooseMenu 'Square'
ExportCard 'win-card-square-apiValue' 1080
InvokeControl 'Format';ChooseMenu 'Story'
ExportCard 'win-card-story-apiValue' 1920
InvokeControl 'Show, Tokens'
ExportCard 'win-card-story-tokens' 1920
InvokeControl 'Format';ChooseMenu 'Square'
ExportCard 'win-card-square-tokens' 1080
InvokeControl 'Format';ChooseMenu 'Feed'
ExportCard 'win-card-feed-tokens' 1350
InvokeControl 'Actual size'
Check 'Actual size changes to Fit control' ($null -ne (FindControl 'Fit'))
InvokeControl 'Fit'
$signature=FindControl 'Name or handle on card'
$signature.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue('This signature is deliberately longer than thirty-two characters.')
Wait-UI 200
Check 'Signature is limited to 32 characters' ($signature.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).Current.Value.Length -eq 32)
$signature.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue('')
$clipboard=[Windows.Forms.Clipboard]::GetDataObject()
try {
 InvokeControl 'More export options';ChooseMenu 'Copy caption'
 Check 'Caption exports demo provenance and source URL' ([Windows.Forms.Clipboard]::GetText().StartsWith('Demo week:') -and [Windows.Forms.Clipboard]::GetText().Contains('https://codexisland.com'))
 InvokeControl 'More export options';ChooseMenu 'Copy image'
 Check 'Image copies to clipboard' ([Windows.Forms.Clipboard]::ContainsImage())
} finally {if($clipboard){[Windows.Forms.Clipboard]::SetDataObject($clipboard,$true)}else{[Windows.Forms.Clipboard]::Clear()}}
foreach($id in @('Claude','Codex','Grok','Antigravity')) {(FindControl $id).GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Toggle();Wait-UI 180}
Check 'All providers deselected disables export' (!(FindControl 'Share…').Current.IsEnabled)
foreach($id in @('Claude','Codex','Grok','Antigravity')) {(FindControl $id).GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Toggle();Wait-UI 180}
InvokeControl 'Show, API value'
CaptureWindow 'win-card-studio'
$results|ConvertTo-Json|Set-Content (Join-Path $artifacts 'card-results.json')
$results|ConvertTo-Json

if($results.Where({!$_.pass}).Count -gt 0){throw 'Card checks failed.'}

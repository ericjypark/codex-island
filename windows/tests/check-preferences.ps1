$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class PrefInput {
 [DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")]public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr h);
}
'@
[PrefInput]::SetThreadDpiAwarenessContext([IntPtr](-4))|Out-Null
$pidApp=(Get-Process CodexIslandPrototype|Select-Object -First 1).Id
$condition=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ProcessIdProperty),$pidApp
function Window {
 $windows=[Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,$condition)
 return ($windows|Where-Object {$_.Current.Name -eq 'CodexIsland Settings'}|Select-Object -First 1)
}
$w=Window
if(!$w){throw 'Open settings before this check.'}
[PrefInput]::SetForegroundWindow([IntPtr]$w.Current.NativeWindowHandle)|Out-Null
$results=[Collections.Generic.List[object]]::new()
function Find([string]$name) {
 $n=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::NameProperty),$name
 $matches=(Window).FindAll([Windows.Automation.TreeScope]::Descendants,$n)
 return ($matches|Where-Object {$_.Current.ControlType -ne [Windows.Automation.ControlType]::Text}|Select-Object -First 1)
}
function Invoke([string]$name) {
 $el=Find $name;if(!$el){throw "Missing control: $name"}
 $pattern=$el.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern)
 $pattern.Invoke();Start-Sleep -Milliseconds 220
}
function Toggle([string]$name) {
 $el=Find $name;if(!$el){throw "Missing toggle: $name"}
 $el.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Toggle();Start-Sleep -Milliseconds 200
}
function Data {Get-Content "$env:LOCALAPPDATA\CodexIslandPrototype\preferences.json" -Raw|ConvertFrom-Json}
function Check([string]$name,[bool]$pass){$results.Add([pscustomobject]@{check=$name;pass=$pass});if(!$pass){throw "Failed: $name"}}
function Capture([string]$name) {
 [PrefInput]::SetForegroundWindow([IntPtr]$w.Current.NativeWindowHandle)|Out-Null
 Start-Sleep -Milliseconds 300
 $r=$w.Current.BoundingRectangle
 $bmp=New-Object Drawing.Bitmap ([int]$r.Width),([int]$r.Height)
 $g=[Drawing.Graphics]::FromImage($bmp);$g.CopyFromScreen([int]$r.X,[int]$r.Y,0,0,$bmp.Size)
 $bmp.Save((Join-Path $PSScriptRoot "..\artifacts\$name.png"));$g.Dispose();$bmp.Dispose()
}
Invoke 'Usage display, Remaining'
Check 'Remaining mode is persisted' ((Data).Remaining -eq $true)
Invoke 'Usage display, Used'
Invoke 'Ring'
Check 'Chart selection is persisted' ((Data).ChartStyle -eq 0)
Invoke 'Sparkline'
Capture 'win-settings-display'
Invoke 'General'
$before=(Data).AlwaysShowUsage
Toggle 'Always show usage'
Check 'Always show usage changes state' ((Get-Content "$env:LOCALAPPDATA\CodexIslandPrototype\state.json" -Raw|ConvertFrom-Json).state -eq 'Peek')
Toggle 'Always show usage'
Check 'Always show can return to hidden' ((Get-Content "$env:LOCALAPPDATA\CodexIslandPrototype\state.json" -Raw|ConvertFrom-Json).state -eq 'Hidden')
Invoke 'Refresh interval, 15m'
Check 'Refresh preset persists at 15 minutes' ((Data).RefreshSeconds -eq 900)
Invoke 'Refresh interval, 5m'
$before=(Data).LowPower
Toggle 'Low Power Mode'
Check 'Low power setting is persisted' ((Data).LowPower -ne $before)
Toggle 'Low Power Mode'
Capture 'win-settings-general'
Invoke 'Providers'
$before=(Data).LeftProvider
Invoke 'Swap left and right'
Check 'Provider order swaps' ((Data).RightProvider -eq $before)
Invoke 'Swap left and right'
Invoke 'Token counting, Input + output'
Check 'Token mode is persisted' ((Data).TokenMode -eq 'billable')
Invoke 'Token counting, All tokens'
Capture 'win-settings-providers'
Invoke 'Display'
$results|ConvertTo-Json|Set-Content (Join-Path $PSScriptRoot '..\artifacts\preferences-results.json')
$results|ConvertTo-Json

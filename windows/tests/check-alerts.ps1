param([switch]$InputOnly)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing,UIAutomationClient,UIAutomationTypes
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class AlertInput {
 [DllImport("user32.dll")] public static extern int GetSystemMetrics(int metric);
 public static void Move(int x,int y) {mouse_event(0x8001,(uint)(x*65535.0/(GetSystemMetrics(0)-1)),(uint)(y*65535.0/(GetSystemMetrics(1)-1)),0,UIntPtr.Zero);}
 [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr window,uint message,IntPtr w,IntPtr l);
 [DllImport("user32.dll")] public static extern void mouse_event(uint flags,uint x,uint y,uint data,UIntPtr extra);
}
'@
[AlertInput]::SetThreadDpiAwarenessContext([IntPtr](-4))|Out-Null
$root=Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype'
$statePath=Join-Path $root 'state.json'
$prefsPath=Join-Path $root 'preferences.json'
$artifacts=Join-Path $PSScriptRoot '..\artifacts'
$saved=[IO.File]::ReadAllText($prefsPath)
$results=[Collections.Generic.List[object]]::new()
function Wait-UI([int]$ms) {
 $watch=[Diagnostics.Stopwatch]::StartNew()
 while($watch.ElapsedMilliseconds -lt $ms){[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 10}
}
function State {Get-Content $statePath -Raw|ConvertFrom-Json}
function Stop-Preview {
 $running=Get-Process CodexIslandPrototype -ErrorAction SilentlyContinue
 if(!$running){return}
 [AlertInput]::PostMessage([IntPtr](State).window,16,[IntPtr]::Zero,[IntPtr]::Zero)|Out-Null
 foreach($process in $running){if(!$process.WaitForExit(5000)){throw 'The preview did not close cleanly.'}}
}
function Start-Preview([bool]$alerts) {
 $info=@{FilePath=(Join-Path $root 'app\CodexIslandPrototype.exe')}
 if($alerts){$info.ArgumentList='--preview-alerts'}
 Start-Process @info
 Wait-UI 1500
}
function Check([string]$name,[bool]$pass){$results.Add([pscustomobject]@{check=$name;pass=$pass;state=(State)})}
function Find-Control($window,[string]$name) {
 $condition=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::NameProperty),$name
 $control=$window.FindAll([Windows.Automation.TreeScope]::Descendants,$condition)|Where-Object {$_.Current.ControlType -ne [Windows.Automation.ControlType]::Text}|Select-Object -First 1
 if(!$control){throw "Missing control: $name"};return $control
}
function Invoke($window,[string]$name){(Find-Control $window $name).GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke();Wait-UI 150}
function Cursor([int]$x,[int]$y){[AlertInput]::Move($x,$y);Wait-UI 60}
function Focus-CheckWindow {
 $focusWindow.Show();$focusWindow.TopMost=$true;$focusWindow.Activate()
 Cursor ($focusWindow.Left+100) ($focusWindow.Top+100)
 [AlertInput]::mouse_event(2,0,0,0,[UIntPtr]::Zero);[AlertInput]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
 Wait-UI 250;$focusWindow.TopMost=$false;Wait-UI 250
 if([AlertInput]::GetForegroundWindow() -ne $focusWindow.Handle){throw 'The test window did not obtain foreground focus.'}
}
function Expand {
 Cursor $cx 800;Wait-UI 500;Cursor $cx 1;Wait-UI 750
 [AlertInput]::mouse_event(2,0,0,0,[UIntPtr]::Zero);[AlertInput]::mouse_event(4,0,0,0,[UIntPtr]::Zero);Wait-UI 900
 if((State).state -ne 'Expanded'){throw ('Hover and click did not expand the panel: '+((State)|ConvertTo-Json -Depth 5))}
}
function Capture([string]$name) {
 $bmp=New-Object Drawing.Bitmap 1100,160;$g=[Drawing.Graphics]::FromImage($bmp)
 $g.CopyFromScreen($cx-550,0,0,0,$bmp.Size);$bmp.Save((Join-Path $artifacts "$name.png"));$g.Dispose();$bmp.Dispose()
}
try {
 Stop-Preview
 $prefs=$saved|ConvertFrom-Json
 $prefs.AlertsEnabled=$true;$prefs.WarningPercent=80;$prefs.CriticalPercent=95;$prefs.AlwaysShowUsage=$false
 $prefs.SettingsTab='general';$prefs.Language='en';$prefs.ReduceMotion=$false;$prefs.LowPower=$false
 $prefs.LeftProvider='codex';$prefs.RightProvider='antigravity';$prefs.Remaining=$false
 $prefs|ConvertTo-Json|Set-Content $prefsPath
 Start-Preview $true
 $initial=State;$cx=[int]($initial.screen.X+$initial.screen.Width/2)
 if($initial.scale -ne 2){throw 'Alert capture coordinates require 200 percent scaling.'}
 $focusWindow=New-Object Windows.Forms.Form
 $focusWindow.Text='CodexIsland alert interaction check';$focusWindow.StartPosition='Manual'
 $focusWindow.Left=$cx-400;$focusWindow.Top=800;$focusWindow.Width=800;$focusWindow.Height=200
 $focusWindow.Show();$focusWindow.Activate();Wait-UI 400
 Check 'Dedicated alert fixture mode is active' $initial.previewAlerts
 Expand
 if($InputOnly){Check 'Hover opens after relaunch' ((State).state -eq 'Expanded');return}
 $island=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$initial.window)
 Invoke $island 'Settings';Cursor $cx 850;Wait-UI 700
 $condition=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ProcessIdProperty),(Get-Process CodexIslandPrototype).Id
 $settings=[Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,$condition)|Where-Object {$_.Current.Name -eq 'CodexIsland Settings'}|Select-Object -First 1
 if(!$settings){throw 'Settings window not found.'}
 $foreground=[AlertInput]::GetForegroundWindow()
 $watch=[Diagnostics.Stopwatch]::StartNew();Invoke $settings 'Warn';Wait-UI 750
 $warning=State
 Check 'Warning opens a held peek with only the crossed provider tinted' ($warning.state -eq 'Peek' -and $warning.pulseHolding -and $warning.alertSeverity -eq 'Warning' -and $warning.providerAlerts.codex -eq 1 -and $null -eq $warning.providerAlerts.antigravity)
 Check 'An automatic pulse preserves the foreground application' ([AlertInput]::GetForegroundWindow() -eq $foreground)
 Capture 'alert-warning-windows'
 Wait-UI 2100
 Check 'Pulse remains visible before its four-second expiry' ((State).state -eq 'Peek' -and $watch.ElapsedMilliseconds -lt 4000)
 Wait-UI ([Math]::Max(0,4500-$watch.ElapsedMilliseconds))
 Check 'Unattended pulse dismisses after four seconds' ((State).state -eq 'Hidden' -and !(State).pulseHolding)
 Invoke $settings 'Crit';Wait-UI 750;Capture 'alert-critical-windows'
 Check 'Critical crossing uses red severity' ((State).alertSeverity -eq 'Critical' -and (State).state -eq 'Peek')
 Cursor $cx 35;Wait-UI 4200
 Check 'Hover keeps the peek open after pulse expiry' ((State).state -eq 'Peek' -and !(State).pulseHolding)
 Cursor $cx 850;Wait-UI 900
 Check 'Leaving after pulse expiry restores ordinary dismissal' ((State).state -eq 'Hidden')
 Invoke $settings 'Both';Wait-UI 750;Capture 'alert-both-windows'
 Check 'Simultaneous warnings retain each provider severity' ((State).providerAlerts.codex -eq 1 -and (State).providerAlerts.antigravity -eq 2 -and (State).alertSeverity -eq 'Critical')
 (Find-Control $settings 'Always show usage').GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Toggle();Wait-UI 4300
 Check 'Always show usage retains the peek after pulse expiry' ((State).state -eq 'Peek' -and !(State).pulseHolding)
 (Find-Control $settings 'Always show usage').GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Toggle();Wait-UI 600
 Expand
 $before=(State).pulseCount
 Invoke $settings 'Warn';Wait-UI 750
 Check 'Expanded panel consumes the alert without opening a pulse' ((State).state -eq 'Expanded' -and (State).pulseCount -eq $before -and !(State).pulseHolding)
 (Find-Control $settings 'Approaching-limit alerts').GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Toggle();Wait-UI 600
 Check 'Disabling alerts clears provider and combined severity' ((State).alertSeverity -eq 'None' -and @((State).providerAlerts.PSObject.Properties).Count -eq 0)
 Cursor $cx 850;Wait-UI 800
 (Find-Control $settings 'Always show usage').GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Toggle()
 (Find-Control $settings 'Low Power Mode').GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Toggle()
 Focus-CheckWindow;Wait-UI 800
 Check 'Low Power stops an unattended peek sweep without active alerts' ((State).state -eq 'Peek' -and (State).effectiveLowPower -and !(State).sweepActive)
 (Find-Control $settings 'Approaching-limit alerts').GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Toggle();Wait-UI 700
 Check 'An active warning keeps the Low Power event glow running' ((State).alertSeverity -eq 'Warning' -and (State).sweepActive)
 Invoke $settings 'Demo';Wait-UI 700
 Check 'Clearing the alert stops the Low Power event glow' ((State).alertSeverity -eq 'None' -and !(State).sweepActive)
 $before=(State).pulseCount
 Invoke $settings 'Both in 3s'
 $focusWindow.FormBorderStyle='None'
 $focusWindow.Bounds=New-Object Drawing.Rectangle $initial.screen.X,$initial.screen.Y,$initial.screen.Width,$initial.screen.Height
 Focus-CheckWindow;Wait-UI 1000
 if(!(State).contextSuppressed){throw 'The scheduled-alert fixture did not establish full-screen suppression.'}
 Wait-UI 2500
 Check 'An alert during full screen updates severity without revealing or starting the sweep' ((State).contextSuppressed -and (State).state -eq 'Hidden' -and (State).alertSeverity -eq 'Critical' -and !(State).sweepActive -and !(State).pulseHolding -and (State).pulseCount -eq $before)
 Check 'A suppressed alert leaves full-screen foreground unchanged' ([AlertInput]::GetForegroundWindow() -eq $focusWindow.Handle)
 $focusWindow.FormBorderStyle='Sizable';$focusWindow.Bounds=New-Object Drawing.Rectangle ($cx-400),800,800,200;Wait-UI 1000
 Check 'Ending full screen restores always-visible alert glow under Low Power' (!(State).contextSuppressed -and (State).state -eq 'Peek' -and (State).sweepActive)
 Stop-Preview;Start-Preview $false
 Check 'Normal demo startup has no fixture pulse path' (!(State).previewAlerts -and (State).pulseCount -eq 0)
} finally {
 if($focusWindow){$focusWindow.Close();$focusWindow.Dispose()}
 Stop-Preview
 [IO.File]::WriteAllText($prefsPath,$saved)
 Start-Preview $false
 $results|ConvertTo-Json -Depth 10|Set-Content (Join-Path $artifacts 'alert-results.json')
 $results|Select-Object check,pass|Format-Table -AutoSize
}
if($results.Where({!$_.pass}).Count -gt 0){throw 'Alert interaction checks failed.'}

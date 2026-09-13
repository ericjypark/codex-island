$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
Add-Type @'
using System;using System.Runtime.InteropServices;
public static class CardStudioInput {
 [DllImport("user32.dll")]public static extern void keybd_event(byte key,byte scan,uint flags,UIntPtr extra);
 [DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr window);
 [DllImport("user32.dll")]public static extern void mouse_event(uint flags,uint x,uint y,uint data,UIntPtr extra);
 [DllImport("user32.dll")]public static extern int GetSystemMetrics(int metric);
 public static void Move(int x,int y){mouse_event(0x8001,(uint)(x*65535.0/(GetSystemMetrics(0)-1)),(uint)(y*65535.0/(GetSystemMetrics(1)-1)),0,UIntPtr.Zero);}
}
'@
function Key([byte]$key){[CardStudioInput]::keybd_event($key,0,0,[UIntPtr]::Zero);[CardStudioInput]::keybd_event($key,0,2,[UIntPtr]::Zero)}
$state=Get-Content (Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype\state.json') -Raw|ConvertFrom-Json
[CardStudioInput]::Move([int]($state.screen.Width/2),100)
if($state.state -ne 'Expanded'){
 [CardStudioInput]::keybd_event(17,0,0,[UIntPtr]::Zero);[CardStudioInput]::keybd_event(18,0,0,[UIntPtr]::Zero);Key 73
 [CardStudioInput]::keybd_event(18,0,2,[UIntPtr]::Zero);[CardStudioInput]::keybd_event(17,0,2,[UIntPtr]::Zero);Start-Sleep -Milliseconds 700
}
[CardStudioInput]::SetForegroundWindow([IntPtr]$state.window)|Out-Null
[CardStudioInput]::keybd_event(17,0,0,[UIntPtr]::Zero);Key 51;[CardStudioInput]::keybd_event(17,0,2,[UIntPtr]::Zero);Start-Sleep -Milliseconds 900
$appProcess=Get-Process CodexIslandPrototype|Select-Object -First 1
$condition=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ProcessIdProperty),$appProcess.Id
$panel=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$state.window)
if(!$panel){throw 'The island did not open.'}
$controls=$panel.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)
$button=$controls|Where-Object {$_.Current.Name -eq 'Create your usage card' -or $_.Current.Name -eq 'Share usage'}|Select-Object -First 1
if(!$button){
 [CardStudioInput]::SetForegroundWindow([IntPtr]$state.window)|Out-Null
 [CardStudioInput]::keybd_event(17,0,0,[UIntPtr]::Zero);Key 188;[CardStudioInput]::keybd_event(17,0,2,[UIntPtr]::Zero);Start-Sleep -Milliseconds 500
 $settings=[Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,$condition)|Where-Object {$_.Current.Name -eq 'CodexIsland Settings'}|Select-Object -First 1
 if(!$settings){throw 'Settings did not open.'}
 $general=$settings.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)|Where-Object {$_.Current.Name -eq 'General' -and $_.Current.ControlType -eq [Windows.Automation.ControlType]::Button}|Select-Object -First 1
 $general.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke();Start-Sleep -Milliseconds 250
 $button=$settings.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)|Where-Object {$_.Current.Name.StartsWith('Create card') -and $_.Current.ControlType -eq [Windows.Automation.ControlType]::Button}|Select-Object -First 1
 if(!$button){throw 'The Create card action was unavailable.'}
}
$button.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
Start-Sleep -Milliseconds 900
$window=[Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,$condition)|Where-Object {$_.Current.Name -eq 'Usage card'}|Select-Object -First 1
if(!$window){throw 'The usage card did not open.'}
[CardStudioInput]::SetForegroundWindow([IntPtr]$window.Current.NativeWindowHandle)|Out-Null
'Updated usage card is open.'

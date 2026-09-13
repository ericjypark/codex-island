$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
Add-Type @'
using System;using System.Runtime.InteropServices;
public static class ProviderSettingsInput {
 [DllImport("user32.dll")]public static extern void keybd_event(byte key,byte scan,uint flags,UIntPtr extra);
 [DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr window);
}
'@
function Key([byte]$key){[ProviderSettingsInput]::keybd_event($key,0,0,[UIntPtr]::Zero);[ProviderSettingsInput]::keybd_event($key,0,2,[UIntPtr]::Zero)}
$state=Get-Content (Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype\state.json') -Raw|ConvertFrom-Json
if($state.state -ne 'Expanded'){
 [ProviderSettingsInput]::keybd_event(17,0,0,[UIntPtr]::Zero);[ProviderSettingsInput]::keybd_event(18,0,0,[UIntPtr]::Zero);Key 73
 [ProviderSettingsInput]::keybd_event(18,0,2,[UIntPtr]::Zero);[ProviderSettingsInput]::keybd_event(17,0,2,[UIntPtr]::Zero);Start-Sleep -Milliseconds 700
}
[ProviderSettingsInput]::SetForegroundWindow([IntPtr]$state.window)|Out-Null
[ProviderSettingsInput]::keybd_event(17,0,0,[UIntPtr]::Zero);Key 188;[ProviderSettingsInput]::keybd_event(17,0,2,[UIntPtr]::Zero);Start-Sleep -Milliseconds 500
$appProcess=Get-Process CodexIslandPrototype|Select-Object -First 1
$condition=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ProcessIdProperty),$appProcess.Id
$settings=[Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,$condition)|Where-Object {$_.Current.Name -eq 'CodexIsland Settings'}|Select-Object -First 1
if(!$settings){throw 'Settings did not open.'}
$condition=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::NameProperty),'Providers'
$button=$settings.FindAll([Windows.Automation.TreeScope]::Descendants,$condition)|Where-Object {$_.Current.ControlType -eq [Windows.Automation.ControlType]::Button}|Select-Object -First 1
$button.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
'Providers settings is open.'

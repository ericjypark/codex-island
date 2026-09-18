$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class ShareInput {
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr h);
 [DllImport("user32.dll")] public static extern void keybd_event(byte key,byte scan,uint flags,UIntPtr extra);
}
'@
[ShareInput]::SetThreadDpiAwarenessContext([IntPtr](-4))|Out-Null
$condition=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::NameProperty),'Usage card'
$w=[Windows.Automation.AutomationElement]::RootElement.FindFirst([Windows.Automation.TreeScope]::Children,$condition)
if(!$w){throw 'Open the card studio before testing the native share dialog.'}
[ShareInput]::SetForegroundWindow([IntPtr]$w.Current.NativeWindowHandle)|Out-Null
$name='Share'+[char]0x2026
$condition=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::NameProperty),$name
$button=$w.FindFirst([Windows.Automation.TreeScope]::Descendants,$condition)
$button.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
Start-Sleep -Milliseconds 4000
$windows=[Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,[Windows.Automation.Condition]::TrueCondition)
$names=@($windows|ForEach-Object {$_.Current.Name})
$shareWindows=@($windows|Where-Object {$_.Current.Name -eq 'Share'})
$payloadNames=@()
foreach($shareWindow in $shareWindows){$payloadNames += @($shareWindow.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)|ForEach-Object {$_.Current.Name}|Where-Object {$_.StartsWith('CodexIsland-') -and $_.Contains('.png')})}
$results=[pscustomobject]@{shareWindowExposedToUia=($shareWindows.Count -gt 0);payloadExposedToUia=($payloadNames.Count -gt 0);payloadNames=$payloadNames}
$results|ConvertTo-Json|Set-Content (Join-Path $PSScriptRoot '..\artifacts\native-share-results.json')
$results|ConvertTo-Json
$bounds=[Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp=New-Object Drawing.Bitmap $bounds.Width,$bounds.Height
$g=[Drawing.Graphics]::FromImage($bmp);$g.CopyFromScreen(0,0,0,0,$bmp.Size)
$bmp.Save((Join-Path $PSScriptRoot '..\artifacts\win-native-share.png'));$g.Dispose();$bmp.Dispose()
[ShareInput]::keybd_event(27,0,0,[UIntPtr]::Zero)
[ShareInput]::keybd_event(27,0,2,[UIntPtr]::Zero)

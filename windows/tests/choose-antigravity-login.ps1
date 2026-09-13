$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
Add-Type @'
using System;using System.Runtime.InteropServices;
public static class AgyLoginInput {
 [DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr window);
 [DllImport("user32.dll")]public static extern void keybd_event(byte key,byte scan,uint flags,UIntPtr extra);
}
'@
$windows=[Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,[Windows.Automation.Condition]::TrueCondition)
$target=$null
foreach($window in $windows){
 if($window.Current.ClassName -notmatch 'CASCADIA|ConsoleWindowClass'){continue}
 foreach($control in $window.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)){
  try{
   $text=$control.GetCurrentPattern([Windows.Automation.TextPattern]::Pattern).DocumentRange.GetText(-1)
   if($text.Contains('Select login method:') -and $text.Contains('> 1. Google OAuth') -and $text.Contains('currently not signed in')){$target=$window;break}
  }catch{}
 }
 if($target){break}
}
if(!$target){throw 'The Antigravity Google OAuth choice is not the current terminal screen.'}
[AgyLoginInput]::SetForegroundWindow([IntPtr]$target.Current.NativeWindowHandle)|Out-Null
Start-Sleep -Milliseconds 200
[AgyLoginInput]::keybd_event(13,0,0,[UIntPtr]::Zero);[AgyLoginInput]::keybd_event(13,0,2,[UIntPtr]::Zero)
'Antigravity Google OAuth login was selected.'

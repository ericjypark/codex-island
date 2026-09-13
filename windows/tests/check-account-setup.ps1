param([switch]$InstallCodex,[switch]$SignInCodex)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Drawing
Add-Type @'
using System;using System.Runtime.InteropServices;
public static class AccountInput {
 [DllImport("user32.dll")]public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
 [DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr window);
}
'@
[AccountInput]::SetThreadDpiAwarenessContext([IntPtr](-4))|Out-Null
$process=Get-Process CodexIslandPrototype|Select-Object -First 1
$condition=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ProcessIdProperty),$process.Id
$window=[Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,$condition)|Where-Object {$_.Current.Name -eq 'CodexIsland Settings'}|Select-Object -First 1
if(!$window){throw 'Open Providers settings first.'}
function Controls {$window.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)}
function Account([string]$id){Controls|Where-Object {$_.Current.AutomationId -eq ('ConnectAccount_'+$id)}|Select-Object -First 1}
$codex=Account 'codex';$claude=Account 'claude'
if(!$codex -or !$claude){throw 'Both account controls must remain available regardless of island selection.'}
$before=$codex.Current.Name
if((Controls|Where-Object {$_.Current.Name -eq 'Open Codex CLI'})){throw 'The misleading website fallback is still present.'}
if($InstallCodex){
 if($before -ne 'Install Codex'){throw 'Codex is already installed; this run will not reinstall it.'}
 $codex.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
 Start-Sleep -Milliseconds 500
 if((Account 'codex').Current.IsEnabled){throw 'Installation should disable duplicate clicks.'}
 $deadline=[DateTime]::UtcNow.AddMinutes(10)
 do {Start-Sleep -Seconds 2;$codex=Account 'codex'} while(!$codex.Current.IsEnabled -and [DateTime]::UtcNow -lt $deadline)
 if($codex.Current.Name -ne 'Sign in with ChatGPT'){throw 'The installer did not reach the sign-in step.'}
}
$artifacts=Join-Path $PSScriptRoot '..\artifacts'
[AccountInput]::SetForegroundWindow([IntPtr]$window.Current.NativeWindowHandle)|Out-Null
Start-Sleep -Milliseconds 300
$rect=$window.Current.BoundingRectangle
$bitmap=New-Object Drawing.Bitmap ([int]$rect.Width),([int]$rect.Height)
$graphics=[Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen([int]$rect.Left,[int]$rect.Top,0,0,$bitmap.Size)
$bitmap.Save((Join-Path $artifacts 'account-settings.png'),[Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose();$bitmap.Dispose()
$result=[pscustomobject]@{bothAccountsVisible=$true;websiteFallbackAbsent=$true;before=$before;codexAction=(Account 'codex').Current.Name;claudeAction=(Account 'claude').Current.Name;installedThroughUI=[bool]$InstallCodex}
$result|ConvertTo-Json|Set-Content (Join-Path $artifacts $(if($InstallCodex){'account-install-results.json'}else{'account-setup-results.json'}))
$result|ConvertTo-Json
if($SignInCodex){
 if((Account 'codex').Current.Name -ne 'Sign in with ChatGPT'){throw 'Sign-in is not ready.'}
 (Account 'codex').GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
 Start-Sleep -Seconds 3
 [pscustomobject]@{loginStarted=!(Account 'codex').Current.IsEnabled}|ConvertTo-Json
}

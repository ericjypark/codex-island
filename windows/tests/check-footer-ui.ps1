param([Parameter(Mandatory=$true)][string]$Snapshot)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Drawing,System.Windows.Forms
Add-Type @'
using System;using System.Runtime.InteropServices;
public static class FooterInput {
 [DllImport("user32.dll")]public static extern void keybd_event(byte key,byte scan,uint flags,UIntPtr extra);
 [DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr window);
 [DllImport("user32.dll")]public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
 [DllImport("user32.dll")]public static extern int GetSystemMetrics(int metric);
 [DllImport("user32.dll")]public static extern void mouse_event(uint flags,uint x,uint y,uint data,UIntPtr extra);
 public static void Move(int x,int y){mouse_event(0x8001,(uint)(x*65535.0/(GetSystemMetrics(0)-1)),(uint)(y*65535.0/(GetSystemMetrics(1)-1)),0,UIntPtr.Zero);}
}
'@
[FooterInput]::SetThreadDpiAwarenessContext([IntPtr](-4))|Out-Null
$profile=Get-Content (Join-Path $Snapshot 'interactive-profile.json') -Raw|ConvertFrom-Json
$statePath=Join-Path $profile.profile 'state.json'
function State {Get-Content $statePath -Raw|ConvertFrom-Json}
function Key([byte]$key){[FooterInput]::keybd_event($key,0,0,[UIntPtr]::Zero);[FooterInput]::keybd_event($key,0,2,[UIntPtr]::Zero)}
$state=State
if($state.sampleData){throw 'The footer must be verified with the real history profile.'}
$appProcess=Get-Process CodexIslandPrototype|Where-Object {$_.Path -eq $profile.executable}|Select-Object -First 1
if(!$appProcess){throw 'The intended preview is not running.'}
[FooterInput]::Move([int]($state.screen.Width/2),60)
if($state.state -ne 'Expanded'){
 [FooterInput]::keybd_event(17,0,0,[UIntPtr]::Zero);[FooterInput]::keybd_event(18,0,0,[UIntPtr]::Zero);Key 73
 [FooterInput]::keybd_event(18,0,2,[UIntPtr]::Zero);[FooterInput]::keybd_event(17,0,2,[UIntPtr]::Zero);Start-Sleep -Milliseconds 800
}
[FooterInput]::SetForegroundWindow([IntPtr](State).window)|Out-Null
[FooterInput]::keybd_event(17,0,0,[UIntPtr]::Zero);Key 51;[FooterInput]::keybd_event(17,0,2,[UIntPtr]::Zero)
Start-Sleep -Milliseconds 800
$window=[Windows.Automation.AutomationElement]::FromHandle([IntPtr](State).window)
function Elements {$window.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)}
function Status {Elements|Where-Object {$_.Current.AutomationId -eq 'island-Refresh now'}|Select-Object -First 1}
$surface=Elements|Where-Object {$_.Current.ClassName -eq 'CodexIsland'}|Select-Object -First 1
if(!$surface.Current.Name.Contains('14,061,868,359 tokens')){throw 'The imported history total changed.'}
$deadline=(Get-Date).AddSeconds(25)
do{Start-Sleep -Milliseconds 250;$status=Status}while((!$status -or !$status.Current.IsEnabled) -and (Get-Date) -lt $deadline)
if(!$status -or !$status.Current.Name.StartsWith('Synced ')){throw 'The live history footer is not synced.'}
$before=(State).providerStatus|ConvertTo-Json -Compress
$status.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
Start-Sleep -Milliseconds 500
$deadline=(Get-Date).AddSeconds(25)
do{Start-Sleep -Milliseconds 200;$status=Status}while(!$status.Current.Name.StartsWith('Synced ') -and (Get-Date) -lt $deadline)
if(!$status.Current.Name.StartsWith('Synced ')){throw 'History refresh did not complete.'}
if(((State).providerStatus|ConvertTo-Json -Compress) -ne $before){throw 'History footer refresh also changed quota request state.'}
$first=$status.Current.Name;Start-Sleep -Milliseconds 2200;$second=(Status).Current.Name
if($first -match 'Synced \d+s ago' -and $first -eq $second){throw 'Elapsed seconds did not advance.'}
$bounds=$surface.Current.BoundingRectangle
$pageButton=Elements|Where-Object {$_.Current.AutomationId -eq 'island-Overview (Ctrl+3)'}|Select-Object -First 1
if(!$pageButton){throw 'The current page control is unavailable.'}
$pageButton.SetFocus()
$output=Join-Path $PSScriptRoot '..\artifacts\footer-confirmed';New-Item -ItemType Directory -Force $output|Out-Null
function Capture([string]$name){
 $bitmap=New-Object Drawing.Bitmap 400,180;$graphics=[Drawing.Graphics]::FromImage($bitmap)
 try{$graphics.CopyFromScreen([int]($bounds.Right-360),[int]($bounds.Bottom-130),0,0,$bitmap.Size);$bitmap.Save((Join-Path $output ($name+'.png')))}finally{$graphics.Dispose();$bitmap.Dispose()}
}
[FooterInput]::Move([int]($bounds.X+$bounds.Width/2),[int]($bounds.Y+25));Start-Sleep -Milliseconds 350;Capture 'installed-normal'
$buttonBounds=(Status).Current.BoundingRectangle
[FooterInput]::Move([int]($buttonBounds.X+$buttonBounds.Width/2),[int]($buttonBounds.Y+$buttonBounds.Height/2));Start-Sleep -Milliseconds 450;Capture 'installed-hover'
[FooterInput]::Move([int]($bounds.X+$bounds.Width/2),[int]($bounds.Y+25));Start-Sleep -Milliseconds 300
$state=State
@{build=$state.build;sampleData=$state.sampleData;page=$state.page;yearTokens=14061868359;before=$first;after=$second;historyRefreshDidNotRequestQuota=$true;effectiveLowPower=$state.effectiveLowPower;verifiedAt=[DateTimeOffset]::UtcNow.ToString('O')}|ConvertTo-Json|Set-Content (Join-Path $output 'installed-results.json')
Write-Output ('Verified real-history footer: '+$first+' -> '+$second+'; build '+$state.build)

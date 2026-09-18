param([Parameter(Mandatory=$true)][string]$Snapshot)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Drawing
Add-Type @'
using System;using System.Runtime.InteropServices;
public static class ResetInput {
 [DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr window);
 [DllImport("user32.dll")]public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
 [DllImport("user32.dll")]public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")]public static extern int GetSystemMetrics(int metric);
 [DllImport("user32.dll")]public static extern void mouse_event(uint flags,uint x,uint y,uint data,UIntPtr extra);
 public static void Move(int x,int y){mouse_event(0x8001,(uint)(x*65535.0/(GetSystemMetrics(0)-1)),(uint)(y*65535.0/(GetSystemMetrics(1)-1)),0,UIntPtr.Zero);}
 [DllImport("user32.dll")]public static extern void keybd_event(byte key,byte scan,uint flags,UIntPtr extra);
}
'@
[ResetInput]::SetThreadDpiAwarenessContext([IntPtr](-4))|Out-Null
$profile=Get-Content (Join-Path $Snapshot 'interactive-profile.json') -Raw|ConvertFrom-Json
$statePath=Join-Path $profile.profile 'state.json'
function State {Get-Content $statePath -Raw|ConvertFrom-Json}
function Key([byte]$key){[ResetInput]::keybd_event($key,0,0,[UIntPtr]::Zero);[ResetInput]::keybd_event($key,0,2,[UIntPtr]::Zero)}
function Toggle {
 [ResetInput]::keybd_event(17,0,0,[UIntPtr]::Zero);[ResetInput]::keybd_event(18,0,0,[UIntPtr]::Zero);Key 73
 [ResetInput]::keybd_event(18,0,2,[UIntPtr]::Zero);[ResetInput]::keybd_event(17,0,2,[UIntPtr]::Zero)
 Start-Sleep -Milliseconds 800
}
function Elements {
 $window=[Windows.Automation.AutomationElement]::FromHandle([IntPtr](State).window)
 $window.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)
}
function Rows {Elements|Where-Object {$_.Current.Name.StartsWith('Codex reset expires ')}}
function Hover($item){$r=$item.Current.BoundingRectangle;[ResetInput]::Move([int]($r.X+$r.Width/2),[int]($r.Y+$r.Height/2));Start-Sleep -Milliseconds 350}
$process=Get-Process CodexIslandPrototype|Where-Object {$_.Path -eq $profile.executable}|Select-Object -First 1
if(!$process){throw 'The intended history preview is not running.'}
$state=State
if($state.sampleData){throw 'The account preview must use live data.'}
if($state.state -eq 'Expanded'){Toggle}
[ResetInput]::Move([int]($state.screen.Width/2),80)
Toggle
[ResetInput]::SetForegroundWindow([IntPtr](State).window)|Out-Null
$deadline=(Get-Date).AddSeconds(25)
do {
 $badge=Elements|Where-Object {$_.Current.Name -match '^\d+ Codex resets? available$'}|Select-Object -First 1
 if(!$badge){Start-Sleep -Milliseconds 500}
}while(!$badge -and (Get-Date) -lt $deadline)
if(!$badge){throw 'The live reset-credit badge is unavailable.'}
$label=$badge.Current.Name
Hover $badge
$rows=@(Rows)
$dates=@($rows|ForEach-Object {$_.Current.Name})
$surface=Elements|Where-Object {$_.Current.ClassName -eq 'CodexIsland'}|Select-Object -First 1
$bounds=$surface.Current.BoundingRectangle
$bitmap=New-Object Drawing.Bitmap ([int]$bounds.Width),([int]$bounds.Height)
$graphics=[Drawing.Graphics]::FromImage($bitmap)
try{$graphics.CopyFromScreen([int]$bounds.X,[int]$bounds.Y,0,0,$bitmap.Size);$bitmap.Save((Join-Path $PSScriptRoot '..\artifacts\codex-reset-live-windows.png'))}finally{$graphics.Dispose();$bitmap.Dispose()}
if($rows.Count -eq 0 -or $rows.Count -gt 3){Write-Output ('Badge bounds: '+$badge.Current.BoundingRectangle);throw 'The live hover panel did not expose expiration details.'}
Hover $rows[0]
if(@(Rows).Count -eq 0){throw 'Moving into the live expiration panel dismissed it.'}
Key 27;Start-Sleep -Milliseconds 250
if((State).state -ne 'Expanded' -or @(Rows).Count -ne 0){throw 'Escape did not close just the credit details.'}
[ResetInput]::Move([int]($bounds.X+$bounds.Width/2),[int]($bounds.Y+100))
Start-Sleep -Milliseconds 150
Hover $badge
if(@(Rows).Count -eq 0){throw 'The live reset panel did not reopen after dismissal.'}
[pscustomobject]@{build=(State).build;sampleData=(State).sampleData;badge=$label;expirationRows=$dates;nativeHover=$true;firstHoverAfterExpand=$true;crossIntoPanel=$true;escapeLeavesIslandExpanded=$true;reopens=$true;verifiedAt=[DateTimeOffset]::UtcNow}|ConvertTo-Json|Set-Content (Join-Path $PSScriptRoot '..\artifacts\codex-reset-ui-results.json')
Write-Output ('Verified live badge, expiration panel, Escape, and reopen on build '+(State).build)

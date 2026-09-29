param([Parameter(Mandatory=$true)][string]$Snapshot,[switch]$FromPeek)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
Add-Type @'
using System;using System.Runtime.InteropServices;
public static class HoverProbe {
 [StructLayout(LayoutKind.Sequential)] public struct Point {public int X,Y;}
 [DllImport("user32.dll")] public static extern bool GetCursorPos(out Point point);
 [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(Point point);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window,out uint process);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
 [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
 [DllImport("user32.dll")] public static extern int GetSystemMetrics(int metric);
 [DllImport("user32.dll")] public static extern void mouse_event(uint flags,uint x,uint y,uint data,UIntPtr extra);
 [DllImport("user32.dll")] public static extern void keybd_event(byte key,byte scan,uint flags,UIntPtr extra);
 public static void Move(int x,int y){mouse_event(0x8001,(uint)(x*65535.0/(GetSystemMetrics(0)-1)),(uint)(y*65535.0/(GetSystemMetrics(1)-1)),0,UIntPtr.Zero);}
}
'@
[HoverProbe]::SetThreadDpiAwarenessContext([IntPtr](-4))|Out-Null
$profile=Get-Content (Join-Path $Snapshot 'interactive-profile.json') -Raw|ConvertFrom-Json
$state=Get-Content (Join-Path $profile.profile 'state.json') -Raw|ConvertFrom-Json
$app=Get-Process CodexIslandPrototype|Where-Object {$_.Path -eq $profile.executable}|Select-Object -First 1
if(!$app){throw 'The intended preview is not running.'}
function Toggle {
 [HoverProbe]::keybd_event(17,0,0,[UIntPtr]::Zero);[HoverProbe]::keybd_event(18,0,0,[UIntPtr]::Zero)
 [HoverProbe]::keybd_event(73,0,0,[UIntPtr]::Zero);[HoverProbe]::keybd_event(73,0,2,[UIntPtr]::Zero)
 [HoverProbe]::keybd_event(18,0,2,[UIntPtr]::Zero);[HoverProbe]::keybd_event(17,0,2,[UIntPtr]::Zero)
 Start-Sleep -Milliseconds 800
}
if($FromPeek){
 if($state.state -eq 'Expanded'){Toggle}
 [HoverProbe]::Move([int]($state.screen.Width/2),80)
 Toggle
 $state=Get-Content (Join-Path $profile.profile 'state.json') -Raw|ConvertFrom-Json
}
$window=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$state.window)
function Elements {$window.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)}
$badge=Elements|Where-Object {$_.Current.Name -match '^\d+ Codex resets? available$'}|Select-Object -First 1
if(!$badge){throw 'The reset badge is unavailable.'}
$r=$badge.Current.BoundingRectangle
[HoverProbe]::SetForegroundWindow([IntPtr]$state.window)|Out-Null
if(!$FromPeek){[HoverProbe]::Move([int]($r.X-30),[int]($r.Y+60));Start-Sleep -Milliseconds 250}
[HoverProbe]::Move([int]($r.X+$r.Width/2),[int]($r.Y+$r.Height/2))
$measurements=@(foreach($delay in @(50,150,300,600)){
 Start-Sleep -Milliseconds $delay
 $point=New-Object HoverProbe+Point;[HoverProbe]::GetCursorPos([ref]$point)|Out-Null
 $owner=0;[HoverProbe]::GetWindowThreadProcessId([HoverProbe]::WindowFromPoint($point),[ref]$owner)|Out-Null
 [pscustomobject]@{delay=$delay;cursorX=$point.X;cursorY=$point.Y;insideBadge=$r.Contains($point.X,$point.Y);pointerOverPreview=($owner -eq $app.Id);rows=@(Elements|Where-Object {$_.Current.Name.StartsWith('Codex reset expires ')}).Count}
})
$report=[pscustomobject]@{build=$state.build;state=$state.state;fromPeek=[bool]$FromPeek;targetX=$r.X+$r.Width/2;targetY=$r.Y+$r.Height/2;measurements=$measurements}
$report|ConvertTo-Json -Depth 4|Set-Content (Join-Path $PSScriptRoot '..\artifacts\reset-hover-probe.json')
$report|ConvertTo-Json -Depth 4

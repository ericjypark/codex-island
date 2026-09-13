param([Parameter(Mandatory=$true)][string]$Snapshot,[switch]$Baseline)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Drawing,System.Windows.Forms
Add-Type @'
using System;using System.Runtime.InteropServices;
public static class TooltipPointer {
 [DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr window);
 [DllImport("user32.dll")]public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
 [DllImport("user32.dll")]public static extern int GetSystemMetrics(int metric);
 [DllImport("dwmapi.dll")]public static extern int DwmFlush();
 [DllImport("user32.dll")]public static extern void mouse_event(uint flags,uint x,uint y,uint data,UIntPtr extra);
 public static void Move(int x,int y){mouse_event(0x8001,(uint)(x*65535.0/(GetSystemMetrics(0)-1)),(uint)(y*65535.0/(GetSystemMetrics(1)-1)),0,UIntPtr.Zero);}
}
'@
[TooltipPointer]::SetThreadDpiAwarenessContext([IntPtr](-4))|Out-Null
$profile=Get-Content (Join-Path $Snapshot 'interactive-profile.json') -Raw|ConvertFrom-Json
$process=Get-Process CodexIslandPrototype|Where-Object {$_.Path -eq $profile.executable}|Select-Object -First 1
if(!$process){throw 'The intended preview is not running.'}
$owned=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ProcessIdProperty),$process.Id
function Windows {[Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,$owned)}
$settings=Windows|Where-Object {$_.Current.Name -eq 'CodexIsland Settings'}|Select-Object -First 1
if(!$settings){throw 'Open the preview settings before checking tooltips.'}
$output=Join-Path $PSScriptRoot ('..\artifacts\tooltip-confirmed\'+$(if($Baseline){'before'}else{'after'}))
New-Item -ItemType Directory -Force $output|Out-Null
$original=[Windows.Forms.Cursor]::Position
$results=@()
try {
 [TooltipPointer]::SetForegroundWindow([IntPtr]$settings.Current.NativeWindowHandle)|Out-Null
 $window=$settings.Current.BoundingRectangle
 foreach($name in @('Close','Zoom')) {
  [TooltipPointer]::Move([int]($window.X+300),[int]($window.Y+150));Start-Sleep -Milliseconds 350
  $button=$settings.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)|Where-Object {$_.Current.ControlType -eq [Windows.Automation.ControlType]::Button -and $_.Current.Name -eq $name}|Select-Object -First 1
  if(!$button){throw ('Missing caption button: '+$name)}
  $bounds=$button.Current.BoundingRectangle
  [TooltipPointer]::Move([int]($bounds.X+$bounds.Width/2),[int]($bounds.Y+$bounds.Height/2));Start-Sleep -Milliseconds 1100
  $condition=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ControlTypeProperty),([Windows.Automation.ControlType]::ToolTip)
  $tip=$null
  for($attempt=0;$attempt -lt 15 -and !$tip;$attempt++) {
   $tip=Windows|ForEach-Object {$_.FindFirst([Windows.Automation.TreeScope]::Subtree,$condition)}|Where-Object {$_}|Select-Object -First 1
   if(!$tip){Start-Sleep -Milliseconds 150}
  }
  if(!$tip){throw ('Hover did not show a tooltip for '+$name+'; cursor='+[Windows.Forms.Cursor]::Position+'; target='+$bounds)}
  Start-Sleep -Milliseconds 450
  [TooltipPointer]::DwmFlush()|Out-Null
  $tipBounds=$tip.Current.BoundingRectangle
  $bitmap=New-Object Drawing.Bitmap ([int]$tipBounds.Width),([int]$tipBounds.Height);$graphics=[Drawing.Graphics]::FromImage($bitmap)
  try {
   $graphics.CopyFromScreen([int]$tipBounds.X,[int]$tipBounds.Y,0,0,$bitmap.Size);$bitmap.Save((Join-Path $output ($name.ToLower()+'.png')))
   $dark=0;$light=0;$total=0
   for($y=3;$y -lt $bitmap.Height-3;$y++){for($x=3;$x -lt $bitmap.Width-3;$x++){$pixel=$bitmap.GetPixel($x,$y);if($pixel.R -lt 60 -and $pixel.G -lt 60 -and $pixel.B -lt 60){$dark++};if($pixel.R -gt 180 -and $pixel.G -gt 180 -and $pixel.B -gt 180){$light++};$total++}}
   $readable=$tip.Current.Name -eq $name -and $dark/$total -gt .65 -and $light -gt 12
   $results+=[pscustomobject]@{name=$name;tooltipName=$tip.Current.Name;darkFraction=$dark/$total;brightTextPixels=$light;readable=$readable}
  } finally {$graphics.Dispose();$bitmap.Dispose()}
  $context=New-Object Drawing.Bitmap 400,180;$graphics=[Drawing.Graphics]::FromImage($context)
  try {$graphics.CopyFromScreen([int]$window.X,[int]$window.Y,0,0,$context.Size);$context.Save((Join-Path $output ('context-'+$name.ToLower()+'.png')))}finally{$graphics.Dispose();$context.Dispose()}
 }
} finally {[TooltipPointer]::Move($original.X,$original.Y)}
@{build=$profile.build;baseline=[bool]$Baseline;checks=$results;verifiedAt=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $output 'results.json')
if(!$Baseline -and @($results|Where-Object {!$_.readable}).Count){throw 'A tooltip did not render readable text on a dark surface.'}
$results|Format-Table name,tooltipName,darkFraction,brightTextPixels,readable

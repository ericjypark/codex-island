$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ContextInput {
 [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr window,uint message,IntPtr w,IntPtr l);
 [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr window,int index);
 [DllImport("user32.dll")] public static extern int GetSystemMetrics(int metric);
 [DllImport("user32.dll")] public static extern void mouse_event(uint flags,uint x,uint y,uint data,UIntPtr extra);
 public static void Move(int x,int y){mouse_event(0x8001,(uint)(x*65535.0/(GetSystemMetrics(0)-1)),(uint)(y*65535.0/(GetSystemMetrics(1)-1)),0,UIntPtr.Zero);}
}
'@
[ContextInput]::SetThreadDpiAwarenessContext([IntPtr](-4))|Out-Null
$root=Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype'
$statePath=Join-Path $root 'state.json';$prefsPath=Join-Path $root 'preferences.json'
$artifacts=Join-Path $PSScriptRoot '..\artifacts'
$saved=[IO.File]::ReadAllText($prefsPath)
$results=[Collections.Generic.List[object]]::new()
function Wait-UI([int]$ms){$w=[Diagnostics.Stopwatch]::StartNew();while($w.ElapsedMilliseconds -lt $ms){[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 10}}
function State {
 for($i=0;$i -lt 15;$i++){try{return Get-Content $statePath -Raw|ConvertFrom-Json}catch{Start-Sleep -Milliseconds 5}}
 throw 'The running app did not provide readable state.'
}
function Check([string]$name,[bool]$pass){$results.Add([pscustomobject]@{check=$name;pass=$pass;state=(State)})}
function Stop-Preview {
 $running=Get-Process CodexIslandPrototype -ErrorAction SilentlyContinue
 if(!$running){return}
 [ContextInput]::PostMessage([IntPtr](State).window,16,[IntPtr]::Zero,[IntPtr]::Zero)|Out-Null
 foreach($process in $running){if(!$process.WaitForExit(5000)){throw 'The preview did not close cleanly.'}}
}
function Start-Preview {Start-Process (Join-Path $root 'app\CodexIslandPrototype.exe');Wait-UI 1600}
function Windowed {
 $form.WindowState='Normal';$form.FormBorderStyle='Sizable'
 $form.Bounds=New-Object Drawing.Rectangle ($cx-500),350,1000,650
 $form.Show();$form.Activate();Wait-UI 1000
}
function Fullscreen {
 $form.WindowState='Normal';$form.FormBorderStyle='None';$form.Bounds=$screen
 $form.Show();$form.Activate();Wait-UI 1000
}
function Capture([string]$name) {
 $bmp=New-Object Drawing.Bitmap 1100,120;$g=[Drawing.Graphics]::FromImage($bmp)
 $g.CopyFromScreen($cx-550,$screen.Top,0,0,$bmp.Size)
 $bmp.Save((Join-Path $artifacts "$name.png"))
 $pixel=$bmp.GetPixel(550,35);$g.Dispose();$bmp.Dispose();return $pixel
}
try {
 Stop-Preview
 $prefs=$saved|ConvertFrom-Json;$prefs.AlwaysShowUsage=$true;$prefs.LowPower=$false;$prefs.ReduceMotion=$false;$prefs.AlertsEnabled=$false
 $prefs|ConvertTo-Json|Set-Content $prefsPath
 Start-Preview
 $initial=State;$cx=[int]($initial.screen.X+$initial.screen.Width/2)
 $screen=New-Object Drawing.Rectangle $initial.screen.X,$initial.screen.Y,$initial.screen.Width,$initial.screen.Height
 $form=New-Object Windows.Forms.Form;$form.Text='CodexIsland full-screen verification';$form.StartPosition='Manual';$form.BackColor=[Drawing.Color]::FromArgb(35,69,103)
 Windowed
 [ContextInput]::Move($cx,900);Wait-UI 700
 Check 'Window context event hooks registered' ((State).contextHooksAvailable)
 Check 'Ordinary window leaves always-visible peek active' ((State).state -eq 'Peek' -and !(State).contextSuppressed -and (State).sweepActive)
 $form.WindowState='Maximized';Wait-UI 1000
 Check 'Maximized bordered window does not suppress the island' ((State).state -eq 'Peek' -and !(State).fullscreen)
 $visible=Capture 'context-maximized-windows'
 Check 'Always-visible island is present in the screen capture' ($visible.R -lt 10 -and $visible.G -lt 10 -and $visible.B -lt 10)
 Fullscreen
 Check 'Borderless full screen hides the island and stops its sweep' ((State).fullscreen -and (State).contextSuppressed -and (State).state -eq 'Hidden' -and !(State).sweepActive)
 Check 'Full-screen handling preserves the foreground application' ([ContextInput]::GetForegroundWindow() -eq $form.Handle)
 $style=[ContextInput]::GetWindowLong([IntPtr](State).window,-20)
 Check 'Suppressed overlay is nonactivating and click-through' (($style -band 0x20) -ne 0 -and ($style -band 0x08000000) -ne 0)
 $hidden=Capture 'context-fullscreen-windows'
 Check 'Screen capture contains full-screen content through the island position' ($hidden.R -eq 35 -and $hidden.G -eq 69 -and $hidden.B -eq 103)
 [ContextInput]::Move($cx,1);Wait-UI 900
 Check 'Top-edge dwell cannot reveal over a full-screen application' ((State).state -eq 'Hidden' -and !(State).sweepActive)
 [ContextInput]::Move($cx,900);Wait-UI 1200
 $cpuBefore=(Get-Process CodexIslandPrototype).TotalProcessorTime.TotalMilliseconds
 $watch=[Diagnostics.Stopwatch]::StartNew();Wait-UI 5000
 $cpu=(Get-Process CodexIslandPrototype).TotalProcessorTime.TotalMilliseconds-$cpuBefore
 $results.Add([pscustomobject]@{check='Full-screen suppressed CPU over five seconds';pass=($cpu -lt 50);cpuMilliseconds=$cpu;oneCorePercent=$cpu/$watch.Elapsed.TotalMilliseconds*100;state=(State)})
 Windowed
 Check 'Resizing the foreground window restores always-visible peek' ((State).state -eq 'Peek' -and !(State).contextSuppressed -and (State).sweepActive)
 Check 'Restoring peek does not activate the island' ([ContextInput]::GetForegroundWindow() -eq $form.Handle)
 Fullscreen;$form.WindowState='Minimized';Wait-UI 1000
 Check 'Minimizing full screen restores the island' (!(State).contextSuppressed -and (State).state -eq 'Peek')
 Fullscreen;$form.Hide();Wait-UI 1000
 Check 'Hiding full screen restores the island' (!(State).contextSuppressed -and (State).state -eq 'Peek')
 Stop-Preview
 $prefs.AlwaysShowUsage=$false;$prefs|ConvertTo-Json|Set-Content $prefsPath
 Fullscreen;Start-Preview
 Check 'Launching under full screen starts suppressed' ((State).contextSuppressed -and (State).state -eq 'Hidden' -and !(State).sweepActive)
 Windowed
 Check 'Ordinary hover mode returns to hidden rest when full screen ends' (!(State).contextSuppressed -and (State).state -eq 'Hidden')
 [ContextInput]::Move($cx,1);Wait-UI 900
 Check 'Hover works again after leaving full screen' ((State).state -eq 'Peek')
} finally {
 if($form){$form.Close();$form.Dispose()}
 Stop-Preview;[IO.File]::WriteAllText($prefsPath,$saved);Start-Preview
 $results|ConvertTo-Json -Depth 10|Set-Content (Join-Path $artifacts 'window-context-results.json')
 $results|Select-Object check,pass,cpuMilliseconds|Format-Table -AutoSize
}
if($results.Where({!$_.pass}).Count -gt 0){throw 'Window context checks failed.'}

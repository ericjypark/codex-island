$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Windows.Forms,System.Drawing
Add-Type @'
using System;using System.Runtime.InteropServices;
public static class DropdownInput {
 [DllImport("user32.dll")]public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
 [DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr window);
 [DllImport("user32.dll")]public static extern bool PostMessage(IntPtr window,uint message,IntPtr w,IntPtr l);
 [DllImport("user32.dll")]public static extern void keybd_event(byte key,byte scan,uint flags,UIntPtr extra);
 [DllImport("user32.dll")]public static extern void mouse_event(uint flags,uint x,uint y,uint data,UIntPtr extra);
 [DllImport("user32.dll")]public static extern int GetSystemMetrics(int index);
 public static void Move(int x,int y){mouse_event(0x8001,(uint)(x*65535.0/(GetSystemMetrics(0)-1)),(uint)(y*65535.0/(GetSystemMetrics(1)-1)),0,UIntPtr.Zero);}
}
'@
[DropdownInput]::SetThreadDpiAwarenessContext([IntPtr](-4))|Out-Null
$root=Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype'
$statePath=Join-Path $root 'state.json';$prefsPath=Join-Path $root 'preferences.json'
$executable=Join-Path $root 'app\CodexIslandPrototype.exe'
$artifacts=Join-Path $PSScriptRoot '..\artifacts'
$saved=[IO.File]::ReadAllText($prefsPath);$initial=Get-Content $statePath -Raw|ConvertFrom-Json
$startupKey=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Run')
$savedStartup=if($startupKey){$startupKey.GetValue('CodexIslandPrototype')}else{$null};if($startupKey){$startupKey.Dispose()}
$isolated=Join-Path ([IO.Path]::GetTempPath()) ('CodexIslandDropdownUI-'+[Guid]::NewGuid().ToString('N'))
$results=[Collections.Generic.List[object]]::new()
$euro='EUR  '+[char]0x20AC
$chinese=-join @([char]0x7B80,[char]0x4F53,[char]0x4E2D,[char]0x6587)
function WaitUI([int]$ms){$watch=[Diagnostics.Stopwatch]::StartNew();while($watch.ElapsedMilliseconds -lt $ms){[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 10}}
function State {Get-Content $statePath -Raw|ConvertFrom-Json}
function Preferences {Get-Content $prefsPath -Raw|ConvertFrom-Json}
function Key([byte]$key){[DropdownInput]::keybd_event($key,0,0,[UIntPtr]::Zero);[DropdownInput]::keybd_event($key,0,2,[UIntPtr]::Zero);WaitUI 180}
function Windows {
 $appProcess=Get-Process CodexIslandPrototype|Sort-Object StartTime -Descending|Select-Object -First 1
 $condition=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ProcessIdProperty),$appProcess.Id
 return [Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,$condition)
}
function All {foreach($window in (Windows)){$window;$window.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)}}
function Settings {Windows|Where-Object {$_.Current.Name -eq 'CodexIsland Settings'}|Select-Object -First 1}
function Control([string]$name){All|Where-Object {$_.Current.Name -eq $name -and $_.Current.ControlType -ne [Windows.Automation.ControlType]::Text}|Select-Object -First 1}
function Invoke([string]$name){$control=Control $name;if(!$control){throw "Missing control: $name"};$control.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke();WaitUI 250}
function MenuItems {All|Where-Object {$_.Current.ControlType -eq [Windows.Automation.ControlType]::MenuItem}}
function Check([string]$name,[bool]$pass){$results.Add([pscustomobject]@{check=$name;pass=$pass});Write-Output ((@('FAIL: ','PASS: '))[[int]$pass]+$name);if(!$pass){throw $name}}
function CloseApp {
 $running=@(Get-Process CodexIslandPrototype -ErrorAction SilentlyContinue);if(!$running.Count){return}
 [DropdownInput]::PostMessage([IntPtr](State).window,16,[IntPtr]::Zero,[IntPtr]::Zero)|Out-Null
 foreach($process in $running){if(!$process.WaitForExit(5000)){throw 'Application did not close gracefully.'}}
}
function StartApp([string]$arguments,[bool]$isolate=$true) {
 $start=New-Object Diagnostics.ProcessStartInfo;$start.FileName=$executable;$start.Arguments=$arguments;$start.UseShellExecute=$false
 $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 if($isolate){$start.EnvironmentVariables['CODEX_HOME']=Join-Path $isolated 'codex';$start.EnvironmentVariables['CLAUDE_CONFIG_DIR']=Join-Path $isolated 'claude';$start.EnvironmentVariables.Remove('CLAUDE_CODE_OAUTH_TOKEN')}
 $process=[Diagnostics.Process]::Start($start);$process.Dispose();WaitUI 1800
}
function CaptureMenu([string]$name) {
 $items=@(MenuItems);if(!$items.Count){throw 'No open menu to capture.'}
 $rects=@($items|ForEach-Object {$_.Current.BoundingRectangle})
 $left=[int](($rects|Measure-Object Left -Minimum).Minimum)-10;$top=[int](($rects|Measure-Object Top -Minimum).Minimum)-10
 $right=[int](($rects|Measure-Object Right -Maximum).Maximum)+10;$bottom=[int](($rects|Measure-Object Bottom -Maximum).Maximum)+10
 $bitmap=New-Object Drawing.Bitmap ($right-$left),($bottom-$top);$graphics=[Drawing.Graphics]::FromImage($bitmap)
 $graphics.CopyFromScreen($left,$top,0,0,$bitmap.Size);$bitmap.Save((Join-Path $artifacts ($name+'.png')));$graphics.Dispose()
 $bright=0;$samples=0
 foreach($rect in $rects){for($y=[int]$rect.Top+6;$y -lt [int]$rect.Bottom-6;$y++){for($x=[int]$rect.Left+4;$x -lt [int]$rect.Left+10;$x++){$pixel=$bitmap.GetPixel($x-$left,$y-$top);if([Math]::Max($pixel.R,[Math]::Max($pixel.G,$pixel.B)) -gt 100){$bright++};$samples++}}}
 $bitmap.Dispose();Check ($name+': menu gutters use the dark surface') ($bright -eq 0 -and $samples -gt 0)
}
function CaptureSettings([string]$name) {
 $rect=(Settings).Current.BoundingRectangle
 $bitmap=New-Object Drawing.Bitmap ([int]$rect.Width),([int]$rect.Height);$graphics=[Drawing.Graphics]::FromImage($bitmap)
 $graphics.CopyFromScreen([int]$rect.X,[int]$rect.Y,0,0,$bitmap.Size);$bitmap.Save((Join-Path $artifacts ($name+'.png')));$graphics.Dispose();$bitmap.Dispose()
}
try {
 CloseApp;[DropdownInput]::Move(500,850)
 $prefs=$saved|ConvertFrom-Json;$prefs.Language='en';$prefs.LeftProvider='claude';$prefs.RightProvider='codex';$prefs.Currency='USD';$prefs.SettingsTab='providers'
 $prefs|Add-Member -NotePropertyName LiveMode -NotePropertyValue $false -Force;$prefs|ConvertTo-Json|Set-Content $prefsPath
 StartApp '--demo --providers'
 Check 'Demo launch exposes a Connect accounts action' ($null -ne (Control 'Connect accounts') -and (State).sampleData)
 CaptureSettings 'providers-connect-windows'
 Invoke 'General';Invoke 'Language'
 $items=@(MenuItems);Check 'Language menu exposes all three native menu items' ($items.Count -eq 3 -and @($items|ForEach-Object {$_.Current.Name}).Contains($chinese))
 Check 'The current language remains checked' ((Control 'English').GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Current.ToggleState -eq [Windows.Automation.ToggleState]::On)
 CaptureMenu 'dropdown-language-windows'
 Key 27;Check 'Escape dismisses the menu without closing Settings' (@(MenuItems).Count -eq 0 -and $null -ne (Settings))
 $language=Control 'Language';$language.SetFocus();Key 40
 Check 'Down arrow opens a focused picker' (@(MenuItems).Count -eq 3)
 Key 27
 Invoke 'Providers';Invoke 'Display currency'
 Check 'Currency menu exposes all nine options' (@(MenuItems).Count -eq 9)
 CaptureMenu 'dropdown-currency-windows'
 (Control $euro).SetFocus();Key 13
 Check 'Keyboard selection persists currency and closes the menu' ((Preferences).Currency -eq 'EUR' -and @(MenuItems).Count -eq 0)
 Invoke 'Display currency';Check 'Reopened menu checks the saved currency' ((Control $euro).GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Current.ToggleState -eq [Windows.Automation.ToggleState]::On)
 Key 27
 Invoke 'Left provider';Check 'Provider picker uses the shared menu' (@(MenuItems).Count -eq 4)
 CaptureMenu 'dropdown-provider-windows'
 $w=Settings;$rect=$w.Current.BoundingRectangle;[DropdownInput]::Move([int]$rect.Left+120,[int]$rect.Top+190)
 [DropdownInput]::mouse_event(2,0,0,0,[UIntPtr]::Zero);[DropdownInput]::mouse_event(4,0,0,0,[UIntPtr]::Zero);WaitUI 250
 Check 'An outside click dismisses the menu without changing selection' (@(MenuItems).Count -eq 0 -and (Preferences).LeftProvider -eq 'claude')
 Invoke 'Connect accounts';WaitUI 2200
 Check 'Connect accounts restarts into live Providers settings' (!(State).sampleData -and (Preferences).LiveMode -and $null -ne (Settings) -and (State).preferences.SettingsTab -eq 'providers')
 Check 'Both selected accounts expose CLI sign-in actions' ($null -ne (Control 'Open Claude CLI') -and $null -ne (Control 'Open Codex CLI'))
 CaptureSettings 'providers-live-windows'
 Check 'Missing isolated credentials remain disconnected' (@((State).providerStatus|Where-Object {$_.status -eq 'NotConnected'}).Count -eq 2)
 CloseApp;StartApp '--providers'
 Check 'An ordinary launch remembers the live-data choice' (!(State).sampleData -and (Preferences).LiveMode)
 Invoke 'Preview demo';WaitUI 2200
 Check 'Preview demo restores sample mode without clearing accounts' ((State).sampleData -and !(Preferences).LiveMode -and $null -ne (Control 'Connect accounts'))
 [pscustomobject]@{build=(State).build;isolatedCredentials=$true;checks=$results}|ConvertTo-Json -Depth 6|Set-Content (Join-Path $artifacts 'dropdown-results.json')
}finally {
 CloseApp;[IO.File]::WriteAllText($prefsPath,$saved);[DropdownInput]::Move(500,850)
 if($null -ne $savedStartup){$key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Run',$true);try{$key.SetValue('CodexIslandPrototype',$savedStartup)}finally{$key.Dispose()}}
 $mode=if($initial.sampleData){'--demo'}else{'--live'};StartApp $mode $false
 if(Test-Path $isolated){Remove-Item $isolated -Recurse -Force}
}

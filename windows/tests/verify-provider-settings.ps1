param([Parameter(Mandatory=$true)][string]$Snapshot,[switch]$Before,[switch]$PreserveCurrentSpacing)
$ErrorActionPreference='Stop'
$profile=Get-Content (Join-Path $Snapshot 'interactive-profile.json') -Raw|ConvertFrom-Json
$output=Join-Path $PSScriptRoot '..\artifacts\provider-settings-confirmed'
New-Item -ItemType Directory -Force $output|Out-Null
$preferences=Join-Path $profile.profile 'preferences.json'
if($Before){Copy-Item $preferences (Join-Path $output 'preferences-before.json');'Saved the current preview preferences for comparison.';exit}
$state=Get-Content (Join-Path $profile.profile 'state.json') -Raw|ConvertFrom-Json
$process=Get-Process CodexIslandPrototype|Where-Object {$_.Path -eq $profile.executable}|Select-Object -First 1
if(!$process -or $state.build -ne $profile.build -or $state.sampleData){throw 'The intended live preview is not running.'}
$source=Get-ChildItem $profile.profile -Directory -Filter 'update-source-*'|Sort-Object LastWriteTime -Descending|Select-Object -First 1
$files=@('IslandVisual.cs','IslandAccessibility.cs','DollarGlowLayer.cs','UsageFeed.cs','MainWindow.xaml.cs','FrameDiagnostics.cs','PreviewSettings.cs','SettingsControls.cs','App.xaml')
$hashes=@();foreach($name in $files){
 $repo=(Get-FileHash (Join-Path $PSScriptRoot ('..\IslandPrototype\'+$name)) -Algorithm SHA256).Hash
 if($repo -ne (Get-FileHash (Join-Path $source.FullName $name) -Algorithm SHA256).Hash){throw ('Installed source differs: '+$name)}
 $hashes+=@{file=$name;sha256=$repo}
}
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Drawing,System.Windows.Forms
Add-Type @'
using System;using System.Runtime.InteropServices;
public static class SettingsVerifyInput {
 [DllImport("user32.dll")]public static extern void keybd_event(byte key,byte scan,uint flags,UIntPtr extra);
 [DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr window);
 [DllImport("user32.dll")]public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
 [DllImport("user32.dll")]public static extern int GetSystemMetrics(int metric);
 [DllImport("user32.dll")]public static extern void mouse_event(uint flags,uint x,uint y,uint data,UIntPtr extra);
 public static void Click(int x,int y){mouse_event(0x8001,(uint)(x*65535.0/(GetSystemMetrics(0)-1)),(uint)(y*65535.0/(GetSystemMetrics(1)-1)),0,UIntPtr.Zero);mouse_event(2,0,0,0,UIntPtr.Zero);mouse_event(4,0,0,0,UIntPtr.Zero);}
}
'@
[SettingsVerifyInput]::SetThreadDpiAwarenessContext([IntPtr](-4))|Out-Null
function Key([byte]$key){[SettingsVerifyInput]::keybd_event($key,0,0,[UIntPtr]::Zero);[SettingsVerifyInput]::keybd_event($key,0,2,[UIntPtr]::Zero)}
function Button($window,[string]$name){$window.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)|Where-Object {$_.Current.ControlType -eq [Windows.Automation.ControlType]::Button -and $_.Current.Name -eq $name}|Select-Object -First 1}
function Invoke($button){if(!$button){throw 'An expected settings control is unavailable.'};$button.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke();Start-Sleep -Milliseconds 350}
[SettingsVerifyInput]::SetForegroundWindow([IntPtr]$state.window)|Out-Null
[SettingsVerifyInput]::keybd_event(17,0,0,[UIntPtr]::Zero);Key 188;[SettingsVerifyInput]::keybd_event(17,0,2,[UIntPtr]::Zero)
Start-Sleep -Milliseconds 700
$owned=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ProcessIdProperty),$process.Id
$settings=[Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,$owned)|Where-Object {$_.Current.Name -eq 'CodexIsland Settings'}|Select-Object -First 1
if(!$settings){throw 'The updated settings window did not open.'}
$providers=Button $settings 'Providers';if(!$providers){throw 'The Providers tab is missing.'}
$tab=$providers.Current.BoundingRectangle
[SettingsVerifyInput]::Click([int]($tab.X+$tab.Width/2),[int]($tab.Y+$tab.Height/2));Start-Sleep -Milliseconds 350
[SettingsVerifyInput]::SetForegroundWindow([IntPtr]$settings.Current.NativeWindowHandle)|Out-Null;Start-Sleep -Milliseconds 700
$all=$settings.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)
$names=@($all|ForEach-Object {$_.Current.Name})
if('Accounts' -in $names -or 'Preview demo' -in $names -or 'Live usage' -in $names){throw 'The obsolete account layout is still present.'}
if(!(Button $settings 'Left provider') -or !(Button $settings 'Right provider')){throw 'The provider selectors are missing.'}
$bounds=$settings.Current.BoundingRectangle
$bitmap=New-Object Drawing.Bitmap ([int]$bounds.Width),([int]$bounds.Height);$graphics=[Drawing.Graphics]::FromImage($bitmap)
try{$graphics.CopyFromScreen([int]$bounds.X,[int]$bounds.Y,0,0,$bitmap.Size);$bitmap.Save((Join-Path $output 'installed-providers.png'))}finally{$graphics.Dispose();$bitmap.Dispose()}
$previousPreferences=Get-Content (Join-Path $output 'preferences-before.json') -Raw|ConvertFrom-Json
$currentPreferences=Get-Content $preferences -Raw|ConvertFrom-Json
$same=($previousPreferences|ConvertTo-Json -Depth 20 -Compress) -eq ($currentPreferences|ConvertTo-Json -Depth 20 -Compress)
$changes=@();foreach($property in $previousPreferences.PSObject.Properties){
 if(($property.Value|ConvertTo-Json -Depth 20 -Compress) -ne ($currentPreferences.($property.Name)|ConvertTo-Json -Depth 20 -Compress)){$changes+=@{name=$property.Name;before=$property.Value;after=$currentPreferences.($property.Name)}}
}
if(!$same -and !($PreserveCurrentSpacing -and $changes.Count -eq 1 -and $changes[0].name -eq 'Spacing')){throw 'Preferences differ from the pre-update snapshot; inspect before claiming preservation.'}
$binary=(Get-FileHash (Join-Path (Split-Path $profile.executable) 'CodexIslandPrototype.dll') -Algorithm SHA256).Hash
if($binary -ne (Get-FileHash (Join-Path $profile.profile 'staged-app\CodexIslandPrototype.dll') -Algorithm SHA256).Hash){throw 'The installed binary differs from the staged build.'}
@{build=$state.build;sourceHashes=$hashes;binarySha256=$binary;preferencesPreserved=$same;preferenceDifferences=$changes;currentPreferencesLeftUnchanged=$true;sampleData=$state.sampleData;verifiedAt=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 6|Set-Content (Join-Path $output 'installed-manifest.json')
'Verified the installed Providers page, source hashes, binary, and live profile. Current preferences were left unchanged.'

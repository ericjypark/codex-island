$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing,UIAutomationClient,UIAutomationTypes
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class LiveInput {
 [DllImport("user32.dll")] public static extern int GetSystemMetrics(int metric);
 public static void Move(int x,int y) {mouse_event(0x8001,(uint)(x*65535.0/(GetSystemMetrics(0)-1)),(uint)(y*65535.0/(GetSystemMetrics(1)-1)),0,UIntPtr.Zero);}
 [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr window,uint message,IntPtr w,IntPtr l);
 [DllImport("user32.dll")] public static extern void mouse_event(uint flags,uint x,uint y,uint data,UIntPtr extra);
 [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr window);
 [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr window,IntPtr dc);
 [DllImport("gdi32.dll",SetLastError=true)] private static extern bool BitBlt(IntPtr destination,int x,int y,int width,int height,IntPtr source,int sourceX,int sourceY,uint operation);
 public static void Capture(System.Drawing.Bitmap bitmap,int x,int y) {
  using(var graphics=System.Drawing.Graphics.FromImage(bitmap)) {
   IntPtr source=GetDC(IntPtr.Zero),destination=graphics.GetHdc();
   try{if(!BitBlt(destination,0,0,bitmap.Width,bitmap.Height,source,x,y,0x40CC0020))throw new System.ComponentModel.Win32Exception();}
   finally{graphics.ReleaseHdc(destination);ReleaseDC(IntPtr.Zero,source);}
  }
 }
}
'@ -ReferencedAssemblies System.Drawing
[LiveInput]::SetThreadDpiAwarenessContext([IntPtr](-4))|Out-Null
$root=Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype'
$statePath=Join-Path $root 'state.json'
$prefsPath=Join-Path $root 'preferences.json'
$artifacts=Join-Path $PSScriptRoot '..\artifacts'
$saved=[IO.File]::ReadAllText($prefsPath)
$initial=Get-Content $statePath -Raw|ConvertFrom-Json
$isolated=Join-Path ([IO.Path]::GetTempPath()) ('CodexIslandLiveUI-'+[Guid]::NewGuid().ToString('N'))
$results=[Collections.Generic.List[object]]::new()
function Wait-UI([int]$ms) {
 $watch=[Diagnostics.Stopwatch]::StartNew()
 while($watch.ElapsedMilliseconds -lt $ms){[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 10}
}
function State {Get-Content $statePath -Raw|ConvertFrom-Json}
function Stop-Preview {
 $running=Get-Process CodexIslandPrototype -ErrorAction SilentlyContinue
 if(!$running){return}
 [LiveInput]::PostMessage([IntPtr](State).window,16,[IntPtr]::Zero,[IntPtr]::Zero)|Out-Null
 foreach($process in $running){if(!$process.WaitForExit(5000)){throw 'The preview did not close cleanly.'}}
}
function Start-Preview([bool]$live,[bool]$isolate) {
 if(!$isolate){
  if($live){Start-Process (Join-Path $root 'app\CodexIslandPrototype.exe') -ArgumentList '--live'}else{Start-Process (Join-Path $root 'app\CodexIslandPrototype.exe') -ArgumentList '--demo'}
  Wait-UI 1600;return
 }
 $start=New-Object Diagnostics.ProcessStartInfo
 $start.FileName=Join-Path $root 'app\CodexIslandPrototype.exe';$start.UseShellExecute=$false
 $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 if($live){$start.Arguments='--live'}
 if($isolate){
  $start.EnvironmentVariables['CODEX_HOME']=Join-Path $isolated 'codex'
  $start.EnvironmentVariables['CLAUDE_CONFIG_DIR']=Join-Path $isolated 'claude'
  $start.EnvironmentVariables.Remove('CLAUDE_CODE_OAUTH_TOKEN')
 }
 [Diagnostics.Process]::Start($start)|Out-Null;Wait-UI 1600
}
function Check([string]$name,[bool]$pass){$results.Add([pscustomobject]@{check=$name;pass=$pass})}
function Find-Control($window,[string]$name) {
 $condition=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::NameProperty),$name
 $control=$window.FindAll([Windows.Automation.TreeScope]::Descendants,$condition)|Where-Object {$_.Current.ControlType -ne [Windows.Automation.ControlType]::Text}|Select-Object -First 1
 if(!$control){throw "Missing control: $name"};return $control
}
function Invoke($window,[string]$name){(Find-Control $window $name).GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke();Wait-UI 300}
function Cursor([int]$x,[int]$y){[LiveInput]::Move($x,$y);Wait-UI 60}
function Expand {
 Cursor $cx 800;Wait-UI 500;Cursor $cx 1;Wait-UI 750
 [LiveInput]::mouse_event(2,0,0,0,[UIntPtr]::Zero);[LiveInput]::mouse_event(4,0,0,0,[UIntPtr]::Zero);Wait-UI 850
 if((State).state -ne 'Expanded'){throw 'Hover and click did not expand the panel.'}
}
function Island {return [Windows.Automation.AutomationElement]::FromHandle([IntPtr](State).window)}
function Description {
 $all=(Island).FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)
 return ($all|Where-Object {$_.Current.Name.StartsWith('CodexIsland ')}|Select-Object -First 1).Current.Name
}
function Capture([string]$name,[int]$height=452) {
 $bitmap=New-Object Drawing.Bitmap 1600,$height
 [LiveInput]::Capture($bitmap,($cx-800),0);$bitmap.Save((Join-Path $artifacts "$name.png"))
 foreach($x in @(48,1512)){
  $lit=0;for($y=18;$y -lt 58;$y++){for($px=$x;$px -lt ($x+40);$px++){if($bitmap.GetPixel($px,$y).GetBrightness() -gt 0.1){$lit++}}}
  Check ($name+': provider logo at '+$x+' is visible') ($lit -gt 80)
 }
 $bitmap.Dispose()
}
function Settings {
 $condition=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ProcessIdProperty),(Get-Process CodexIslandPrototype).Id
 return [Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,$condition)|Where-Object {$_.Current.Name -eq 'CodexIsland Settings'}|Select-Object -First 1
}
try {
 Stop-Preview
 Cursor 500 850
 $prefs=$saved|ConvertFrom-Json
 $prefs.LeftProvider='claude';$prefs.RightProvider='codex';$prefs.SettingsTab='general';$prefs.Language='en'
 $prefs.AlwaysShowUsage=$false;$prefs.Page=0;$prefs.HasNavigated=$true;$prefs.LowPower=$false
 $prefs|ConvertTo-Json|Set-Content $prefsPath
 Start-Preview $true $true
 $state=State;$cx=[int]($state.screen.X+$state.screen.Width/2)
 if($state.scale -ne 2){throw 'Live UI capture requires 200 percent display scaling.'}
 Check 'Live mode is explicit and starts hidden' (!$state.sampleData -and $state.state -eq 'Hidden' -and !$state.usageLoading)
 Check 'Missing CLI credentials report disconnected for both selected providers' (@($state.providerStatus|Where-Object {$_.status -eq 'NotConnected'}).Count -eq 2)
 Expand;Capture 'live-installed-disconnected-windows'
 $description=Description
 Check 'Installed usage view exposes login prompts without demo values' ($description.Contains('Not connected. Sign in to see your usage.') -and $description.Contains('Codex') -and $description.Contains('Claude') -and !$description.Contains('%') -and !$description.Contains('Demo'))
 Invoke (Island) 'Claude provider settings';Cursor $cx 850;Wait-UI 500
 $settings=Settings
 Check 'The inline connection action opens Providers settings' ($null -ne $settings -and (State).preferences.SettingsTab -eq 'providers')
 $names=$settings.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)|ForEach-Object {$_.Current.Name}
 Check 'Provider settings offer both account actions without a website fallback' (($names.Contains('Install Claude Code') -or $names.Contains('Sign in with Claude')) -and ($names.Contains('Install Codex') -or $names.Contains('Sign in with ChatGPT')) -and !$names.Contains('Open Codex CLI') -and $names.Contains('Accounts') -and !$names.Contains('MAX') -and !$names.Contains('PRO'))
 $rect=$settings.Current.BoundingRectangle
 $bitmap=New-Object Drawing.Bitmap ([int]$rect.Width),([int]$rect.Height);$graphics=[Drawing.Graphics]::FromImage($bitmap)
 $graphics.CopyFromScreen([int]$rect.X,[int]$rect.Y,0,0,$bitmap.Size);$bitmap.Save((Join-Path $artifacts 'live-installed-settings-windows.png'));$graphics.Dispose();$bitmap.Dispose()
 Invoke $settings 'Refresh usage';Wait-UI 400
 Check 'Refresh completes with missing credentials and preserves Providers settings' (!(State).usageLoading -and (State).preferences.SettingsTab -eq 'providers' -and @((State).providerStatus|Where-Object {$_.status -eq 'NotConnected'}).Count -eq 2)
 Invoke $settings 'Close';Expand
 Invoke (Island) 'Cost (Ctrl+2)';Wait-UI 600;Capture 'live-installed-cost-windows'
 Check 'Installed Cost view cannot render fixture money' ((Description).Contains('Usage history unavailable') -and !(Description).Contains('$') -and (State).page -eq 1)
 Invoke (Island) 'Overview (Ctrl+3)';Wait-UI 650;Capture 'live-installed-overview-windows' 554
 Check 'Installed Overview cannot render a fixture calendar' ((Description).Contains('Usage history unavailable') -and (State).page -eq 2)
 $names=(Island).FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)|ForEach-Object {$_.Current.Name}
 Check 'Live Overview has no demo card export action' (!$names.Contains('Create your usage card'))
 [pscustomobject]@{build=(State).build;isolatedMissingCredentials=$true;checks=$results}|ConvertTo-Json -Depth 6|Set-Content (Join-Path $artifacts 'live-ui-results.json')
 $results|ConvertTo-Json
} finally {
 Stop-Preview
 [IO.File]::WriteAllText($prefsPath,$saved)
 Start-Preview (!$initial.sampleData) $false
 if(Test-Path $isolated){Remove-Item $isolated -Recurse -Force}
}
if($results.Where({!$_.pass}).Count -gt 0){throw 'Live UI checks failed.'}

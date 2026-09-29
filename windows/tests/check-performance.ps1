param([string]$OutputName='performance-results.json')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @'
using System;using System.Runtime.InteropServices;
public static class PerfInput {
 [DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")]public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr h);
 [DllImport("user32.dll")]public static extern int GetSystemMetrics(int n);
 [DllImport("user32.dll")]public static extern void mouse_event(uint flags,uint x,uint y,uint data,UIntPtr extra);
 [DllImport("user32.dll")]public static extern void keybd_event(byte key,byte scan,uint flags,UIntPtr extra);
 [DllImport("user32.dll")]public static extern IntPtr SendMessageTimeout(IntPtr h,uint msg,UIntPtr w,IntPtr l,uint flags,uint timeout,out UIntPtr result);
 [DllImport("user32.dll")]public static extern uint GetGuiResources(IntPtr process,uint flags);
 public static void Move(int x,int y){mouse_event(0x8001,(uint)(x*65535.0/(GetSystemMetrics(0)-1)),(uint)(y*65535.0/(GetSystemMetrics(1)-1)),0,UIntPtr.Zero);}
 public static double Respond(IntPtr h){UIntPtr result;var watch=System.Diagnostics.Stopwatch.StartNew();var ok=SendMessageTimeout(h,0,UIntPtr.Zero,IntPtr.Zero,2,1000,out result);return ok==IntPtr.Zero?1000:watch.Elapsed.TotalMilliseconds;}
}
'@
[PerfInput]::SetThreadDpiAwarenessContext([IntPtr](-4))|Out-Null
$root=Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype'
$statePath=Join-Path $root 'state.json'
$artifact=Join-Path (Join-Path $PSScriptRoot '..\artifacts') $OutputName
$results=[Collections.Generic.List[object]]::new()
function WaitUI([int]$ms){$w=[Diagnostics.Stopwatch]::StartNew();while($w.ElapsedMilliseconds -lt $ms){[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 10}}
function ReadState {
 for($i=0;$i -lt 15;$i++){try{return Get-Content $statePath -Raw|ConvertFrom-Json}catch{Start-Sleep -Milliseconds 5}}
 throw 'The running app did not provide readable state.'
}
$initial=ReadState
$pidApp=(Get-Process CodexIslandPrototype|Select-Object -First 1).Id
$handle=[IntPtr]$initial.window
$cx=[int]($initial.screen.Width/2)
$scale=$initial.scale
$processCondition=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ProcessIdProperty),$pidApp
function Key([byte]$key){[PerfInput]::keybd_event($key,0,0,[UIntPtr]::Zero);[PerfInput]::keybd_event($key,0,2,[UIntPtr]::Zero)}
function Chord([byte]$key){[PerfInput]::keybd_event(17,0,0,[UIntPtr]::Zero);Key $key;[PerfInput]::keybd_event(17,0,2,[UIntPtr]::Zero)}
function Expand {
 if((ReadState).state -ne 'Expanded'){
  [PerfInput]::keybd_event(17,0,0,[UIntPtr]::Zero);[PerfInput]::keybd_event(18,0,0,[UIntPtr]::Zero);Key 73;[PerfInput]::keybd_event(18,0,2,[UIntPtr]::Zero);[PerfInput]::keybd_event(17,0,2,[UIntPtr]::Zero)
 }
 [PerfInput]::Move($cx,[int](50*$scale));[PerfInput]::SetForegroundWindow($handle)|Out-Null
 WaitUI 750
 if((ReadState).state -ne 'Expanded'){throw 'Could not open the panel.'}
}
function Page([int]$page){Chord ([byte](49+$page));WaitUI 550;if((ReadState).page -ne $page){throw 'The keyboard page action was not processed.'}}
function Window([string]$name){return ([Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,$processCondition)|Where-Object {$_.Current.Name -eq $name}|Select-Object -First 1)}
function Find([Windows.Automation.AutomationElement]$parent,[string]$name){$c=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::NameProperty),$name;return ($parent.FindAll([Windows.Automation.TreeScope]::Descendants,$c)|Where-Object {$_.Current.ControlType -ne [Windows.Automation.ControlType]::Text}|Select-Object -First 1)}
function Preferences([bool]$always,[bool]$lowPower){
 Expand;Chord 188;WaitUI 500
 $w=Window 'CodexIsland Settings';if(!$w){throw 'Settings did not open for the performance scenario.'}
 (Find $w 'General').GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke();WaitUI 180
 $current=ReadState
 if($current.preferences.AlwaysShowUsage -ne $always){(Find $w 'Always show usage').GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Toggle();WaitUI 180}
 if((ReadState).preferences.LowPower -ne $lowPower){(Find $w 'Low Power Mode').GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Toggle();WaitUI 180}
 $w.GetCurrentPattern([Windows.Automation.WindowPattern]::Pattern).Close();WaitUI 300
}
function Snapshot {
 $p=Get-Process -Id $pidApp
 return [pscustomobject]@{cpuMs=$p.TotalProcessorTime.TotalMilliseconds;privateMB=$p.PrivateMemorySize64/1MB;workingMB=$p.WorkingSet64/1MB;handles=$p.HandleCount;gdi=[PerfInput]::GetGuiResources($p.Handle,0);user=[PerfInput]::GetGuiResources($p.Handle,1)}
}
function Save {$results|ConvertTo-Json -Depth 6|Set-Content $artifact}
function Idle([string]$name,[string]$expected){
 WaitUI 1500
 $state=ReadState;if($state.state -ne $expected){throw "$name expected $expected, observed $($state.state)"}
 $a=Snapshot;$watch=[Diagnostics.Stopwatch]::StartNew();WaitUI 6000;$b=Snapshot
 $results.Add([pscustomobject]@{scenario=$name;build=$state.build;state=$state.state;page=$state.page;lowPower=$state.effectiveLowPower;elapsedMs=$watch.Elapsed.TotalMilliseconds;cpuOneCorePercent=($b.cpuMs-$a.cpuMs)/$watch.Elapsed.TotalMilliseconds*100;start=$a;end=$b});Save
}
$form=New-Object Windows.Forms.Form
$form.Text='CodexIsland performance check';$form.StartPosition='Manual';$form.Left=$cx-400;$form.Top=700;$form.Width=800;$form.Height=200
try {
 $form.Show();$form.Activate();WaitUI 300
 Preferences $false $false
 [PerfInput]::Move($cx,800);$form.Activate();Idle 'hidden' 'Hidden'
 [PerfInput]::Move($cx,1);WaitUI 650;Idle 'peek-hover' 'Peek'
 Expand;Page 0;Idle 'usage-settled' 'Expanded'
 Page 1;Idle 'cost-settled' 'Expanded'
 Page 2;Idle 'overview-settled' 'Expanded'
 Preferences $true $false
 [PerfInput]::Move($cx,800);$form.Activate();Idle 'always-visible-rest' 'Peek'
 Preferences $true $true
 [PerfInput]::Move($cx,800);$form.Activate();Idle 'low-power-rest' 'Peek'
 Preferences $false $false;Expand
 $overall=[Diagnostics.Stopwatch]::StartNew()
 for($block=0;$block -lt 6;$block++){
  $a=Snapshot;$latencies=[Collections.Generic.List[double]]::new();$watch=[Diagnostics.Stopwatch]::StartNew()
  for($i=0;$i -lt 9;$i++){
   $page=$i%3;Chord ([byte](49+$page))
   for($j=0;$j -lt 9;$j++){WaitUI 20;$latencies.Add([PerfInput]::Respond($handle))}
  }
  $b=Snapshot;$sorted=@($latencies|Sort-Object)
  $results.Add([pscustomobject]@{scenario='page-stress';block=$block;build=(ReadState).build;elapsedMs=$watch.Elapsed.TotalMilliseconds;cpuOneCorePercent=($b.cpuMs-$a.cpuMs)/$watch.Elapsed.TotalMilliseconds*100;responseP95ms=$sorted[[int](($sorted.Count-1)*.95)];responseMaxMs=$sorted[-1];start=$a;end=$b});Save
 }
 Key 27;[PerfInput]::Move($cx,800);$form.Activate();Idle 'hidden-after-stress' 'Hidden'
} finally {
 try {
  Preferences ([bool]$initial.preferences.AlwaysShowUsage) ([bool]$initial.preferences.LowPower)
  Expand;Page ([int]$initial.page);Key 27
 } catch {Write-Warning "Could not restore the original performance preferences: $_"}
 $form.Close();$form.Dispose();[PerfInput]::Move($cx,800)
}
$results|ConvertTo-Json -Depth 6

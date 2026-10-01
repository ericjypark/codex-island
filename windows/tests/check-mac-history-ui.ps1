param([Parameter(Mandatory=$true)][string]$Snapshot,[ValidateSet('inspect','overview','dialogs','retry-backup','backup','import','finish','card')][string]$Action='inspect')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Drawing,System.Windows.Forms
Add-Type @'
using System;using System.Runtime.InteropServices;
public static class HistoryInput {
 [DllImport("user32.dll")]public static extern void keybd_event(byte key,byte scan,uint flags,UIntPtr extra);
 [DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr window);
 [DllImport("user32.dll")]public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
 [DllImport("user32.dll")]public static extern int GetSystemMetrics(int metric);
 [DllImport("user32.dll")]public static extern void mouse_event(uint flags,uint x,uint y,uint data,UIntPtr extra);
 public static void Move(int x,int y){mouse_event(0x8001,(uint)(x*65535.0/(GetSystemMetrics(0)-1)),(uint)(y*65535.0/(GetSystemMetrics(1)-1)),0,UIntPtr.Zero);}
}
'@
[HistoryInput]::SetThreadDpiAwarenessContext([IntPtr](-4))|Out-Null
$profile=Get-Content (Join-Path $Snapshot 'interactive-profile.json') -Raw|ConvertFrom-Json
$statePath=Join-Path $profile.profile 'state.json'
$backupPath=Join-Path $profile.profile ('settings-backup-'+$profile.build.Substring(0,8)+'.sqlite3')
$appProcess=Get-Process CodexIslandPrototype|Where-Object {$_.Path -eq $profile.executable}|Select-Object -First 1
if(!$appProcess){throw 'The isolated history preview is not running.'}
$owned=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ProcessIdProperty),$appProcess.Id
function State {Get-Content $statePath -Raw|ConvertFrom-Json}
function AppWindows {
 $condition=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ControlTypeProperty),([Windows.Automation.ControlType]::Window)
 foreach($rootWindow in [Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,$owned)){
  $rootWindow
  $rootWindow.FindAll([Windows.Automation.TreeScope]::Descendants,$condition)
 }
}
function Window([string]$title){AppWindows|Where-Object {$_.Current.Name -eq $title}|Select-Object -First 1}
function Elements($window){$window.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)}
function Button($window,[string]$name){Elements $window|Where-Object {($_.Current.Name -eq $name -or $name -in @('Import','Back up') -and $_.Current.Name.StartsWith($name)) -and $_.Current.ControlType -eq [Windows.Automation.ControlType]::Button}|Select-Object -First 1}
function Invoke($button){if(!$button){throw 'Expected button is unavailable.'};$button.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke();Start-Sleep -Milliseconds 350}
function Key([byte]$key){[HistoryInput]::keybd_event($key,0,0,[UIntPtr]::Zero);[HistoryInput]::keybd_event($key,0,2,[UIntPtr]::Zero)}
function Chord([byte]$key){[HistoryInput]::keybd_event(17,0,0,[UIntPtr]::Zero);Key $key;[HistoryInput]::keybd_event(17,0,2,[UIntPtr]::Zero);Start-Sleep -Milliseconds 600}
function EnterFileName($dialog,[string]$path){
 $edit=Elements $dialog|Where-Object {$_.Current.ControlType -eq [Windows.Automation.ControlType]::Edit -and $_.Current.Name -eq 'File name:'}|Select-Object -First 1
 if(!$edit){throw 'The file-name editor is unavailable.'}
 [HistoryInput]::SetForegroundWindow([IntPtr]$dialog.Current.NativeWindowHandle)|Out-Null
 $edit.SetFocus();Chord 65
 $keys=($path.ToCharArray()|ForEach-Object {if($_ -in @('{','}','+','^','%','~','(',')','[',']')){'{'+$_+'}'}else{[string]$_}}) -join ''
 [Windows.Forms.SendKeys]::SendWait($keys);Start-Sleep -Milliseconds 250
 if($edit.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).Current.Value -ne $path){throw 'The file picker did not accept the requested filename.'}
 $edit.SetFocus();Start-Sleep -Milliseconds 150
}
function Capture($window,[string]$name){
 [HistoryInput]::SetForegroundWindow([IntPtr]$window.Current.NativeWindowHandle)|Out-Null;Start-Sleep -Milliseconds 350
 $bounds=$window.Current.BoundingRectangle
 if($window.Current.Name -eq 'CodexIsland'){
  $surface=Elements $window|Where-Object {$_.Current.ClassName -eq 'CodexIsland'}|Select-Object -First 1
  if(!$surface){throw 'The island capture bounds are unavailable.'}
  $bounds=$surface.Current.BoundingRectangle
 }
 $bitmap=New-Object Drawing.Bitmap ([int]$bounds.Width),([int]$bounds.Height)
 $graphics=[Drawing.Graphics]::FromImage($bitmap)
 try{$graphics.CopyFromScreen([int]$bounds.X,[int]$bounds.Y,0,0,$bitmap.Size);$bitmap.Save((Join-Path $profile.verifiedOutput ($name+'.png')))}finally{$graphics.Dispose();$bitmap.Dispose()}
}
function Expand {
 $state=State;[HistoryInput]::Move([int]($state.screen.Width/2),80)
 if($state.state -ne 'Expanded'){
  [HistoryInput]::keybd_event(17,0,0,[UIntPtr]::Zero);[HistoryInput]::keybd_event(18,0,0,[UIntPtr]::Zero);Key 73
  [HistoryInput]::keybd_event(18,0,2,[UIntPtr]::Zero);[HistoryInput]::keybd_event(17,0,2,[UIntPtr]::Zero);Start-Sleep -Milliseconds 800
 }
 [HistoryInput]::SetForegroundWindow([IntPtr](State).window)|Out-Null
}
if($Action -eq 'inspect'){
 Expand;Chord 51
 $panel=[Windows.Automation.AutomationElement]::FromHandle([IntPtr](State).window)
 $summary=Elements $panel|Where-Object {$_.Current.ClassName -eq 'CodexIsland'}|Select-Object -First 1
 if(!$summary -or !$summary.Current.Name.Contains('14,061,868,359 tokens')){throw 'The interactive calendar does not match the imported year total.'}
 Capture $panel 'interactive-history-overview'
 Invoke (Button $panel 'Settings')
 $settings=Window 'CodexIsland Settings';Invoke (Button $settings 'General');Capture $settings 'interactive-history-settings'
 if(!(Button $settings 'Import').Current.IsEnabled -or !(Button $settings 'Back up').Current.IsEnabled){throw 'History actions are unavailable.'}
 Invoke (Button $settings 'Back up')
}
elseif($Action -eq 'backup'){
 $dialog=Window 'Back up usage history';if(!$dialog){throw 'The backup picker is not open.'}
 $destination=$backupPath
 if(Test-Path $destination){throw 'The UI backup destination already exists and has been preserved.'}
 EnterFileName $dialog $destination
 Invoke (Button $dialog 'Save')
 $deadline=(Get-Date).AddSeconds(15)
 do{Start-Sleep -Milliseconds 250}while(!(Test-Path $destination) -and (Get-Date) -lt $deadline)
 if(!(Test-Path $destination)){throw 'The UI backup was not saved.'}
}
elseif($Action -eq 'retry-backup'){
 $dialog=Window 'Import usage history';if($dialog){Invoke (Button $dialog 'Cancel')}
 $settings=Window 'CodexIsland Settings';Invoke (Button $settings 'Back up')
}
elseif($Action -eq 'import'){
 $notice=Window 'Usage history';if($notice){Invoke (Button $notice 'OK')}
 $settings=Window 'CodexIsland Settings';Invoke (Button $settings 'Import')
}
elseif($Action -eq 'finish'){
 $dialog=Window 'Import usage history';if(!$dialog){throw 'The import picker is not open.'}
 EnterFileName $dialog $backupPath
 Key 13
 $deadline=(Get-Date).AddSeconds(20)
 do {Start-Sleep -Milliseconds 250;$notice=Window 'Usage history imported'}while(!$notice -and (Get-Date) -lt $deadline)
 if(!$notice){throw 'The UI import did not report completion.'}
 $message=@(Elements $notice|Where-Object {$_.Current.ControlType -eq [Windows.Automation.ControlType]::Text}|ForEach-Object {$_.Current.Name}) -join ' '
 if(!$message.Contains('Imported 0 usage records and 0 recovered daily totals.')){throw 'The repeated UI import did not preserve the expected counts.'}
 Capture $notice 'interactive-history-import-result'
 [HistoryInput]::SetForegroundWindow([IntPtr]$notice.Current.NativeWindowHandle)|Out-Null;Key 13;Start-Sleep -Milliseconds 350
 $settings=Window 'CodexIsland Settings';$settings.GetCurrentPattern([Windows.Automation.WindowPattern]::Pattern).Close();Start-Sleep -Milliseconds 350
 Expand;Chord 51
 $panel=[Windows.Automation.AutomationElement]::FromHandle([IntPtr](State).window)
 $summary=Elements $panel|Where-Object {$_.Current.ClassName -eq 'CodexIsland'}|Select-Object -First 1
 if(!$summary.Current.Name.Contains('14,061,868,359 tokens')){throw 'Calendar totals changed after UI import.'}
 Capture $panel 'interactive-history-overview'
 @{build=(State).build;backupSaved=$true;repeatImportRecords=0;repeatImportRecoveredDays=0;yearTokens=14061868359;sampleData=(State).sampleData;normalProfileSeparate=$true}|ConvertTo-Json|Set-Content (Join-Path $profile.verifiedOutput 'interactive-history-ui-results.json')
}
elseif($Action -eq 'card'){
 Expand;Chord 51
 $panel=[Windows.Automation.AutomationElement]::FromHandle([IntPtr](State).window)
 Invoke (Button $panel 'Create your usage card')
 $card=Window 'Usage card';if(!$card){throw 'The card studio did not open.'}
 Invoke (Button $card 'Period')
 $allTime=AppWindows|ForEach-Object {Elements $_}|Where-Object {$_.Current.ControlType -eq [Windows.Automation.ControlType]::MenuItem -and $_.Current.Name -eq 'All time'}|Select-Object -First 1
 Invoke $allTime
 if((Button $card 'Period').Current.HelpText -ne 'All time'){throw 'The all-time card period was not selected.'}
 Capture $card 'interactive-history-card-studio'
}
elseif($Action -eq 'overview'){
 $card=Window 'Usage card';if($card){$card.GetCurrentPattern([Windows.Automation.WindowPattern]::Pattern).Close();Start-Sleep -Milliseconds 300}
 Expand;Chord 51
 $panel=[Windows.Automation.AutomationElement]::FromHandle([IntPtr](State).window)
 $summary=Elements $panel|Where-Object {$_.Current.ClassName -eq 'CodexIsland'}|Select-Object -First 1
 if(!$summary -or !$summary.Current.Name.Contains('14,061,868,359 tokens')){throw 'The interactive calendar does not match the imported year total.'}
 Capture $panel 'interactive-history-overview'
 @{build=(State).build;yearTokens=14061868359;sampleData=(State).sampleData;verifiedAt=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content (Join-Path $profile.verifiedOutput 'interactive-overview-results.json')
 Write-Output ('Verified the imported calendar total on build '+(State).build)
}
$current=AppWindows
foreach($window in $current){
 if($Action -eq 'dialogs' -or $window.Current.Name -in @('Back up usage history','Import usage history','Usage history','Usage history imported','Usage card')){
  [pscustomobject]@{window=$window.Current.Name;controls=@(Elements $window|Where-Object {$_.Current.AutomationId -eq '1001' -or $_.Current.Name -in @('Save','Open','Cancel','OK') -or $_.Current.Name.StartsWith('Imported ') -or $_.Current.Name.StartsWith('Your usage history backup') -or $window.Current.Name -eq 'Usage history' -and $_.Current.ControlType -eq [Windows.Automation.ControlType]::Text}|ForEach-Object {[pscustomobject]@{name=$_.Current.Name;id=$_.Current.AutomationId;type=$_.Current.ControlType.ProgrammaticName}})}|ConvertTo-Json -Depth 5
 }
}
if($Action -eq 'finish'){'Interactive history backup, repeated import, and exact calendar totals verified.'}
if($Action -eq 'dialogs'){Get-ChildItem $profile.profile -File|Where-Object {$_.Name -like '*backup*' -or $_.Name -like '*before-import*'}|Select-Object Name,Length|ConvertTo-Json}
if($Action -eq 'dialogs'){
 foreach($title in @('Import usage history','Back up usage history')){
  $dialog=Window $title;if($dialog){Capture $dialog 'history-dialog-probe';Elements $dialog|Where-Object {$_.Current.ControlType -eq [Windows.Automation.ControlType]::Edit}|ForEach-Object {[pscustomobject]@{name=$_.Current.Name;id=$_.Current.AutomationId;class=$_.Current.ClassName}}|ConvertTo-Json}
 }
}

param([ValidateSet('inspect','claude','grok','antigravity')][string]$Install='inspect')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Drawing
$process=Get-Process CodexIslandPrototype|Select-Object -First 1
$condition=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ProcessIdProperty),$process.Id
$window=[Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,$condition)|Where-Object {$_.Current.Name -eq 'CodexIsland Settings'}|Select-Object -First 1
if(!$window){throw 'Open Providers settings first.'}
function Controls {$window.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)}
function Account([string]$id){Controls|Where-Object {$_.Current.AutomationId -eq ('ConnectAccount_'+$id)}|Select-Object -First 1}
$before=@{}
foreach($id in @('codex','claude','grok','antigravity')){
 $button=Account $id;if(!$button){throw ('Missing account control: '+$id)}
 $before[$id]=$button.Current.Name
}
$installed=$false
if($Install -ne 'inspect'){
 $button=Account $Install
 if(!$button.Current.Name.StartsWith('Install ')){throw 'The CLI is already installed; this run will not reinstall it.'}
 $button.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke();Start-Sleep -Milliseconds 600
 if((Account $Install).Current.IsEnabled){throw 'Installation must disable duplicate clicks.'}
 $deadline=[DateTime]::UtcNow.AddMinutes(10)
 do {Start-Sleep -Seconds 2;$button=Account $Install} while(!$button.Current.IsEnabled -and [DateTime]::UtcNow -lt $deadline)
 $expected=@{claude='Sign in with Claude';grok='Sign in with Grok';antigravity='Sign in with Google'}[$Install]
 if($button.Current.Name -ne $expected){throw ('Installer did not reach sign-in: '+$button.Current.Name)}
 $installed=$true
}
$after=@{};foreach($id in @('codex','claude','grok','antigravity')){$after[$id]=(Account $id).Current.Name}
$names=@(Controls|ForEach-Object {$_.Current.Name})
if($names -contains 'Antigravity and Grok account connections are not available on Windows yet.'){throw 'Outdated unsupported message remains visible.'}
$state=Get-Content (Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype\state.json') -Raw|ConvertFrom-Json
$result=[pscustomobject]@{build=$state.build;allFourAccountsPresent=$true;islandProviders=$state.preferences.SelectedProviders;before=$before;after=$after;installedThroughUI=$installed;provider=$Install}
$result|ConvertTo-Json -Depth 6|Set-Content (Join-Path $PSScriptRoot ('..\artifacts\connected-account-'+$Install+'-results.json'))
$result|ConvertTo-Json -Depth 6

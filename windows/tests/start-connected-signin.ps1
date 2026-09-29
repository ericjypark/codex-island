param([ValidateSet('antigravity','grok','claude')][string]$Provider)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
$process=Get-Process CodexIslandPrototype|Select-Object -First 1
$condition=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ProcessIdProperty),$process.Id
$window=[Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,$condition)|Where-Object {$_.Current.Name -eq 'CodexIsland Settings'}|Select-Object -First 1
if(!$window){throw 'Providers settings must be open.'}
$condition=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::AutomationIdProperty),('ConnectAccount_'+$Provider)
$button=$window.FindFirst([Windows.Automation.TreeScope]::Descendants,$condition)
$expected=@{antigravity='Sign in with Google';grok='Sign in with Grok';claude='Sign in with Claude'}[$Provider]
if(!$button -or $button.Current.Name -ne $expected -or !$button.Current.IsEnabled){throw 'This provider is not ready to begin a new sign-in.'}
$button.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
Start-Sleep -Seconds 4
[pscustomobject]@{provider=$Provider;signInStarted=(!$button.Current.IsEnabled);button=$button.Current.Name}|ConvertTo-Json

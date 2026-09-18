$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
$process=Get-Process CodexIslandPrototype|Select-Object -First 1
$owned=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ProcessIdProperty),$process.Id
$windows=[Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,$owned)
$values=@()
foreach($window in $windows){
 $condition=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ClassNameProperty),'CodexIsland'
 foreach($surface in $window.FindAll([Windows.Automation.TreeScope]::Descendants,$condition)){$values+=$surface.Current.Name}
}
$state=Get-Content (Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype\state.json') -Raw|ConvertFrom-Json
[pscustomobject]@{build=$state.build;sampleData=$state.sampleData;providerStatus=$state.providerStatus;visibleUsage=$values}|ConvertTo-Json -Depth 6

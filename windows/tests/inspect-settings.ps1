$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$p=Get-Process CodexIslandPrototype | Select-Object -First 1
$condition=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ProcessIdProperty),$p.Id
$windows=[Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,$condition)
foreach($w in $windows) {
 Write-Output ('WINDOW '+$w.Current.Name)
 $els=$w.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)
 foreach($el in $els) { if($el.Current.Name -ne '') {Write-Output ($el.Current.ControlType.ProgrammaticName+' '+$el.Current.Name)} }
}

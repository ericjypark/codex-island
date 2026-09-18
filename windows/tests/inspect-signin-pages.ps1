$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Drawing,System.Windows.Forms
$all=[Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,[Windows.Automation.Condition]::TrueCondition)
$pages=@()
foreach($window in @($all|Where-Object {$_.Current.ClassName -eq 'Chrome_WidgetWin_1'})){
 $edits=$window.FindAll([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ControlTypeProperty),([Windows.Automation.ControlType]::Edit)))
 foreach($edit in $edits){
  if($edit.Current.Name -notmatch 'address|search or enter web|주소'){continue}
  try{
   $value=$edit.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).Current.Value;$uri=$null
   if([Uri]::TryCreate($value,[UriKind]::Absolute,[ref]$uri)){$pages+=[pscustomobject]@{host=$uri.Host}}
  }catch{}
 }
}
$names=@('codex.exe','claude.exe','grok.exe','agy.exe')
$cli=@(Get-CimInstance Win32_Process|Where-Object {$_.Name -in $names}|ForEach-Object {[pscustomobject]@{name=$_.Name;id=$_.ProcessId;parent=$_.ParentProcessId}})
[pscustomobject]@{pages=$pages;cliProcesses=$cli}|ConvertTo-Json -Depth 5

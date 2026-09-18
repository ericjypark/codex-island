$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
$browserWindows=@([Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,[Windows.Automation.Condition]::TrueCondition)|Where-Object {$_.Current.ClassName -eq 'Chrome_WidgetWin_1'})
$pages=@()
foreach($window in $browserWindows){
 $edits=$window.FindAll([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ControlTypeProperty),([Windows.Automation.ControlType]::Edit)))
 foreach($edit in $edits){
  if($edit.Current.Name -notmatch 'address|search or enter web|주소'){continue}
  try {
   $value=$edit.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).Current.Value
   $uri=$null
   if([Uri]::TryCreate($value,[UriKind]::Absolute,[ref]$uri)){
    $pages+=[pscustomobject]@{host=$uri.Host;isOpenAISignIn=($uri.Host -in @('auth.openai.com','auth0.openai.com','chatgpt.com'));browserAddressFound=$true}
   }
  }catch{}
 }
}
$state=Get-Content (Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype\state.json') -Raw|ConvertFrom-Json
$cli=Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex\bin\codex.exe'
$version=if(Test-Path $cli){& $cli --version}else{'Not found'}
$result=[pscustomobject]@{codexVersion=$version;pages=$pages;sampleData=$state.sampleData;providerStatus=$state.providerStatus}
$result|ConvertTo-Json -Depth 6|Set-Content (Join-Path $PSScriptRoot '..\artifacts\account-login-results.json')
$result|ConvertTo-Json -Depth 6

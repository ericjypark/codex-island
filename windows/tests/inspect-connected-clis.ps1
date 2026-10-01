$ErrorActionPreference='Stop'
$agy=Join-Path $env:LOCALAPPDATA 'agy\bin\agy.exe'
if(Test-Path $agy){
 'Antigravity version:'
 & $agy --version
 'Antigravity command help:'
 & $agy --help
}
$grok=Join-Path $env:USERPROFILE '.grok\bin\grok.exe'
if(Test-Path $grok){
 'Grok version:'
 & $grok --version
 'Grok login command help:'
 & $grok login --help
}

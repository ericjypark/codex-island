$ErrorActionPreference='Stop'
$path=Join-Path $env:USERPROFILE '.grok\bin\grok.exe'
if(!(Test-Path $path)){throw 'Grok must be installed.'}
$command="& '"+$path.Replace("'","''")+"' login"
$start=New-Object Diagnostics.ProcessStartInfo
$start.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$start.UseShellExecute=$true
$start.WorkingDirectory=$env:USERPROFILE
$start.Arguments='-NoProfile -NoExit -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
$process=[Diagnostics.Process]::Start($start)
[pscustomobject]@{diagnosticTerminal=$process.Id}|ConvertTo-Json

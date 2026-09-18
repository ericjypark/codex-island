$ErrorActionPreference='Stop'
$root=Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype\grok-compat-probe'
New-Item -ItemType Directory -Force $root|Out-Null
$target=Join-Path $root 'grok.exe'
if(!(Test-Path $target)){Invoke-WebRequest -UseBasicParsing -Uri 'https://x.ai/cli/grok-1.0.30-windows-x86_64.exe' -OutFile $target}
$version=& $target --version
$native=Join-Path $env:USERPROFILE '.grok\bin\grok.exe'
function Metadata([string]$path){
 $stream=[IO.File]::OpenRead($path);$reader=New-Object IO.BinaryReader $stream
 try{$stream.Position=60;$offset=$reader.ReadInt32();$stream.Position=$offset+4;$machine=$reader.ReadUInt16();$stream.Position=$offset+24+72;$stack=$reader.ReadUInt64();[pscustomobject]@{machine=$machine;stackReserve=$stack;size=$stream.Length}}finally{$reader.Dispose()}
}
[pscustomobject]@{version=$version;native=(Metadata $native);x64=(Metadata $target)}|ConvertTo-Json
$command="& '"+$target.Replace("'","''")+"' login"
$start=New-Object Diagnostics.ProcessStartInfo
$start.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe';$start.UseShellExecute=$true;$start.WorkingDirectory=$env:USERPROFILE
$start.Arguments='-NoProfile -NoExit -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
$process=[Diagnostics.Process]::Start($start)
[pscustomobject]@{diagnosticTerminal=$process.Id}|ConvertTo-Json

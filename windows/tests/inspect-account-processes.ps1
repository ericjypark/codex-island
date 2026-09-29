$ErrorActionPreference='Stop'
$names=@('CodexIslandPrototype.exe','codex.exe','claude.exe','grok.exe','agy.exe')
$items=@(Get-CimInstance Win32_Process|Where-Object {$_.Name -in $names})
$items|ForEach-Object {[pscustomobject]@{name=$_.Name;id=$_.ProcessId;parent=$_.ParentProcessId}}|ConvertTo-Json

$ErrorActionPreference='Stop'
$expected=@(@{id=964;parent=1864;name='claude.exe'},@{id=3424;parent=4948;name='grok.exe'})
foreach($item in $expected){
 $process=Get-CimInstance Win32_Process -Filter ('ProcessId='+$item.id)
 if($process -and $process.Name -eq $item.name -and $process.ParentProcessId -eq $item.parent){Stop-Process -Id $item.id;[pscustomobject]@{stopped=$item.name;id=$item.id}|ConvertTo-Json -Compress}
}

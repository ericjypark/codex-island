$ErrorActionPreference='Stop'
$commands=@('codex','claude','node','npm','winget','git')|ForEach-Object {
 $found=Get-Command $_ -ErrorAction SilentlyContinue|Select-Object -First 1
 [pscustomobject]@{command=$_;found=($null -ne $found);kind=if($found){$found.CommandType.ToString()}else{$null}}
}
$paths=@{
 codexStandalone=(Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex\bin\codex.exe')
 codexLegacyNative=(Join-Path $env:USERPROFILE '.local\bin\codex.exe')
 codexNpm=(Join-Path $env:APPDATA 'npm\codex.cmd')
 claudeNative=(Join-Path $env:USERPROFILE '.local\bin\claude.exe')
 codexAuth=(Join-Path $(if($env:CODEX_HOME){$env:CODEX_HOME}else{Join-Path $env:USERPROFILE '.codex'}) 'auth.json')
 claudeAuth=(Join-Path $(if($env:CLAUDE_CONFIG_DIR){$env:CLAUDE_CONFIG_DIR}else{Join-Path $env:USERPROFILE '.claude'}) '.credentials.json')
}
[pscustomobject]@{commands=$commands;paths=@($paths.GetEnumerator()|ForEach-Object {[pscustomobject]@{name=$_.Key;exists=(Test-Path $_.Value)}});architecture=$env:PROCESSOR_ARCHITECTURE}|ConvertTo-Json -Depth 5

$ErrorActionPreference='Stop'
$codex=Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex\bin\codex.exe'
& $codex app-server --help

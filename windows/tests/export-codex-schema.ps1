$ErrorActionPreference='Stop'
$codex=Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex\bin\codex.exe'
& $codex app-server generate-json-schema --out (Join-Path $PSScriptRoot '..\artifacts\codex-protocol-schema')

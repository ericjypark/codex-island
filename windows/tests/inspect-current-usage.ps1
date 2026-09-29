$ErrorActionPreference='Stop'
$state=Get-Content (Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype\state.json') -Raw|ConvertFrom-Json
[pscustomobject]@{build=$state.build;sampleData=$state.sampleData;providerStatus=$state.providerStatus;usageUpdated=$state.usageUpdated;loading=$state.usageLoading}|ConvertTo-Json -Depth 6

$ErrorActionPreference='Stop'
$root=Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype'
$state=Get-Content (Join-Path $root 'state.json') -Raw|ConvertFrom-Json
for($i=0;$i -lt 20 -and !$state.currencyUpdatedAt;$i++) {
 Start-Sleep -Milliseconds 250
 $state=Get-Content (Join-Path $root 'state.json') -Raw|ConvertFrom-Json
}
$rates=Get-Content (Join-Path $root 'currency-rates.json') -Raw|ConvertFrom-Json
[pscustomobject]@{currency=$state.currency;lastUpdated=$state.currencyUpdatedAt;error=$state.currencyError;usdRate=$rates.Rates.USD;krwRatePresent=($rates.Rates.KRW -gt 0);eurRatePresent=($rates.Rates.EUR -gt 0)}|ConvertTo-Json

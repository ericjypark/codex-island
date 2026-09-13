param([ValidateSet('prepare','offline','recovered')][string]$Action='prepare',[string]$Snapshot)
$ErrorActionPreference='Stop'
$root=Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype'
$contextPath=Join-Path $root 'network-check.json'
function State([string]$directory){try{Get-Content (Join-Path $directory 'state.json') -Raw|ConvertFrom-Json}catch{$null}}
function Codex($state){$state.providerStatus|Where-Object {$_.id -eq 'codex'}|Select-Object -First 1}
if($Action -eq 'prepare'){
 $profile=Get-Content (Join-Path $Snapshot 'interactive-profile.json') -Raw|ConvertFrom-Json
 $app=Get-Process CodexIslandPrototype|Where-Object {$_.Path -eq $profile.executable}|Select-Object -First 1
 if(!$app){throw 'The intended history preview is not running.'}
 $deadline=(Get-Date).AddSeconds(30)
 do{$state=State $profile.profile;if($state -and !$state.usageLoading -and (Codex $state).status -eq 'Ready'){break};Start-Sleep -Milliseconds 100}while((Get-Date) -lt $deadline)
 if(!$state -or $state.sampleData -or $state.usageLoading -or (Codex $state).status -ne 'Ready' -or !$state.networkEventsRegistered -or $state.wakeGrace){throw 'A connected live preview outside wake grace is required.'}
 if([DateTimeOffset]$state.nextExpectedRefresh -lt [DateTimeOffset]::UtcNow.AddSeconds(90)){throw 'The regular poll is too close to isolate network recovery. Run after it finishes.'}
 if(![Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()){throw 'The VM network must begin connected.'}
 $context=[pscustomobject]@{profile=$profile.profile;executable=$profile.executable;build=$state.build;priorAttempt=(Codex $state).attemptedAt;regularPoll=$state.nextExpectedRefresh;offlineObserved=$false;offlineAt=$null;output=(Join-Path $PSScriptRoot '..\artifacts\native-network-results.json')}
 $context|ConvertTo-Json|Set-Content $contextPath
 $driver=Join-Path $root 'check-network-recovery.ps1';Copy-Item $PSCommandPath $driver -Force
 Write-Output ('DRIVER='+$driver)
 return
}
$context=Get-Content $contextPath -Raw|ConvertFrom-Json
$app=Get-Process CodexIslandPrototype|Where-Object {$_.Path -eq $context.executable}|Select-Object -First 1
if(!$app -or (State $context.profile).build -ne $context.build){throw 'The prepared preview instance changed.'}
if($Action -eq 'offline'){
 $deadline=(Get-Date).AddSeconds(15)
 while([Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable() -and (Get-Date) -lt $deadline){Start-Sleep -Milliseconds 100}
 if([Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()){throw 'Windows did not report the disconnected adapter as unavailable.'}
 $context.offlineObserved=$true;$context.offlineAt=[DateTimeOffset]::UtcNow.ToString('o');$context|ConvertTo-Json|Set-Content $contextPath
 Write-Output 'PASS: Windows observed the real VM network becoming unavailable.'
 return
}
if(!$context.offlineObserved){throw 'The disconnected network state was not verified.'}
$deadline=(Get-Date).AddSeconds(30)
do {
 $state=State $context.profile;$codex=Codex $state
 if($state -and !$state.usageLoading -and $codex.status -eq 'Ready' -and [DateTimeOffset]$codex.attemptedAt -gt [DateTimeOffset]$context.priorAttempt){break}
 Start-Sleep -Milliseconds 100
}while((Get-Date) -lt $deadline)
if(!$state -or $state.usageLoading -or $codex.status -ne 'Ready' -or [DateTimeOffset]$codex.attemptedAt -le [DateTimeOffset]$context.priorAttempt){throw 'The reconnected preview did not obtain a fresh successful quota response.'}
if(![Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()){throw 'The VM network has not returned.'}
if([DateTimeOffset]::UtcNow -ge [DateTimeOffset]$context.regularPoll -or $state.nextExpectedRefresh -ne $context.regularPoll){throw 'The regular polling timer overlapped this network check.'}
[pscustomobject]@{build=$state.build;sampleData=$state.sampleData;actualAdapterTransition=$true;unavailableObserved=$true;connectedAfter=$true;freshCodexReady=$true;regularPollNotDue=$true;regularCadencePreserved=$true;verifiedAt=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content $context.output
Write-Output ('PASS: The live preview recovered a fresh quota reading before its regular poll on build '+$state.build)

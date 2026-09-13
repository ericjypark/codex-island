param([Parameter(Mandatory=$true)][string]$Snapshot)
$ErrorActionPreference='Stop'
$profile=Get-Content (Join-Path $Snapshot 'interactive-profile.json') -Raw|ConvertFrom-Json
$state=Get-Content (Join-Path $profile.profile 'state.json') -Raw|ConvertFrom-Json
if($state.build -ne $profile.build -or $state.sampleData){throw 'The intended installed build is not running in live mode.'}
if(!(Get-Process CodexIslandPrototype|Where-Object {$_.Path -eq $profile.executable})){throw 'The intended executable is not running.'}
$source=Get-ChildItem $profile.profile -Directory -Filter 'update-source-*'|Sort-Object LastWriteTime -Descending|Select-Object -First 1
$files=@('IslandVisual.cs','IslandAccessibility.cs','DollarGlowLayer.cs','UsageFeed.cs','MainWindow.xaml.cs','FrameDiagnostics.cs')
$hashes=@();foreach($name in $files){
 $repo=(Get-FileHash (Join-Path $PSScriptRoot ('..\IslandPrototype\'+$name)) -Algorithm SHA256).Hash
 $built=(Get-FileHash (Join-Path $source.FullName $name) -Algorithm SHA256).Hash
 if($repo -ne $built){throw ('Installed source differs: '+$name)};$hashes+=@{file=$name;sha256=$repo}
}
$installed=(Get-FileHash (Join-Path (Split-Path $profile.executable) 'CodexIslandPrototype.dll') -Algorithm SHA256).Hash
$staged=(Get-FileHash (Join-Path $profile.profile 'staged-app\CodexIslandPrototype.dll') -Algorithm SHA256).Hash
if($installed -ne $staged){throw 'Installed binary differs from the verified staged build.'}
$baseline=Get-Content (Join-Path $PSScriptRoot '..\artifacts\responsiveness-baseline\results.json') -Raw|ConvertFrom-Json
$preserved=($state.preferences|ConvertTo-Json -Depth 12 -Compress) -eq ($baseline.preferences|ConvertTo-Json -Depth 12 -Compress)
if(!$preserved){throw 'The measurement did not preserve the original preferences.'}
@{build=$state.build;verifiedAt=[DateTimeOffset]::UtcNow.ToString('O');preferencesPreserved=$preserved;sampleData=$state.sampleData;sourceHashes=$hashes;binarySha256=$installed}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $PSScriptRoot '..\artifacts\responsiveness-confirmed\installed-manifest.json')
Write-Output ('Verified installed build '+$state.build+', six source files, binary, live profile, and original preferences.')

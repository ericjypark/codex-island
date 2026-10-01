param(
    [string]$PackagePath,
    [string]$OutputName='window-motion',
    [ValidateSet('arm64','x64')][string]$Architecture='arm64',
    [ValidateSet('measure','regression','introduction','no-counter','no-sweep','no-shadows')][string]$Variant='measure'
)
$ErrorActionPreference='Stop'
$env:DOTNET_CLI_TELEMETRY_OPTOUT='1'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$base=Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype'
$work=Join-Path $base ('window-motion-'+[Guid]::NewGuid().ToString('N'))
$dotnet=Join-Path $base 'dotnet\dotnet.exe'
try {
    $source=Join-Path $work 'probe';New-Item -ItemType Directory -Force $source|Out-Null
    Copy-Item (Join-Path $PSScriptRoot 'window-motion\*') $source
    Copy-Item (Join-Path $PSScriptRoot '..\IslandPrototype\Assets') $source -Recurse
    $app=Join-Path $work 'package'
    if($PackagePath){[IO.Compression.ZipFile]::ExtractToDirectory($PackagePath,$app)}
    else {
        $appSource=Join-Path $work 'app-source'
        & robocopy (Join-Path $PSScriptRoot '..\IslandPrototype') $appSource /E /XD bin obj /NFL /NDL /NJH /NJS /NP|Out-Null
        if($LASTEXITCODE -ge 8){throw 'App source staging failed.'}
        & $dotnet publish (Join-Path $appSource 'IslandPrototype.csproj') -c Release -r ('win-'+$Architecture) --self-contained true -o $app --nologo
        if($LASTEXITCODE -ne 0){throw 'App build failed.'}
    }
    $binary=Get-ChildItem $app -Recurse -Filter CodexIslandPrototype.dll|Select-Object -First 1
    $publish=Join-Path $work 'runner'
    & $dotnet publish (Join-Path $source 'WindowMotionTests.csproj') -c Release -r ('win-'+$Architecture) --self-contained true -o $publish --nologo
    if($LASTEXITCODE -ne 0){throw 'Motion probe build failed.'}
    $profile=Join-Path $work 'profile';New-Item -ItemType Directory -Force $profile|Out-Null
    @{SchemaVersion=2;LiveMode=($Variant -eq 'introduction');AlwaysShowUsage=($Variant -ne 'introduction');ReduceMotion=$false;LowPower=$false;AutomaticUpdates=$false;Page=0;HasNavigated=$true;HasCycledChart=$true;LeftProvider='codex';RightProvider='antigravity'}|ConvertTo-Json|Set-Content (Join-Path $profile 'preferences.json') -Encoding UTF8
    $output=Join-Path (Join-Path $PSScriptRoot '..\artifacts') $OutputName
    $dataMode=if($Variant -eq 'introduction'){'--live'}else{'--demo'}
    & (Join-Path $publish 'WindowMotionTests.exe') $binary.DirectoryName $output $dataMode --data-dir $profile --probe-mode $Variant
    if($LASTEXITCODE -ne 0){throw 'Motion checks failed.'}
} finally {
    for($attempt=0;$attempt -lt 5 -and (Test-Path $work);$attempt++) {
        try {Remove-Item $work -Recurse -Force}
        catch {
            if($attempt -eq 4){Write-Warning ('Temporary probe files remain at '+$work)}
            else {Start-Sleep -Milliseconds 250}
        }
    }
}

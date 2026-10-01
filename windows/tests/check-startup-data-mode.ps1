param([Parameter(Mandatory=$true)][string]$PackagePath,[string]$ReceiptPath)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type @'
using System;using System.Runtime.InteropServices;
public static class StartupCheckWindow {
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr window,uint message,IntPtr wParam,IntPtr lParam);
}
'@
$work=Join-Path $env:LOCALAPPDATA ('CodexIslandStartupCheck\'+[Guid]::NewGuid().ToString('N'))
$results=New-Object Collections.Generic.List[object]
try {
    [IO.Compression.ZipFile]::ExtractToDirectory($PackagePath,$work)
    $exe=Get-ChildItem $work -Recurse -Filter CodexIslandPrototype.exe|Select-Object -First 1
    if(!$exe){throw 'The package has no application executable.'}
    $profile=Join-Path $work 'isolated-profile'
    $preferencesFile=Join-Path $profile 'preferences.json'
    function Launch-Check([string]$Name,[bool]$ExpectedDemo,[string[]]$ModeArguments=@()) {
        $arguments=@($ModeArguments)+@('--settings','--data-dir',('"'+$profile+'"'))
        $stateFile=Join-Path $profile 'state.json'
        if(Test-Path $stateFile){Remove-Item $stateFile}
        $owned=Start-Process $exe.FullName -ArgumentList $arguments -PassThru
        $state=$null
        try {
            $deadline=[DateTime]::UtcNow.AddSeconds(20)
            do {
                Start-Sleep -Milliseconds 200
                $owned.Refresh();if($owned.HasExited){throw 'The test application exited during startup.'}
                try {$state=Get-Content $stateFile -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop}catch{$state=$null}
            } while((!$state -or $state.preferences.SettingsTab -ne 'general' -or !(Test-Path $preferencesFile)) -and [DateTime]::UtcNow -lt $deadline)
            if(!$state -or $state.sampleData -ne $ExpectedDemo){throw ($Name+': unexpected sample-data mode.')}
            $results.Add(@{name=$Name;sampleData=$state.sampleData;effectiveLiveMode=$state.preferences.LiveMode;schema=$state.preferences.SchemaVersion;version=$state.appVersion;build=$state.build})
            return $state
        } finally {
            $owned.Refresh()
            if(!$owned.HasExited -and $state.window){[StartupCheckWindow]::PostMessage([IntPtr]([long]$state.window),0x10,[IntPtr]::Zero,[IntPtr]::Zero)|Out-Null}
            $owned.WaitForExit(5000)|Out-Null
            $owned.Refresh();if(!$owned.HasExited){Stop-Process -Id $owned.Id;Wait-Process -Id $owned.Id -ErrorAction SilentlyContinue}
        }
    }
    $null=Launch-Check 'A fresh normal launch uses live accounts' $false
    $null=Launch-Check 'Opening Settings and relaunching retains live accounts' $false
    $legacy=Get-Content $preferencesFile -Raw|ConvertFrom-Json
    $legacy.SchemaVersion=1;$legacy.LiveMode=$false;$legacy.Currency='KRW';$legacy.SettingsTab='providers'
    $legacy|ConvertTo-Json -Depth 20|Set-Content $preferencesFile -Encoding UTF8
    $recovered=Launch-Check 'Legacy implicit demo settings recover on normal startup' $false
    if($recovered.preferences.Currency -ne 'KRW' -or !$recovered.preferences.LiveMode){throw 'Recovery did not retain preferences and restore live mode.'}
    $null=Launch-Check 'The explicit demo flag still previews sample data' $true @('--demo')
    $null=Launch-Check 'The demo flag does not change the next normal launch' $false
    $explicit=Get-Content $preferencesFile -Raw|ConvertFrom-Json
    $explicit.SchemaVersion=2;$explicit.LiveMode=$false
    $explicit|ConvertTo-Json -Depth 20|Set-Content $preferencesFile -Encoding UTF8
    $null=Launch-Check 'An explicit saved preview choice is retained' $true
    $receipt=@{package=(Split-Path $PackagePath -Leaf);verifiedAt=[DateTimeOffset]::UtcNow.ToString('o');checks=$results.Count;results=$results}
    $json=$receipt|ConvertTo-Json -Depth 6
    if($ReceiptPath){$json|Set-Content $ReceiptPath -Encoding UTF8}
    $json
} finally {
    if(Test-Path $work){Remove-Item $work -Recurse -Force}
}

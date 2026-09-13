param([ValidateSet('arm64','x64')][string]$Architecture='arm64',[ValidateSet('Install','Upgrade','Verify','Uninstall')][string]$Stage='Install',[switch]$CorruptFirst,[string]$FromVersion='0.0.1',[string]$ToVersion='0.0.2',[switch]$CheckStartupRemoval)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Drawing,System.Windows.Forms
Add-Type @'
using System;using System.Runtime.InteropServices;
public static class UpdateCapture {
 [DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr handle);
 [DllImport("user32.dll")]public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
 [DllImport("dwmapi.dll")]public static extern int DwmFlush();
}
'@
[UpdateCapture]::SetThreadDpiAwarenessContext([IntPtr](-4))|Out-Null
$root=Join-Path $env:LOCALAPPDATA ('CodexIslandPrototype\update-qa\'+$Architecture)
$feed=Join-Path $root 'feed';$profile=Join-Path $root 'profile'
$packageId='CodexIsland.UpdateTest.'+$(if($Architecture -eq 'arm64'){'Arm64'}else{'X64'})
$installed=Join-Path $env:LOCALAPPDATA $packageId
$executable=Join-Path $installed 'current\CodexIslandPrototype.exe'
$statePath=Join-Path $profile 'state.json'
$results=Join-Path $PSScriptRoot ('..\artifacts\installer-qa\'+$Architecture)
New-Item -ItemType Directory -Force $results|Out-Null
function State {try{Get-Content $statePath -Raw|ConvertFrom-Json}catch{return $null}}
function Owned {Get-Process CodexIslandPrototype -ErrorAction SilentlyContinue|Where-Object {$_.Path -eq $executable}|Select-Object -First 1}
function WaitFor([scriptblock]$condition,[string]$description) {
    $deadline=[DateTime]::UtcNow.AddSeconds(100)
    do {if(& $condition){return};Start-Sleep -Milliseconds 250}while([DateTime]::UtcNow -lt $deadline)
    throw ('Timed out: '+$description+'; state='+(State|ConvertTo-Json -Compress -Depth 4))
}
function Settings {
    $process=Owned;if(!$process){return $null}
    $owned=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ProcessIdProperty),$process.Id
    [Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,$owned)|Where-Object {$_.Current.Name -eq 'CodexIsland Settings'}|Select-Object -First 1
}
function Control([string]$name,[bool]$id=$true) {
    $property=if($id){[Windows.Automation.AutomationElement]::AutomationIdProperty}else{[Windows.Automation.AutomationElement]::NameProperty}
    $condition=New-Object Windows.Automation.PropertyCondition $property,$name
    (Settings).FindAll([Windows.Automation.TreeScope]::Descendants,$condition)|Where-Object {$_.Current.ControlType -ne [Windows.Automation.ControlType]::Text}|Select-Object -First 1
}
function Invoke([string]$name,[bool]$id=$true) {
    $control=Control $name $id;if(!$control){throw ('Missing control '+$name)}
    $control.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
}
function Launch {
    Start-Process $executable -ArgumentList ('--demo --settings --data-dir "'+$profile+'"')|Out-Null
    WaitFor {Settings} 'Settings to open'
}
function Check([string]$name,[bool]$passed) {if(!$passed){throw ('Failed: '+$name)};Write-Output ('PASS: '+$name)}
function Capture([string]$name) {
    $window=Settings;[UpdateCapture]::SetForegroundWindow([IntPtr]$window.Current.NativeWindowHandle)|Out-Null
    $scroll=$window.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)|Where-Object {$_.GetCurrentPropertyValue([Windows.Automation.AutomationElement]::IsScrollPatternAvailableProperty)}|Select-Object -First 1
    if($scroll){$scroll.GetCurrentPattern([Windows.Automation.ScrollPattern]::Pattern).SetScrollPercent(-1,100)}
    Start-Sleep -Milliseconds 800;[UpdateCapture]::DwmFlush()|Out-Null
    $bounds=$window.Current.BoundingRectangle
    $bitmap=New-Object Drawing.Bitmap ([int]$bounds.Width),([int]$bounds.Height)
    $graphics=[Drawing.Graphics]::FromImage($bitmap)
    try{$graphics.CopyFromScreen([int]$bounds.X,[int]$bounds.Y,0,0,$bitmap.Size);$bitmap.Save((Join-Path $results ($name+'.png')))}finally{$graphics.Dispose();$bitmap.Dispose()}
}
if($Stage -eq 'Install') {
    if(Test-Path $installed){throw 'A QA installation already exists. Inspect it before choosing a fresh test run.'}
    New-Item -ItemType Directory -Force $profile|Out-Null
    @{SettingsTab='general';AutomaticUpdates=$false;LiveMode=$false;Spacing='compact';RefreshSeconds=900;Remaining=$true;ReduceMotion=$true;Currency='KRW';Language='en'}|ConvertTo-Json|Set-Content (Join-Path $profile 'preferences.json') -Encoding UTF8
    Add-Type @'
using System;using System.Runtime.InteropServices;
public static class UpdateFixtureSqlite {
 [DllImport("winsqlite3",CallingConvention=CallingConvention.Cdecl)]static extern int sqlite3_open([MarshalAs(UnmanagedType.LPUTF8Str)]string file,out IntPtr db);
 [DllImport("winsqlite3",CallingConvention=CallingConvention.Cdecl)]static extern int sqlite3_exec(IntPtr db,[MarshalAs(UnmanagedType.LPUTF8Str)]string sql,IntPtr callback,IntPtr args,IntPtr error);
 [DllImport("winsqlite3",CallingConvention=CallingConvention.Cdecl)]static extern int sqlite3_close(IntPtr db);
 public static void Create(string path){IntPtr db;if(sqlite3_open(path,out db)!=0)throw new Exception("Fixture open failed");try{if(sqlite3_exec(db,"PRAGMA user_version=1; CREATE TABLE usage_events(source TEXT NOT NULL,record_id TEXT NOT NULL,provider TEXT NOT NULL,timestamp_ms INTEGER NOT NULL,model TEXT NOT NULL,input_tokens INTEGER NOT NULL,output_tokens INTEGER NOT NULL,cache_creation_tokens INTEGER NOT NULL,cache_read_tokens INTEGER NOT NULL,PRIMARY KEY(source,record_id)) WITHOUT ROWID; INSERT INTO usage_events VALUES('fixture','preserved','codex',1789200000000,'gpt-5',1234,567,0,89);",IntPtr.Zero,IntPtr.Zero,IntPtr.Zero)!=0)throw new Exception("Fixture write failed");}finally{sqlite3_close(db);}}
}
'@
    [UpdateFixtureSqlite]::Create((Join-Path $profile 'usage-history.sqlite3'))
    $setup=Join-Path $feed ($packageId+'-win-'+$Architecture+'-preview-Setup.exe')
    $process=Start-Process $setup -ArgumentList '--silent' -Wait -PassThru
    Check 'Installer completes without requiring a separately installed .NET runtime' ($process.ExitCode -eq 0 -and (Test-Path (Join-Path $installed 'current\coreclr.dll')) -and (Test-Path (Join-Path $installed 'current\PresentationFramework.dll')))
    Launch
    WaitFor {(State).appVersion -eq '0.0.1'} 'version 0.0.1'
    Invoke 'CheckForUpdates';WaitFor {(State).appUpdate.Phase -eq 3} 'initial no-update check'
    $preferences=Join-Path $profile 'preferences.json';$history=Join-Path $profile 'usage-history.sqlite3'
    @{preferences=(Get-FileHash $preferences).Hash;history=(Get-FileHash $history).Hash;version=(State).appVersion;pid=(Owned).Id}|ConvertTo-Json|Set-Content (Join-Path $results 'before.json')
    Check 'The installed app finds its architecture-specific feed and reports no update' ((State).appUpdate.Phase -eq 3)
} elseif($Stage -eq 'Upgrade') {
    Check 'The old version is still running before checking' ((State).appVersion -eq $FromVersion)
    if($CorruptFirst) {
        $feedPath=Join-Path $feed ('releases.win-'+$Architecture+'-preview.json')
        $originalFeed=[IO.File]::ReadAllBytes($feedPath)
        $index=Get-Content $feedPath -Raw|ConvertFrom-Json
        $index.Assets=@($index.Assets|Where-Object {$_.Type -eq 'Full'})
        try {
            $index|ConvertTo-Json -Depth 20|Set-Content $feedPath -Encoding UTF8
            Invoke 'CheckForUpdates';WaitFor {(State).appUpdate.Phase -eq 4} 'full update available'
            $asset=$index.Assets|Where-Object {$_.Version -eq $ToVersion}|Select-Object -First 1
            $package=Join-Path $feed $asset.FileName
            $stream=[IO.File]::Open($package,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::Read)
            $offset=[int64]($stream.Length/2);$stream.Position=$offset;$originalByte=$stream.ReadByte();$stream.Position=$offset;$stream.WriteByte(($originalByte -bxor 255));$stream.Dispose()
            try {
                Invoke 'ApplyUpdate';WaitFor {(State).appUpdate.Phase -eq 4 -and (State).appUpdate.Error} 'corrupted download rejected'
                Check 'A damaged real package is rejected while the installed version keeps running' ((State).appVersion -eq $FromVersion -and (State).appUpdate.Error -like '*verified*')
            } finally {
                $stream=[IO.File]::OpenWrite($package);$stream.Position=$offset;$stream.WriteByte($originalByte);$stream.Dispose()
            }
        } finally {[IO.File]::WriteAllBytes($feedPath,$originalFeed)}
    }
    Invoke 'CheckForUpdates';WaitFor {(State).appUpdate.Phase -eq 4} 'update available'
    Check 'The new version is offered without downloading automatically' ((State).appUpdate.AvailableVersion -eq $ToVersion)
    Invoke 'ApplyUpdate';WaitFor {(State).appUpdate.Phase -eq 6} 'update ready'
    Capture 'ready-to-update'
    Check 'Downloading keeps the running version unchanged' ((State).appVersion -eq $FromVersion)
    Invoke 'Quit' $false;WaitFor {!(Owned)} 'old process to exit without applying'
    Launch
    WaitFor {(State).appUpdate.Phase -eq 6} 'downloaded update restored'
    Check 'An ordinary relaunch does not install the downloaded update' ((State).appVersion -eq $FromVersion)
    $oldPid=(Owned).Id;Invoke 'ApplyUpdate'
    WaitFor {$p=Owned;$p -and $p.Id -ne $oldPid -and (State).appVersion -eq $ToVersion} 'the updated process to restart'
    WaitFor {Settings} 'updated Settings to open'
    $before=Get-Content (Join-Path $results 'before.json') -Raw|ConvertFrom-Json
    $historyHash=(Get-FileHash (Join-Path $profile 'usage-history.sqlite3')).Hash
    $preferencesHash=(Get-FileHash (Join-Path $profile 'preferences.json')).Hash
    Check 'The complete preferences file is unchanged after upgrade' ($before.preferences -eq $preferencesHash)
    Check 'The existing SQLite history file is unchanged after upgrade' ($before.history -eq $historyHash)
    Check 'Restart arguments preserve the separate demo data profile' ((State).sampleData -eq $true -and (State).preferences.Spacing -eq 'compact' -and (State).preferences.Currency -eq 'KRW')
    Invoke 'CheckForUpdates';WaitFor {(State).appUpdate.Phase -eq 3} 'updated app no-update check'
    Capture 'updated'
    @{version=(State).appVersion;preferencesUnchanged=($before.preferences -eq $preferencesHash);historyUnchanged=($before.history -eq $historyHash);executable=$executable;architecture=$Architecture;selfContained=$true;automaticApplyDisabled=$true;pid=(Owned).Id}|ConvertTo-Json|Set-Content (Join-Path $results 'after.json')
} elseif($Stage -eq 'Uninstall') {
    $before=Get-Content (Join-Path $results 'before.json') -Raw|ConvertFrom-Json
    $runKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';$startupName=$null
    if($CheckStartupRemoval) {
        $toggle=Control 'Launch at Login' $false
        $toggle.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Toggle();Start-Sleep -Milliseconds 250
        $entry=(Get-ItemProperty $runKey).PSObject.Properties|Where-Object {$_.Name -like 'CodexIslandProfile-*' -and $_.Value -like ('*'+$installed+'*')}|Select-Object -First 1
        Check 'Launch at Login targets the stable launcher and retains the data profile' ($entry -and $entry.Value -like ('"'+$installed+'\CodexIslandPrototype.exe"*') -and $entry.Value.Contains($profile))
        $startupName=$entry.Name
    }
    Invoke 'Quit' $false;WaitFor {!(Owned)} 'QA app to quit before uninstall'
    $uninstall=Start-Process (Join-Path $installed 'Update.exe') -ArgumentList '--silent uninstall' -Wait -PassThru
    WaitFor {!(Test-Path $executable)} 'QA installation to be removed'
    Check 'The uninstaller removes the app and leaves its preferences and history intact' ($uninstall.ExitCode -eq 0 -and (Get-FileHash (Join-Path $profile 'preferences.json')).Hash -eq $before.preferences -and (Get-FileHash (Join-Path $profile 'usage-history.sqlite3')).Hash -eq $before.history)
    if($startupName){Check "Uninstall removes only this installation's startup entry" (!(Get-ItemProperty $runKey).PSObject.Properties[$startupName])}
    @{uninstalled=$true;historyPreserved=$true;startupRemoved=[bool]$CheckStartupRemoval}|ConvertTo-Json|Set-Content (Join-Path $results 'uninstall.json')
} else {
    Capture 'current'
    State|ConvertTo-Json -Depth 4
}

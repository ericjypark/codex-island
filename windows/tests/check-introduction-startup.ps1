param([Parameter(Mandatory=$true)][string]$PackagePath,[Parameter(Mandatory=$true)][string]$ReceiptPath)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type @'
using System;using System.Runtime.InteropServices;
public static class IntroductionStartupInput {
 [StructLayout(LayoutKind.Sequential)] public struct Point {public int X,Y;}
 [DllImport("user32.dll")] public static extern bool GetCursorPos(out Point point);
 [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);
 [DllImport("user32.dll")] public static extern void mouse_event(uint flags,uint x,uint y,uint data,UIntPtr extra);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr window,uint message,IntPtr wParam,IntPtr lParam);
 public static void Move(int x,int y){mouse_event(0xC001,(uint)((x-GetSystemMetrics(76))*65535.0/(GetSystemMetrics(78)-1)),(uint)((y-GetSystemMetrics(77))*65535.0/(GetSystemMetrics(79)-1)),0,UIntPtr.Zero);}
}
'@
$work=Join-Path $env:LOCALAPPDATA ('CodexIslandIntroductionCheck\'+[Guid]::NewGuid().ToString('N'))
$results=New-Object Collections.Generic.List[object]
$pointer=New-Object IntroductionStartupInput+Point
[IntroductionStartupInput]::GetCursorPos([ref]$pointer)|Out-Null
$owned=$null;$state=$null
function Read-State {
    try {return Get-Content $stateFile -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop}catch{return $null}
}
function Stop-Owned {
    if(!$owned){return}
    $owned.Refresh()
    if(!$owned.HasExited -and $state.window){[IntroductionStartupInput]::PostMessage([IntPtr]([long]$state.window),0x10,[IntPtr]::Zero,[IntPtr]::Zero)|Out-Null}
    $owned.WaitForExit(5000)|Out-Null
    $owned.Refresh();if(!$owned.HasExited){Stop-Process -Id $owned.Id;Wait-Process -Id $owned.Id -ErrorAction SilentlyContinue}
}
try {
    [IO.Compression.ZipFile]::ExtractToDirectory($PackagePath,$work)
    $exe=Get-ChildItem $work -Recurse -Filter CodexIslandPrototype.exe|Select-Object -First 1
    if(!$exe){throw 'The package has no application executable.'}
    $profile=Join-Path $work 'isolated-profile';$stateFile=Join-Path $profile 'state.json'
    $awayX=[IntroductionStartupInput]::GetSystemMetrics(76)+20
    $awayY=[IntroductionStartupInput]::GetSystemMetrics(77)+[int]([IntroductionStartupInput]::GetSystemMetrics(79)/2)
    [IntroductionStartupInput]::Move($awayX,$awayY)
    foreach($run in 1..2){
        if(Test-Path $stateFile){Remove-Item $stateFile}
        $owned=Start-Process $exe.FullName -ArgumentList @('--data-dir',('"'+$profile+'"')) -PassThru
        $deadline=[DateTime]::UtcNow.AddSeconds(20)
        do {
            Start-Sleep -Milliseconds 150;$state=Read-State
            $owned.Refresh();if($owned.HasExited){throw 'The test application exited during startup.'}
        } while((!$state -or ($run -eq 1 -and !$state.introductionVisible)) -and [DateTime]::UtcNow -lt $deadline)
        if(!$state){throw 'The test application did not provide state.'}
        if($state.sampleData){throw 'The fresh installation did not launch with live accounts.'}
        if($run -eq 1){
            if(!$state.introductionVisible -or $state.state -ne 'Peek' -or $state.preferences.HasSeenIntroduction){throw 'First launch did not show an uncompleted introduction.'}
            $results.Add(@{name='Fresh normal launch shows the pill and guide';pass=$true;build=$state.build})
            $deadline=[DateTime]::UtcNow.AddSeconds(14)
            do {Start-Sleep -Milliseconds 150;$state=Read-State}while((!$state -or !$state.preferences.HasSeenIntroduction -or $state.introductionVisible -or $state.state -ne 'Hidden') -and [DateTime]::UtcNow -lt $deadline)
            if(!$state -or !$state.preferences.HasSeenIntroduction -or $state.introductionVisible -or $state.state -ne 'Hidden'){throw 'The introduction did not finish and hide.'}
            $results.Add(@{name='Unattended guide finishes and persists completion';pass=$true;build=$state.build})
        } else {
            Start-Sleep -Milliseconds 1400;$state=Read-State
            if(!$state.preferences.HasSeenIntroduction -or $state.introductionVisible -or $state.introductionPending){throw 'Introduction repeated after a normal restart.'}
            $results.Add(@{name='A new process does not repeat the completed guide';pass=$true;build=$state.build})
        }
        Stop-Owned;$owned=$null
    }
    @{package=(Split-Path $PackagePath -Leaf);checks=$results.Count;results=$results;verifiedAt=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content $ReceiptPath -Encoding UTF8
    Write-Output ('Passed '+$results.Count+' packaged introduction startup checks.')
} finally {
    Stop-Owned
    [IntroductionStartupInput]::Move($pointer.X,$pointer.Y)
    for($attempt=0;$attempt -lt 5 -and (Test-Path $work);$attempt++) {
        try {Remove-Item $work -Recurse -Force}
        catch {
            if($attempt -eq 4){throw}
            Start-Sleep -Milliseconds 250
        }
    }
}

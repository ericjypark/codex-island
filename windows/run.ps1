$ErrorActionPreference = 'Stop'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$root = Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype'
$dotnet = Join-Path $root 'dotnet\dotnet.exe'
if (!(Test-Path $dotnet)) {
    throw 'Install the .NET 10 ARM64 SDK in %LOCALAPPDATA%\CodexIslandPrototype\dotnet first. See README.md.'
}
$source = Join-Path $root 'src'
New-Item -ItemType Directory -Force $source | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'IslandPrototype\*') $source -Recurse -Force
$version = (Get-Content (Join-Path $PSScriptRoot "..\VERSION") -Raw).Trim()
& $dotnet publish (Join-Path $source 'IslandPrototype.csproj') -c Release -r win-arm64 --self-contained true -p:Version=$version -o (Join-Path $root 'staged-app') --nologo
if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }
New-Item -ItemType Directory -Force (Join-Path $root 'app') | Out-Null
Get-Process CodexIslandPrototype -ErrorAction SilentlyContinue | Stop-Process
Copy-Item (Join-Path $root 'staged-app\*') (Join-Path $root 'app') -Recurse -Force
$executable = Join-Path $root 'app\CodexIslandPrototype.exe'
$shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'CodexIsland Prototype.lnk'))
$shortcut.TargetPath = $executable
$shortcut.WorkingDirectory = Split-Path $executable
$shortcut.Save()
Start-Process $executable
Write-Output "Launched $executable"

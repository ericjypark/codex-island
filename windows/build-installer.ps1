param(
    [ValidateSet('win-x64','win-arm64')][string]$Runtime='win-arm64',
    [string]$Version,
    [string]$OutputDirectory,
    [ValidateSet('preview','stable')][string]$ReleaseChannel='preview',
    [switch]$Unsigned,
    [string]$AzureTrustedSignFile,
    [string]$PackageId='CodexIsland',
    [string]$TestFeed
)
$ErrorActionPreference='Stop'
$env:DOTNET_CLI_TELEMETRY_OPTOUT='1'
if(!$Version){$Version=(Get-Content (Join-Path $PSScriptRoot '..\VERSION') -Raw).Trim()}
if($Version -notmatch '^\d+\.\d+\.\d+$'){throw 'Version must have the form X.Y.Z.'}
if($PackageId -notmatch '^CodexIsland(?:\.UpdateTest[\w.]*)?$'){throw 'Use CodexIsland or a separate CodexIsland.UpdateTest package ID.'}
if($TestFeed -and $PackageId -eq 'CodexIsland'){throw 'A local test feed must never be embedded in a public installer.'}
if(!$TestFeed -and $PackageId -ne 'CodexIsland'){throw 'An update test package requires a local TestFeed.'}
if($Unsigned -and $AzureTrustedSignFile){throw 'Choose unsigned preview packaging or a signing identity.'}
if($Unsigned -and $ReleaseChannel -ne 'preview'){throw 'Unsigned installers are restricted to the preview channel.'}
if(!$Unsigned -and !$AzureTrustedSignFile){throw 'Provide AzureTrustedSignFile, or explicitly choose -Unsigned for a preview installer.'}
if($AzureTrustedSignFile -and !(Test-Path $AzureTrustedSignFile -PathType Leaf)){throw 'The signing metadata file does not exist.'}
$cache=Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype'
$portableDotnet=Join-Path $cache 'dotnet\dotnet.exe'
$dotnetCommand=Get-Command dotnet -ErrorAction SilentlyContinue
if($dotnetCommand){$dotnet=$dotnetCommand.Source}
elseif(Test-Path $portableDotnet){$dotnet=$portableDotnet;$env:DOTNET_ROOT=Split-Path $dotnet}
else{throw 'Install the .NET 10 SDK before building the Windows installer.'}
$vpkVersion='1.2.0'
$vpkRoot=Join-Path $cache ('vpk-'+$vpkVersion)
$vpk=Join-Path $vpkRoot 'vpk.exe'
if(!(Test-Path $vpk)){
    & $dotnet tool install vpk --version $vpkVersion --tool-path $vpkRoot
    if($LASTEXITCODE -ne 0){throw 'Velopack installation failed.'}
}
$channel=$Runtime+$(if($ReleaseChannel -eq 'preview'){'-preview'}else{''})
if(!$OutputDirectory){$OutputDirectory=Join-Path $PSScriptRoot ('artifacts\installers\'+$channel)}
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force $OutputDirectory|Out-Null
$work=Join-Path $cache ('installer-builds\'+[Guid]::NewGuid().ToString('N'))
$source=Join-Path $work 'source';$publish=Join-Path $work 'publish'
New-Item -ItemType Directory -Force $source|Out-Null
& robocopy (Join-Path $PSScriptRoot 'IslandPrototype') $source /E /XD bin obj /NFL /NDL /NJH /NJS /NP|Out-Null
if($LASTEXITCODE -ge 8){throw 'Could not stage installer source.'}
$properties=@(('-p:Version='+$Version),'-p:ContinuousIntegrationBuild=true','-p:DebugType=None')
if($TestFeed){$properties+=('-p:WindowsUpdateTestFeed='+[IO.Path]::GetFullPath($TestFeed))}
& $dotnet publish (Join-Path $source 'IslandPrototype.csproj') -c Release -r $Runtime --self-contained true @properties -o $publish --nologo
if($LASTEXITCODE -ne 0){throw 'Windows application publish failed.'}
$title=if($PackageId -eq 'CodexIsland'){'CodexIsland'}else{'CodexIsland Update Test '+$Runtime}
$pack=@('pack','--packId',$PackageId,'--packVersion',$Version,'--packDir',$publish,'--mainExe','CodexIslandPrototype.exe','--packTitle',$title,'--packAuthors','Eric Park','--runtime',$Runtime,'--channel',$channel,'--icon',(Join-Path $source 'Assets\CodexIsland.ico'),'--outputDir',$OutputDirectory,'--shortcuts','StartMenuRoot')
if($AzureTrustedSignFile){$pack+=@('--azureTrustedSignFile',[IO.Path]::GetFullPath($AzureTrustedSignFile))}
& $vpk @pack
if($LASTEXITCODE -ne 0){throw 'Windows installer packaging failed.'}
$setup=Get-Item (Join-Path $OutputDirectory ($PackageId+'-'+$channel+'-Setup.exe'))
$signature=Get-AuthenticodeSignature $setup.FullName
if(!$Unsigned -and $signature.Status -ne 'Valid'){throw 'The installer signature is not valid.'}
$manifest=[ordered]@{version=$Version;runtime=$Runtime;channel=$channel;packageId=$PackageId;unsigned=[bool]$Unsigned;installer=$setup.Name;sha256=(Get-FileHash $setup.FullName -Algorithm SHA256).Hash;selfContained=$true}
$manifest|ConvertTo-Json|Set-Content (Join-Path $OutputDirectory ('windows-'+$channel+'.json')) -Encoding UTF8
Write-Output ('Installer: '+$setup.FullName)
Write-Output ('Update channel: '+$channel)
Write-Output ('Signature: '+$signature.Status)

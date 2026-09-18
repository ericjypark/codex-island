param([Parameter(Mandatory=$true)][string]$Snapshot,[ValidateSet('NoEffects','Glass','Software')][string]$Mode='NoEffects')
$ErrorActionPreference='Stop'
$root=Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype'
$source=Join-Path $root ('graphics-effect-probe-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory $source|Out-Null
Copy-Item (Join-Path $PSScriptRoot '..\IslandPrototype\*') $source -Recurse -Force
if($Mode -eq 'NoEffects'){
$visual=Join-Path $source 'IslandVisual.cs';$text=[IO.File]::ReadAllText($visual)
$anchor='FrameDiagnostics.End(started,"island",Page,CounterProgress);'
if(!$text.Contains($anchor)){throw 'The probe insertion point changed.'}
[IO.File]::WriteAllText($visual,$text.Replace($anchor,'GraphicsEffectProbe.Remove(Window.GetWindow(this));'+[Environment]::NewLine+'        '+$anchor))
@'
using System.Windows;
using System.Windows.Media;
namespace IslandPrototype;
internal static class GraphicsEffectProbe {
 internal static void Remove(DependencyObject? node){
  if(node==null)return;
  if(node is UIElement element)element.Effect=null;else if(node is DrawingVisual drawing)drawing.Effect=null;
  for(int i=0;i<VisualTreeHelper.GetChildrenCount(node);i++)Remove(VisualTreeHelper.GetChild(node,i));
 }
}
'@|Set-Content (Join-Path $source 'GraphicsEffectProbe.cs')
}elseif($Mode -eq 'Software'){
 $main=Join-Path $source 'MainWindow.xaml.cs';$text=[IO.File]::ReadAllText($main)
 $anchor='source.AddHook(WindowMessage);';if(!$text.Contains($anchor)){throw 'The software probe insertion point changed.'}
 [IO.File]::WriteAllText($main,$text.Replace($anchor,$anchor+[Environment]::NewLine+'        source.CompositionTarget.RenderMode=RenderMode.SoftwareOnly;'))
}else{
 $xaml=Join-Path $source 'MainWindow.xaml';[IO.File]::WriteAllText($xaml,[IO.File]::ReadAllText($xaml).Replace('AllowsTransparency="True"','AllowsTransparency="False"'))
 $main=Join-Path $source 'MainWindow.xaml.cs';$text=[IO.File]::ReadAllText($main)
 $anchor='source.AddHook(WindowMessage);';if(!$text.Contains($anchor)){throw 'The glass probe insertion point changed.'}
 [IO.File]::WriteAllText($main,$text.Replace($anchor,$anchor+[Environment]::NewLine+'        GlassPresentationProbe.Apply(source);'))
 @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Interop;
using System.Windows.Media;
namespace IslandPrototype;
internal static class GlassPresentationProbe {
 [StructLayout(LayoutKind.Sequential)]private struct Margins{internal int Left,Right,Top,Bottom;}
 [DllImport("dwmapi.dll")]private static extern int DwmExtendFrameIntoClientArea(IntPtr window,ref Margins margins);
 internal static void Apply(HwndSource source){source.CompositionTarget.BackgroundColor=Colors.Transparent;var margins=new Margins{Left=-1,Right=-1,Top=-1,Bottom=-1};int result=DwmExtendFrameIntoClientArea(source.Handle,ref margins);if(result!=0)throw new InvalidOperationException("DWM extension failed: "+result);}
}
'@|Set-Content (Join-Path $source 'GlassPresentationProbe.cs')
}
$output=Join-Path $source 'app';$version=(Get-Content (Join-Path $PSScriptRoot '..\..\VERSION') -Raw).Trim()
& (Join-Path $root 'dotnet\dotnet.exe') publish (Join-Path $source 'IslandPrototype.csproj') -c Release -r win-arm64 --self-contained true -p:Version=$version -o $output --nologo
if($LASTEXITCODE -ne 0){throw 'The isolated graphics probe did not build.'}
$name=switch($Mode){'NoEffects'{'pointer-no-effects'}'Software'{'pointer-software'}default{'pointer-glass'}}
& (Join-Path $PSScriptRoot 'measure-live-responsiveness.ps1') -Snapshot $Snapshot -Name $name -PointerOnly -RawClicks -ProbeExecutable (Join-Path $output 'CodexIslandPrototype.exe')

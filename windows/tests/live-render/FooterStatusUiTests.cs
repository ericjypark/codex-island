using System;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using IslandPrototype;

internal static class FooterStatusUiTests
{
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr h,out NativeRect rect);
    [StructLayout(LayoutKind.Sequential)] private struct NativeRect {public int Left,Top,Right,Bottom;}
    internal static async Task Run(string output,Action<string,bool> check)
    {
        var observed=DateTimeOffset.UtcNow.AddMinutes(-3);var client=new Client();
        using var feed=new UsageFeed(new LiveUsageCoordinator(client,()=>observed));feed.Select(["codex"]);await feed.RefreshAsync(true);
        var surface=new IslandVisual {Width=800,Height=226,Expanded=true,Page=0,ContentOpacity=1,LogoOpacity=0,PillOpacity=0,HasCycled=true,Feed=feed,Preferences=new IslandPreferences {LeftProvider="codex",RightProvider=null}};
        var window=new Window {Width=800,Height=226,Left=100,Top=150,WindowStyle=WindowStyle.None,AllowsTransparency=true,Background=Brushes.Transparent,ShowInTaskbar=false,Topmost=true,Content=surface};
        int refreshes=0;surface.RefreshRequested+=()=>refreshes++;
        window.Show();
        async Task Capture(string name) {
            await Task.Delay(200);GetWindowRect(new System.Windows.Interop.WindowInteropHelper(window).Handle,out var rect);
            using var bitmap=new System.Drawing.Bitmap(rect.Right-rect.Left,rect.Bottom-rect.Top);
            using(var graphics=System.Drawing.Graphics.FromImage(bitmap))graphics.CopyFromScreen(rect.Left,rect.Top,0,0,bitmap.Size);
            bitmap.Save(Path.Combine(output,"footer-"+name+"-windows.png"));
        }
        try {
            var face=(Typeface)typeof(FooterStatusLayer).GetField("labelFace",System.Reflection.BindingFlags.NonPublic|System.Reflection.BindingFlags.Static)!.GetValue(null)!;
            bool resolved=face.TryGetGlyphTypeface(out var glyph);
            check("Footer resolves the embedded status face instead of a system fallback",resolved&&glyph!.FontUri.ToString().Contains("IslandText-Status",StringComparison.OrdinalIgnoreCase));
            surface.InvalidateVisual();await Capture("synced");
            check("Footer renders a green live status and a separate elapsed age",surface.StatusControl.Spoken=="Synced 3m ago"&&surface.StatusControl.ClockRunning&&surface.StatusControl.PulseRunning);
            using(var bitmap=new System.Drawing.Bitmap(Path.Combine(output,"footer-synced-windows.png"))) {
                double scale=bitmap.Width/800.0;int green=0;
                for(int y=(int)(194*scale);y<215*scale;y++)for(int x=(int)(640*scale);x<775*scale;x++){var p=bitmap.GetPixel(x,y);if(p.G>100&&p.G>p.R*1.7&&p.G>p.B*1.2)green++;}
                check("Native footer capture contains the teal status dot",green>12);
            }
            var control=surface.StatusControl;var bounds=control.Bounds;
            control.SetPointer(new Point(bounds.X+bounds.Width/2,bounds.Y+bounds.Height/2));await Capture("hover");
            check("Clicking the complete status group requests one refresh",surface.ActivateAt(new Point(bounds.Right-2,bounds.Y+8))&&refreshes==1);
            control.SetPointer(null);surface.FocusTarget(FooterStatusLayer.TargetId);await Capture("focus");
            check("Keyboard activation refreshes the focused status control",surface.ActivateFocused()&&refreshes==2);
            observed=DateTimeOffset.UtcNow.AddSeconds(-10);await feed.RefreshPageAsync(0);surface.InvalidateVisual();await Task.Delay(200);
            string before=control.Spoken;int draws=control.TextDrawCount,rootDraws=surface.RenderCount;await Task.Delay(1200);
            check("Elapsed time advances without a provider request or island redraw",control.Spoken!=before&&control.TextDrawCount>draws&&client.Calls==2&&surface.RenderCount==rootDraws);
            var stale=surface.AccessibleTargets.Single(t=>t.Help==FooterStatusLayer.TargetId);
            client.Pending=new(TaskCreationOptions.RunContinuationsAsynchronously);var pending=feed.RefreshPageAsync(0);await Task.Delay(30);surface.InvalidateVisual();await Capture("syncing");
            stale.Action();
            check("Syncing disables both current and retained refresh actions",control.Loading&&!surface.TargetEnabled(FooterStatusLayer.TargetId)&&!surface.ActivateFocused()&&refreshes==2&&!control.ClockRunning&&!control.PulseRunning);
            client.Pending.SetResult(new(UsageStatus.Ready,[new("5h",42,DateTimeOffset.UtcNow.AddHours(3))]));await pending;surface.InvalidateVisual();await Task.Delay(100);
            surface.ReduceMotion=true;
            check("Reduce Motion stops the dot animation while retaining elapsed time",!control.PulseRunning&&control.ClockRunning);
            surface.ReduceMotion=false;surface.LowPower=true;
            check("Low Power stops the footer pulse immediately",!control.PulseRunning&&control.ClockRunning);
            surface.LowPower=false;surface.AmbientVisible=false;
            check("A suppressed island stops the footer clock and pulse",!control.ClockRunning&&!control.PulseRunning);
            surface.AmbientVisible=true;
            check("Returning to a visible island resumes its live status",control.ClockRunning&&control.PulseRunning);
            surface.Expanded=false;surface.ContentOpacity=.5;surface.InvalidateVisual();await Task.Delay(50);
            check("The footer fades with the departing content after its clock stops",control.Opacity==.5&&!control.ClockRunning&&!control.PulseRunning);
            surface.ContentOpacity=0;surface.InvalidateVisual();await Task.Delay(100);
            check("A collapsed island releases all footer animation clocks",!control.ClockRunning&&!control.PulseRunning);
            surface.Expanded=true;surface.ContentOpacity=1;surface.Feed=new UsageFeed(new LiveUsageCoordinator(new Client()));surface.InvalidateVisual();await Capture("idle");
            check("A provider with no successful reading displays Idle",control.Spoken=="Idle"&&!control.ClockRunning&&!control.PulseRunning);
            surface.Preferences=surface.Preferences with {LeftProvider="grok"};surface.InvalidateVisual();await Capture("connection");
            check("A disconnected provider displays Check connection",control.Spoken=="Check connection"&&!control.PulseRunning);
            surface.Feed.Dispose();
            Localizer.Language="zh-Hans";surface.Feed=feed;surface.Preferences=surface.Preferences with{LeftProvider="codex"};surface.InvalidateVisual();await Capture("chinese");
            check("Chinese footer localizes its label and relative age",control.Spoken.StartsWith("已同步 ")&&control.Spoken.EndsWith("秒前"));
        } finally{Localizer.Language="en";window.Close();}
        check("Closing the native window stops the footer clock",!surface.StatusControl.ClockRunning&&!surface.StatusControl.PulseRunning);
    }
    private sealed class Client:IUsageClient
    {
        internal int Calls;internal TaskCompletionSource<UsageResult>? Pending;
        public Task<UsageResult> FetchAsync(string provider,CancellationToken token){Calls++;return Pending?.Task??Task.FromResult(new UsageResult(UsageStatus.Ready,[new("5h",42,DateTimeOffset.UtcNow.AddHours(3))]));}
    }
}

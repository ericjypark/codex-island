using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using IslandPrototype;

internal static class Program
{
    [DllImport("user32.dll")]private static extern bool SetCursorPos(int x,int y);
    [STAThread] private static int Main(string[] args)
    {
        var app=new Application();int code=0;
        app.Startup+=async(_,_)=>{try{await Run(args[0]);}catch(Exception e){Console.Error.WriteLine(e);code=1;}finally{app.Shutdown();}};
        app.Run();return code;
    }
    private static async Task Run(string output)
    {
        var checks=new List<object>();bool passed=true;
        void Check(string name,bool pass,object? details=null){checks.Add(new {check=name,pass,details});passed&=pass;Console.WriteLine((pass?"PASS: ":"FAIL: ")+name+" "+JsonSerializer.Serialize(details));}
        var surface=new IslandVisual{Width=800,Height=277,Expanded=true,Page=2,PagePosition=2,ContentOpacity=1,LogoOpacity=0,PillOpacity=0,SwapOpacity=1,CounterProgress=1};
        var window=new Window{Width=800,Height=277,Left=100,Top=200,WindowStyle=WindowStyle.None,AllowsTransparency=true,Background=Brushes.Transparent,Topmost=true,ShowInTaskbar=false,Content=surface};
        window.Show();
        try {
            await Task.Delay(500);int before=surface.OverviewBuildCount,targets=surface.AccessibleTargets.Length;
            var dpi=VisualTreeHelper.GetDpi(surface);RenderTargetBitmap Capture(){var image=new RenderTargetBitmap((int)(800*dpi.DpiScaleX),(int)(277*dpi.DpiScaleY),dpi.PixelsPerInchX,dpi.PixelsPerInchY,PixelFormats.Pbgra32);image.Render(surface);return image;}
            byte[] Pixels(BitmapSource image){var bytes=new byte[image.PixelWidth*image.PixelHeight*4];image.CopyPixels(bytes,image.PixelWidth*4,0);return bytes;}
            var original=Pixels(Capture());
            surface.Page=1;surface.BeginAnimation(IslandVisual.PagePositionProperty,ParityTheme.Ease(1,.36,page:true));await Task.Delay(500);
            surface.Page=2;surface.BeginAnimation(IslandVisual.PagePositionProperty,ParityTheme.Ease(2,.36,page:true));await Task.Delay(500);
            int after=surface.OverviewBuildCount;
            Check("Sliding away and back reuses the unchanged Overview drawing",after==before,new{before,after});
            Check("A retained calendar restores every interactive target after sliding",surface.AccessibleTargets.Length==targets,new{before=targets,after=surface.AccessibleTargets.Length});
            Check("Settled pixels remain unchanged after a page round trip",Pixels(Capture()).SequenceEqual(original));
            var day=surface.AccessibleTargets.First(t=>t.Help.Contains(": ")&&t.Help.EndsWith(" tokens"));day.Action();await Task.Delay(730);
            Check("Selecting a day invalidates the retained calendar",surface.OverviewBuildCount==after+1&&surface.SelectedDay.HasValue,new{before=after,after=surface.OverviewBuildCount});
            int selected=surface.OverviewBuildCount;surface.ClearSelection();await Task.Delay(100);
            Check("Clearing the selection refreshes the retained calendar",surface.OverviewBuildCount==selected+1&&surface.SelectedDay==null);
            async Task Move(Point point){var screen=surface.PointToScreen(point);SetCursorPos((int)screen.X,(int)screen.Y);await Task.Delay(160);}
            await Move(new Point(400,25));await Task.Delay(250);
            int hoverBuilds=surface.OverviewBuildCount,hoverRenders=surface.RenderCount;
            foreach(var point in new[]{new Point(35,255),new Point(700,255),new Point(400,25)})await Move(point);
            Check("Hovering footer controls retains the calendar and page drawing",surface.OverviewBuildCount==hoverBuilds&&surface.RenderCount==hoverRenders,new{beforeBuilds=hoverBuilds,afterBuilds=surface.OverviewBuildCount,beforeRenders=hoverRenders,afterRenders=surface.RenderCount});
            var days=surface.AccessibleTargets.Where(t=>t.Help.Contains(": ")&&t.Help.EndsWith(" tokens")).Take(6).ToArray();
            hoverBuilds=surface.OverviewBuildCount;hoverRenders=surface.RenderCount;
            await Move(new Point(days[0].Bounds.X+5,days[0].Bounds.Y+5));var hovered=Pixels(Capture());
            foreach(var target in days.Skip(1))await Move(new Point(target.Bounds.X+5,target.Bounds.Y+5));
            await Move(new Point(400,25));
            Check("Calendar hover changes pixels without rebuilding cells or the page",!hovered.SequenceEqual(Pixels(Capture()))&&surface.OverviewBuildCount==hoverBuilds&&surface.RenderCount==hoverRenders,new{beforeBuilds=hoverBuilds,afterBuilds=surface.OverviewBuildCount,beforeRenders=hoverRenders,afterRenders=surface.RenderCount});
            surface.FocusTarget("Overview (Ctrl+3)");await Task.Delay(100);
            Check("Keyboard navigation keeps a visible focus target",surface.FocusedTarget=="Overview (Ctrl+3)"&&surface.IsKeyboardFocusWithin);
            await Move(new Point(35,255));
            Check("Returning to pointer input clears the previous keyboard ring",surface.FocusedTarget==null);
            surface.FocusNext(false);await Task.Delay(80);
            Check("Tab navigation restores keyboard focus after pointer input",surface.FocusedTarget!=null&&surface.IsKeyboardFocusWithin);
            if(DateTime.Now.Second>55)await Task.Delay((61-DateTime.Now.Second)*1000);
            surface.BeginAnimation(IslandVisual.PagePositionProperty,null);
            surface.Page=1;surface.PagePosition=1;surface.InvalidateVisual();await Task.Delay(120);
            surface.Page=0;surface.PagePosition=0;surface.InvalidateVisual();await Task.Delay(120);
            surface.InvalidateVisual();await Task.Delay(50);
            int usageBuilds=surface.UsageBuildCount,costBuilds=surface.CostBuildCount;
            var usagePixels=Pixels(Capture());
            surface.Page=1;surface.BeginAnimation(IslandVisual.PagePositionProperty,ParityTheme.Ease(1,.36,page:true));await Task.Delay(450);
            surface.Page=0;surface.BeginAnimation(IslandVisual.PagePositionProperty,ParityTheme.Ease(0,.36,page:true));await Task.Delay(450);
            Check("Usage and Cost retain their drawing through page motion",surface.UsageBuildCount==usageBuilds&&surface.CostBuildCount==costBuilds,new{usageBefore=usageBuilds,usageAfter=surface.UsageBuildCount,costBefore=costBuilds,costAfter=surface.CostBuildCount});
            Check("Retaining page content preserves settled Usage pixels",Pixels(Capture()).SequenceEqual(usagePixels));
            using var expiring=new UsageFeed(new LiveUsageCoordinator(new ExpiringClient()));expiring.Select(["codex"]);await expiring.RefreshAsync(true);
            surface.Feed=expiring;surface.Preferences=surface.Preferences with{LeftProvider="codex",RightProvider=null};surface.InvalidateVisual();await Task.Delay(180);
            int beforeExpiry=surface.UsageBuildCount;bool hadReading=surface.AccessibleDescription.Contains("42%");await Task.Delay(1400);
            surface.InvalidateVisual();await Task.Delay(80);
            Check("A retained quota disappears as soon as its window expires",hadReading&&surface.AccessibleDescription.Contains("no reading")&&surface.UsageBuildCount==beforeExpiry+1,new{before=beforeExpiry,after=surface.UsageBuildCount});
            string directory=Path.GetDirectoryName(output)!;Directory.CreateDirectory(directory);
            var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(Capture()));using(var stream=File.Create(Path.Combine(directory,"swipe-render-calendar.png")))encoder.Save(stream);
            File.WriteAllText(output,JsonSerializer.Serialize(new{build=typeof(IslandVisual).Assembly.ManifestModule.ModuleVersionId,checks},new JsonSerializerOptions{WriteIndented=true}));
            if(!passed)throw new InvalidOperationException("Overview rendering regression failed.");
        }finally{window.Close();}
    }
    private sealed class ExpiringClient:IUsageClient
    {
        public Task<UsageResult> FetchAsync(string provider,CancellationToken cancellation)=>Task.FromResult(new UsageResult(UsageStatus.Ready,[new("5h",42,DateTimeOffset.UtcNow.AddSeconds(1.2))]));
    }
}

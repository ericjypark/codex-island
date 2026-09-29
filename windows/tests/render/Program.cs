using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using IslandPrototype;

internal static class Program
{
    private sealed record Tick(double At,double Progress);
    private static readonly List<object> results=new();
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr h,out NativeRect rect);
    [StructLayout(LayoutKind.Sequential)] private struct NativeRect {public int Left,Top,Right,Bottom;}
    [STAThread]
    private static int Main(string[] args)
    {
        var app=new Application();
        int exitCode=0;
        app.Startup+=async(_,_)=>{
            try {await Run(args[0],args.Contains("--probe-cache"));}
            catch(Exception error){Console.Error.WriteLine(error);exitCode=1;}
            finally{app.Shutdown();}
        };
        app.Run();return exitCode;
    }

    private static async Task Run(string output,bool probeCache)
    {
        var surface=new IslandVisual {Width=800,Height=226,Expanded=true,Page=1,PagePosition=1,ContentOpacity=1,LogoOpacity=0,PillOpacity=0};
        var window=new Window {Width=800,Height=226,Left=100,Top=100,WindowStyle=WindowStyle.None,AllowsTransparency=true,Background=Brushes.Transparent,ShowInTaskbar=false,Topmost=true,Content=surface};
        window.Show();
        await Task.Delay(750);
        var watch=new Stopwatch();
        var ticks=new List<Tick>();
        var descriptor=DependencyPropertyDescriptor.FromProperty(IslandVisual.CounterProgressProperty,typeof(IslandVisual));
        EventHandler changed=(_,_)=>ticks.Add(new(watch.Elapsed.TotalMilliseconds,surface.CounterProgress));
        descriptor.AddValueChanged(surface,changed);
        try {
            foreach(bool beginsLow in new[]{false,true}) {
                surface.LowPower=beginsLow;ticks.Clear();watch.Restart();surface.StartCounter(false);
                await Task.Delay(150);
                double switchedAt=watch.Elapsed.TotalMilliseconds, before=surface.CounterProgress;
                surface.LowPower=!beginsLow;
                double after=surface.CounterProgress;
                await Task.Delay(580);watch.Stop();
                var middle=ticks.Where(t=>t.At>switchedAt+55&&t.At<switchedAt+335&&t.Progress<1).ToArray();
                var intervals=middle.Zip(middle.Skip(1),(a,b)=>b.At-a.At).Where(ms=>ms>1).Order().ToArray();
                double median=intervals.Length==0?0:intervals[intervals.Length/2];
                bool monotonic=ticks.Zip(ticks.Skip(1),(a,b)=>b.Progress+.00001>=a.Progress).All(x=>x);
                bool cadence=beginsLow?median>0&&median<26:median>=26&&median<50;
                double settledAt=ticks.FirstOrDefault(t=>t.Progress==1)?.At??double.PositiveInfinity;
                bool pass=cadence&&monotonic&&after+.00001>=before&&surface.CounterProgress==1&&settledAt is >=580 and <=730;
                var result=new {check=beginsLow?"Disabling Low Power during count-up restores cadence":"Enabling Low Power during count-up limits cadence",pass,
                    switchedAt,before,after,settledAt,medianIntervalMs=median,observedTicks=middle.Length,monotonic,finalProgress=surface.CounterProgress,
                    build=typeof(IslandVisual).Assembly.ManifestModule.ModuleVersionId,ticks};
                results.Add(JsonSerializer.SerializeToElement(result));
                File.WriteAllText(output,JsonSerializer.Serialize(results,new JsonSerializerOptions {WriteIndented=true}));
                Console.WriteLine($"{(pass?"PASS":"FAIL")} {result.check}: median {median:0.0} ms, {middle.Length} ticks");
                await Task.Delay(250);
            }
            surface.StartCounter(true);
            bool reduced=surface.CounterProgress==1;
            Console.WriteLine($"{(reduced?"PASS":"FAIL")} Reduced motion settles without a counter animation");
            results.Add(JsonSerializer.SerializeToElement(new {check="Reduced motion settles immediately",pass=reduced}));
            int settledTicks=ticks.Count;await Task.Delay(120);
            results.Add(JsonSerializer.SerializeToElement(new {check="Settled count-up stops changing values",pass=ticks.Count==settledTicks}));
            var grid=new System.Windows.Controls.Grid();
            grid.ColumnDefinitions.Add(new());grid.ColumnDefinitions.Add(new());
            IslandVisual Panel()=>new() {Width=800,Height=277,Expanded=true,Page=2,PagePosition=2,ContentOpacity=1,LogoOpacity=0,PillOpacity=0,CounterProgress=1};
            var direct=Panel();direct.CacheMode=null;
            var cached=Panel();System.Windows.Controls.Grid.SetColumn(cached,1);
            grid.Children.Add(direct);grid.Children.Add(cached);
            window.Content=grid;window.Width=1600;window.Height=277;window.Left=50;window.Top=350;
            await Task.Delay(900);
            void RemoveCaches(Visual visual) {
                if(visual is UIElement element)element.CacheMode=null;
                if(visual is ContainerVisual container)container.CacheMode=null;
                for(int i=0;i<VisualTreeHelper.GetChildrenCount(visual);i++)RemoveCaches((Visual)VisualTreeHelper.GetChild(visual,i));
            }
            RemoveCaches(direct);
            var restoreCaches=new List<Action>();
            void RememberCaches(Visual visual) {
                if(visual is UIElement element){var cache=element.CacheMode;restoreCaches.Add(()=>element.CacheMode=cache);}
                if(visual is ContainerVisual container){var cache=container.CacheMode;restoreCaches.Add(()=>container.CacheMode=cache);}
                for(int i=0;i<VisualTreeHelper.GetChildrenCount(visual);i++)RememberCaches((Visual)VisualTreeHelper.GetChild(visual,i));
            }
            RememberCaches(cached);
            GetWindowRect(new System.Windows.Interop.WindowInteropHelper(window).Handle,out var rect);
            double scale=VisualTreeHelper.GetDpi(cached).DpiScaleX;
            int width=(int)Math.Round(800*scale),height=(int)Math.Round(277*scale);
            CacheMode? productionCache=cached.CacheMode;
            foreach(string mode in probeCache?new[]{"uncached-control","default","nearest","supersample"}:new[]{"uncached-control","current"}) {
                foreach(var restore in restoreCaches)restore();
                if(mode=="uncached-control")RemoveCaches(cached);
                cached.CacheMode=mode=="current"?productionCache:mode=="uncached-control"?null:new BitmapCache {RenderAtScale=mode=="supersample"?scale*2:scale};
                RenderOptions.SetBitmapScalingMode(cached,mode=="nearest"?BitmapScalingMode.NearestNeighbor:BitmapScalingMode.Unspecified);
                await Task.Delay(350);
                using var pixels=new System.Drawing.Bitmap(width*2,height);
                using(var graphics=System.Drawing.Graphics.FromImage(pixels))graphics.CopyFromScreen(rect.Left,rect.Top,0,0,pixels.Size);
                pixels.Save(Path.Combine(Path.GetDirectoryName(output)!,"cache-ab-"+mode+".png"),System.Drawing.Imaging.ImageFormat.Png);
                int margin=(int)Math.Ceiling(16*scale),different=0,total=0,maxChannelError=0,textMaxError=0;long error=0;
                for(int y=margin;y<height-margin;y++)for(int x=margin;x<width-margin;x++){
                    var a=pixels.GetPixel(x,y);var b=pixels.GetPixel(x+width,y);total++;
                    if(a!=b)different++;
                    int r=Math.Abs(a.R-b.R),g=Math.Abs(a.G-b.G),bError=Math.Abs(a.B-b.B);
                    error+=r+g+bError;maxChannelError=Math.Max(maxChannelError,Math.Max(r,Math.Max(g,bError)));
                    if(y<118*scale||y>=216*scale)textMaxError=Math.Max(textMaxError,Math.Max(r,Math.Max(g,bError)));
                }
                int interiorMaxError=0;
                for(int col=0;col<53;col++)for(int row=0;row<7;row++)for(int dy=-2;dy<=2;dy++)for(int dx=-2;dx<=2;dx++){
                    int x=(int)Math.Round((16+col*13.95+5.8)*scale)+dx,y=(int)Math.Round((119+row*13.95+5.8)*scale)+dy;
                    var a=pixels.GetPixel(x,y);var b=pixels.GetPixel(x+width,y);
                    interiorMaxError=Math.Max(interiorMaxError,Math.Max(Math.Abs(a.R-b.R),Math.Max(Math.Abs(a.G-b.G),Math.Abs(a.B-b.B))));
                }
                bool pass=mode=="uncached-control"?maxChannelError<=1:textMaxError<=1&&interiorMaxError<=1;
                var raster=new {check="Text and calendar fill pixels retain native rendering",mode,pass,different,total,maxChannelError,textMaxError,interiorMaxError,
                    calendarEdgeAntialiasingDiffers=maxChannelError>1,meanChannelError=(double)error/(3*total),scale};
                results.Add(JsonSerializer.SerializeToElement(raster));
                Console.WriteLine($"{(raster.pass?"PASS":"FAIL")} Cache raster {mode}: {different}/{total} changed pixels, mean error {raster.meanChannelError:0.0000}");
            }
            File.WriteAllText(output,JsonSerializer.Serialize(results,new JsonSerializerOptions {WriteIndented=true}));
            if(results.Cast<JsonElement>().Any(r=>!r.GetProperty("pass").GetBoolean()))throw new InvalidOperationException("Rendering checks failed.");
        } finally {descriptor.RemoveValueChanged(surface,changed);window.Close();}
    }
}

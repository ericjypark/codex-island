using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation.Peers;
using System.Windows.Automation.Provider;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using IslandPrototype;

internal static class PillTests
{
    [DllImport("dwmapi.dll")] private static extern int DwmFlush();
    internal static async Task Run(string output)
    {
        Directory.CreateDirectory(output);
        var results=new List<object>();int failures=0;
        void Check(string name,bool pass){results.Add(new {name,pass});Console.WriteLine((pass?"PASS ":"FAIL ")+name);if(!pass)failures++;}
        var client=new Client();
        using var feed=new UsageFeed(new LiveUsageCoordinator(client));
        var preferences=new IslandPreferences {LeftProvider="claude",RightProvider="codex",Remaining=false};
        feed.Preferences=preferences;feed.Select(preferences.SelectedProviders);
        var surface=new IslandVisual {Width=ParityTheme.PillWidth(2),Height=52,Expanded=false,PillShape=1,PillOpacity=1,LogoOpacity=0,ContentOpacity=0,Preferences=preferences,Feed=feed};
        var host=new Border {Padding=new Thickness(32),Child=surface,Background=new SolidColorBrush(Color.FromRgb(38,46,62))};
        var window=new Window {SizeToContent=SizeToContent.WidthAndHeight,Left=100,Top=260,WindowStyle=WindowStyle.None,ResizeMode=ResizeMode.NoResize,ShowInTaskbar=false,ShowActivated=false,Topmost=true,Content=host};
        window.Show();
        BitmapSource Raster(double scale) {
            surface.UpdateLayout();
            var bitmap=new RenderTargetBitmap((int)Math.Round(host.ActualWidth*scale),(int)Math.Round(host.ActualHeight*scale),96*scale,96*scale,PixelFormats.Pbgra32);
            bitmap.Render(host);
            var origin=surface.TranslatePoint(new Point(),host);
            return new CroppedBitmap(bitmap,new Int32Rect((int)Math.Round(origin.X*scale),(int)Math.Round(origin.Y*scale),(int)Math.Round(surface.Width*scale),(int)Math.Round(surface.Height*scale)));
        }
        void Save(BitmapSource bitmap,string name){var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));using var file=File.Create(Path.Combine(output,name+".png"));encoder.Save(file);}
        byte[] Pixels(BitmapSource bitmap){var data=new byte[bitmap.PixelWidth*bitmap.PixelHeight*4];bitmap.CopyPixels(data,bitmap.PixelWidth*4,0);return data;}
        bool Lit(byte[] pixels,int width,double x,double y,double scale) {
            for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++) {
                int i=(((int)Math.Round(y*scale)+dy)*width+(int)Math.Round(x*scale)+dx)*4;
                if(i>=0&&i+3<pixels.Length&&Math.Max(pixels[i],Math.Max(pixels[i+1],pixels[i+2]))>120)return true;
            }
            return false;
        }
        try {
            var expanded=ParityTheme.Silhouette(800,277);
            Check("The expanded outline retains the Mac's flat upper corners",expanded.FillContains(new Point(.5,.5))&&expanded.FillContains(new Point(799.5,.5)));
            Check("The expanded outline retains rounded lower corners",!expanded.FillContains(new Point(.5,276.5))&&expanded.FillContains(new Point(400,276.5)));
            double ringX=PillMotion.IconCenter(surface.Width,2,0,0).X;
            byte[]? missing=null,zero=null;
            foreach(double? value in new double?[]{null,0,25,100}) {
                client.Used=value;await feed.RefreshAsync(true);surface.InvalidateVisual();await Task.Delay(80);
                var bitmap=Raster(2);string name=value?.ToString("0")??"missing";Save(bitmap,"rings-"+name);
                var pixels=Pixels(bitmap);
                if(value==null)missing=pixels;
                if(value==0)zero=pixels;
                if(value==100)Check("100 percent closes the full ring",Enumerable.Range(0,16).All(i=>Lit(pixels,bitmap.PixelWidth,ringX+Math.Sin(i*Math.PI/8)*15.25,26-Math.Cos(i*Math.PI/8)*15.25,2)));
                if(value==0)Check("A real zero has no bright progress arc",!Lit(pixels,bitmap.PixelWidth,ringX,10.75,2));
                if(value==25)Check("A quarter ring fills clockwise from the top",Lit(pixels,bitmap.PixelWidth,ringX+15.25,26,2)&&!Lit(pixels,bitmap.PixelWidth,ringX-15.25,26,2));
                Check("Reading "+name+" remains distinct in accessibility",surface.AccessibleDescription.Contains(value==null?"5h no reading":$"5h {value:0}% used"));
            }
            Check("Missing quota is visually distinct from zero",missing!=null&&zero!=null&&!missing.SequenceEqual(zero));
            client.Used=25;await feed.RefreshAsync(true);surface.Remaining=true;surface.InvalidateVisual();await Task.Delay(80);
            var remaining=Raster(2);Save(remaining,"rings-remaining");
            Check("Remaining mode fills three quarters for 25 percent used",Lit(Pixels(remaining),remaining.PixelWidth,ringX-15.25,26,2)&&surface.AccessibleDescription.Contains("75% remaining"));
            surface.Remaining=false;
            client.Used=100;client.ResetHours=167;await feed.RefreshAsync(true);surface.InvalidateVisual();await Task.Delay(80);
            Save(Raster(2),"pill-long-reset-200");
            client.Used=25;client.ResetHours=3;await feed.RefreshAsync(true);

            foreach(double scale in new[]{1,1.25,1.5,2}) {
                surface.InvalidateVisual();await Task.Delay(40);
                var bitmap=Raster(scale);Save(bitmap,"pill-dual-"+(int)(scale*100));
                var pixels=Pixels(bitmap);
                Check($"{scale*100:0}% scale keeps rounded corners outside the black capsule",pixels[0]>0&&pixels[(bitmap.PixelWidth-1)*4]>0&&pixels[(bitmap.PixelHeight-1)*bitmap.PixelWidth*4]>0);
            }
            surface.Preferences=preferences with {RightProvider=null};surface.Width=ParityTheme.PillWidth(1);surface.InvalidateVisual();await Task.Delay(80);
            Save(Raster(2),"pill-single-200");
            Check("One provider is centered without a vacant second slot",surface.AccessibleDescription.Contains("Claude")&&!surface.AccessibleDescription.Contains("Codex:"));
            var peer=UIElementAutomationPeer.CreatePeerForElement(surface);
            int invoked=0;surface.ExpansionRequested+=()=>invoked++;
            (peer?.GetPattern(PatternInterface.Invoke) as IInvokeProvider)?.Invoke();await Task.Delay(40);
            Check("The collapsed pill exposes an accessible open action",invoked==1&&peer?.GetAutomationControlType()==AutomationControlType.Button);
            surface.Preferences=preferences;surface.Width=ParityTheme.PillWidth(2);surface.InvalidateVisual();await Task.Delay(200);DwmFlush();
            var origin=host.PointToScreen(new Point());double dpi=VisualTreeHelper.GetDpi(host).DpiScaleX;
            using(var capture=new System.Drawing.Bitmap((int)Math.Round(host.ActualWidth*dpi),(int)Math.Round(host.ActualHeight*dpi))) {
                using(var graphics=System.Drawing.Graphics.FromImage(capture))graphics.CopyFromScreen((int)origin.X,(int)origin.Y,0,0,capture.Size);
                capture.Save(Path.Combine(output,"pill-native.png"),System.Drawing.Imaging.ImageFormat.Png);
            }
            File.WriteAllText(Path.Combine(output,"results.json"),JsonSerializer.Serialize(new {build=typeof(IslandVisual).Assembly.ManifestModule.ModuleVersionId,liveScale=dpi,failures,results},new JsonSerializerOptions {WriteIndented=true}));
            await PillMotionTests.Run(surface,host,window,output);
        } finally {window.Close();}
        if(failures>0)throw new Exception($"{failures} pill checks failed.");
    }

    private sealed class Client:IUsageClient
    {
        public double? Used=25;
        public double ResetHours=3;
        public Task<UsageResult> FetchAsync(string provider,CancellationToken cancellation)=>Task.FromResult(new UsageResult(UsageStatus.Ready,
            [new LiveWindow("5h",provider=="claude"?Used:68,DateTimeOffset.UtcNow.AddHours(ResetHours),Kind:0)],"Test","pill-fixture-"+provider));
    }
}

using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using IslandPrototype;

internal static class Program
{
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr h,out NativeRect rect);
    [StructLayout(LayoutKind.Sequential)] private struct NativeRect {public int Left,Top,Right,Bottom;}
    [STAThread] private static int Main(string[] args)
    {
        var app=new Application();int exit=0;
        app.Startup+=async(_,_)=>{try{if(Array.IndexOf(args,"--pill-only")>=0)await PillTests.Run(args[0]);else await Run(args[0]);}catch(Exception error){Console.Error.WriteLine(error);exit=1;}finally{app.Shutdown();}};
        app.Run();return exit;
    }
    private static async Task Run(string directory)
    {
        Directory.CreateDirectory(directory);
        var surface=new IslandVisual {Width=800,Height=226,Expanded=true,ContentOpacity=1,LogoOpacity=0,PillOpacity=0,HasCycled=true};
        var window=new Window {Width=800,Height=226,Left=70,Top=110,WindowStyle=WindowStyle.None,AllowsTransparency=true,Background=Brushes.Black,ShowInTaskbar=false,Topmost=true,Content=surface};
        window.Show();var captures=new List<object>();
        async Task Capture(string name)
        {
            surface.InvalidateVisual();await Task.Delay(300);
            GetWindowRect(new System.Windows.Interop.WindowInteropHelper(window).Handle,out var rect);
            double scale=VisualTreeHelper.GetDpi(surface).DpiScaleX;
            using var bitmap=new System.Drawing.Bitmap((int)Math.Round(surface.Width*scale),(int)Math.Round(surface.Height*scale));
            using(var graphics=System.Drawing.Graphics.FromImage(bitmap))graphics.CopyFromScreen(rect.Left,rect.Top,0,0,bitmap.Size);
            bitmap.Save(Path.Combine(directory,"win-"+name+".png"),System.Drawing.Imaging.ImageFormat.Png);
            captures.Add(new {name,scale,width=bitmap.Width,height=bitmap.Height});
        }
        try {
            foreach(var item in new[]{("ring",0),("bar",1),("stepped",2),("numeric",3),("spark",4)}) {
                surface.Page=0;surface.PagePosition=0;surface.ChartStyle=item.Item2;await Capture("usage-"+item.Item1);
            }
            foreach(var item in new[]{("dollar",0),("multi",1),("tokens",2),("spark",3)}) {
                surface.Page=1;surface.PagePosition=1;surface.CostStyle=item.Item2;await Capture("cost-"+item.Item1);
            }
            surface.Page=2;surface.PagePosition=2;surface.Height=277;window.Height=277;await Capture("overview");
            var first=new DateTime(DateTime.Today.Year,1,1);var start=first.AddDays(-(int)first.DayOfWeek);
            int day=(DateTime.Today-start).Days;
            surface.ActivateAt(new Point(16+day/7*13.95+5.8,38+81+day%7*13.95+5.8));
            surface.Height=335;window.Height=335;await Task.Delay(700);await Capture("overview-detail");
            await RefinementTests.Run(surface,window,directory);
            File.WriteAllText(Path.Combine(directory,"manifest.json"),JsonSerializer.Serialize(new {build=typeof(IslandVisual).Assembly.ManifestModule.ModuleVersionId,fixtureDate=ParityData.FixtureDate,captures},new JsonSerializerOptions {WriteIndented=true}));
            Console.WriteLine("Captured 11 current native Windows panels in an isolated rendering window.");
        } finally{window.Close();}
    }
}

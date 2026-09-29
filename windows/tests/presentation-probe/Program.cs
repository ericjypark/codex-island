using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Controls;

internal static class Program
{
    [DllImport("user32.dll")]private static extern void mouse_event(uint flags,uint x,uint y,uint data,UIntPtr extra);
    [DllImport("user32.dll")]private static extern int GetSystemMetrics(int metric);
    [DllImport("user32.dll")]private static extern IntPtr GetDC(IntPtr window);
    [DllImport("user32.dll")]private static extern int ReleaseDC(IntPtr window,IntPtr dc);
    [DllImport("gdi32.dll")]private static extern uint GetPixel(IntPtr dc,int x,int y);
    [DllImport("dwmapi.dll")]private static extern int DwmExtendFrameIntoClientArea(IntPtr window,ref Margins margins);
    [StructLayout(LayoutKind.Sequential)]private struct Margins{public int Left,Right,Top,Bottom;}
    [STAThread]private static int Main(string[] args)
    {
        var app=new Application{ShutdownMode=ShutdownMode.OnExplicitShutdown};int code=0;
        app.Startup+=async(_,_)=>{try{await Run(args[0]);}catch(Exception error){Console.Error.WriteLine(error);code=1;}finally{app.Shutdown();}};
        app.Run();return code;
    }
    private static async Task Run(string output)
    {
        var results=new List<object>();Directory.CreateDirectory(output);
        foreach(string mode in new[]{"opaque","layered","glass"}){
            var grid=new Canvas();var brush=new SolidColorBrush(Color.FromRgb(56,56,56));
            var target=new Border{Width=60,Height=60,Background=brush};Canvas.SetLeft(target,100);Canvas.SetTop(target,100);grid.Children.Add(target);
            var window=new Window{Width=900,Height=420,Left=100,Top=420,WindowStyle=WindowStyle.None,ResizeMode=ResizeMode.NoResize,
                AllowsTransparency=mode=="layered",Background=mode=="opaque"?Brushes.Black:Brushes.Transparent,Content=grid,Topmost=true,ShowInTaskbar=false};
            window.SourceInitialized+=(_,_)=>{if(mode=="glass"){
                var source=(HwndSource)PresentationSource.FromVisual(window)!;source.CompositionTarget.BackgroundColor=Colors.Transparent;
                var margins=new Margins{Left=-1,Right=-1,Top=-1,Bottom=-1};int result=DwmExtendFrameIntoClientArea(source.Handle,ref margins);
                if(result!=0)throw new InvalidOperationException("DWM extension failed: "+result);
            }};
            target.MouseDown+=(_,_)=>brush.Color=Color.FromRgb(198,198,198);window.Show();await Task.Delay(500);
            try{
                var latencies=new List<double>();var point=target.PointToScreen(new Point(30,30));int x=(int)point.X,y=(int)point.Y;
                for(int sample=0;sample<12;sample++){
                    brush.Color=Color.FromRgb(56,56,56);
                    mouse_event(0x8001,(uint)(x*65535.0/(GetSystemMetrics(0)-1)),(uint)(y*65535.0/(GetSystemMetrics(1)-1)),0,UIntPtr.Zero);
                    await Task.Delay(300);
                    double duration=await Task.Run(()=>{
                        IntPtr dc=GetDC(IntPtr.Zero);try{
                            if((GetPixel(dc,x,y)&255)>130)throw new InvalidOperationException("The probe did not settle.");
                            var watch=System.Diagnostics.Stopwatch.StartNew();mouse_event(2,0,0,0,UIntPtr.Zero);mouse_event(4,0,0,0,UIntPtr.Zero);
                            while(watch.ElapsedMilliseconds<1000){if((GetPixel(dc,x,y)&255)>150)break;Thread.Sleep(1);}return watch.Elapsed.TotalMilliseconds;
                        }finally{ReleaseDC(IntPtr.Zero,dc);}
                    });latencies.Add(duration);await Task.Delay(150);
                }
                var ordered=latencies.Order().ToArray();var result=new{mode,medianMs=ordered[6],maxMs=ordered[^1],samples=latencies};results.Add(result);Console.WriteLine(JsonSerializer.Serialize(result));
                var origin=window.PointToScreen(new Point());var dpi=VisualTreeHelper.GetDpi(window);
                using var bitmap=new System.Drawing.Bitmap((int)(window.ActualWidth*dpi.DpiScaleX),(int)(window.ActualHeight*dpi.DpiScaleY));
                using(var graphics=System.Drawing.Graphics.FromImage(bitmap))graphics.CopyFromScreen((int)origin.X,(int)origin.Y,0,0,bitmap.Size);
                bitmap.Save(Path.Combine(output,"presentation-"+mode+".png"));
            }finally{window.Close();}
        }
        File.WriteAllText(Path.Combine(output,"presentation-probe.json"),JsonSerializer.Serialize(new{results,scope="Identical WPF control, size, input and readback; only window transparency changes"},new JsonSerializerOptions{WriteIndented=true}));
    }
}

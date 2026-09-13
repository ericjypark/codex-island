using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.Loader;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;

internal static class Program
{
    private const BindingFlags Flags=BindingFlags.Instance|BindingFlags.NonPublic|BindingFlags.Public;
    [STAThread] private static int Main(string[] args)
    {
        string folder=args[0],output=args[1];
        int variantIndex=Array.IndexOf(args,"--probe-mode");
        string variant=variantIndex>=0?args[variantIndex+1]:"baseline";
        nint initialForeground=variant=="introduction"?IntroductionTests.Foreground:0;
        AssemblyLoadContext.Default.Resolving+=(_,name)=>File.Exists(Path.Combine(folder,name.Name+".dll"))?AssemblyLoadContext.Default.LoadFromAssemblyPath(Path.Combine(folder,name.Name+".dll")):null;
        var assembly=AssemblyLoadContext.Default.LoadFromAssemblyPath(Path.Combine(folder,"CodexIslandPrototype.dll"));
        var velopack=AssemblyLoadContext.Default.LoadFromAssemblyPath(Path.Combine(folder,"Velopack.dll"));
        dynamic bootstrap=velopack.GetType("Velopack.VelopackApp")!.GetMethod("Build")!.Invoke(null,null)!;
        bootstrap.SetArgs(Array.Empty<string>()).SetAutoApplyOnStartup(false).Run();
        var app=(Application)Activator.CreateInstance(assembly.GetType("IslandPrototype.App")!)!;
        app.GetType().GetMethod("InitializeComponent")!.Invoke(app,null);
        int exit=0;
        app.Startup+=async(_,_)=>{
            try {
                await Task.Delay(1600);
                var window=app.MainWindow??throw new Exception("No app window");
                if(variant=="introduction") {await IntroductionTests.Run(window,output,initialForeground);return;}
                var type=window.GetType();
                var stateType=type.GetNestedType("IslandState",BindingFlags.NonPublic)!;
                var setState=type.GetMethod("SetState",Flags)!;
                var moving=type.GetField("shellMoving",Flags)!;
                var surface=type.GetField("Surface",Flags)!.GetValue(window)!;
                var renderCount=surface.GetType().GetProperty("RenderCount",Flags)!;
                if(variant=="no-shadows")foreach(string field in new[]{"ShadowShape","HaloShape"})((UIElement)type.GetField(field,Flags)!.GetValue(window)!).Effect=null;
                void State(string name,bool animate) {
                    setState.Invoke(window,new object[]{Enum.Parse(stateType,name),animate});
                    if(variant=="no-counter"&&name=="Expanded")surface.GetType().GetMethod("StartCounter")!.Invoke(surface,new object[]{true});
                    if(variant=="no-sweep") {
                        var sweep=type.GetField("Sweep",Flags)!.GetValue(window)!;
                        sweep.GetType().GetProperty("Active")!.SetValue(sweep,false);
                    }
                }
                var checks=new List<object>();
                void Check(string name,bool pass){checks.Add(new{name,pass});Console.WriteLine((pass?"PASS ":"FAIL ")+name);if(!pass)exit=1;}
                if(variant=="regression") {
                    var counter=surface.GetType().GetField("counterRunning",Flags)!;
                    foreach(var test in new[]{(page:0,cost:0,animated:false),(page:2,cost:0,animated:false),(page:1,cost:0,animated:true),(page:1,cost:1,animated:false),(page:1,cost:2,animated:false),(page:1,cost:3,animated:false)}) {
                        State("Peek",false);
                        type.GetMethod("ChangePage",Flags)!.Invoke(window,new object[]{test.page});
                        surface.GetType().GetProperty("CostStyle")!.SetValue(surface,test.cost);
                        State("Expanded",true);
                        Check($"Page {test.page}, cost style {test.cost}: counter animation {test.animated}",(bool)counter.GetValue(surface)! == test.animated);
                        await Task.Delay(700);
                    }
                    State("Peek",false);State("Expanded",true);
                    var onFrame=type.GetMethod("AnimateShellFrame",Flags)!;
                    var island=(FrameworkElement)type.GetField("Island",Flags)!.GetValue(window)!;
                    var frameArgs=(RenderingEventArgs)Activator.CreateInstance(typeof(RenderingEventArgs),Flags,null,new object[]{TimeSpan.FromDays(1)},null)!;
                    System.Threading.Thread.Sleep(8);onFrame.Invoke(window,new object?[]{null,frameArgs});
                    double firstWidth=island.Width;
                    System.Threading.Thread.Sleep(8);onFrame.Invoke(window,new object?[]{null,frameArgs});
                    Check("Repeated rendering time does not advance shell geometry",island.Width==firstWidth);
                    State("Hidden",false);
                    var theme=assembly.GetType("IslandPrototype.ParityTheme")!;
                    var silhouette=theme.GetMethod("Silhouette",BindingFlags.Static|BindingFlags.Public)!;
                    ReferenceSweep.Silhouette=(w,h,p)=>(Geometry)silhouette.Invoke(null,new object[]{w,h,p})!;
                    var sweepType=assembly.GetType("IslandPrototype.GlowSweep")!;
                    var sweep=(FrameworkElement)Activator.CreateInstance(sweepType)!;
                    sweepType.GetProperty("Active")!.SetValue(sweep,true);
                    var reference=new ReferenceSweep{Active=true};
                    var drawSweep=sweepType.GetMethod("DrawSweep",Flags);
                    if(drawSweep!=null) {
                        foreach(var size in new[]{(192.0,52.0,1.0),(340.0,90.0,.75),(650.0,210.0,.15),(800.0,226.0,0.0),(800.0,277.0,0.0),(800.0,335.0,0.0),(112.0,52.0,1.0)}) {
                            foreach(var control in new FrameworkElement[]{sweep,reference}){control.Width=size.Item1;control.Height=size.Item2;control.Measure(new Size(size.Item1,size.Item2));control.Arrange(new Rect(0,0,size.Item1,size.Item2));}
                            sweepType.GetProperty("PillShape",Flags)!.SetValue(sweep,size.Item3);reference.PillShape=size.Item3;
                            foreach(double rotation in new[]{0.0,.2,.7,1.0}) {
                                byte[] Raster(bool current) {
                                    var drawing=new DrawingVisual();using(var dc=drawing.RenderOpen()) {
                                        if(current)drawSweep.Invoke(sweep,new object[]{dc,rotation});else reference.DrawSweep(dc,rotation);
                                    }
                                    int width=(int)size.Item1*2+16,height=(int)size.Item2*2+16;
                                    var bitmap=new System.Windows.Media.Imaging.RenderTargetBitmap(width,height,192,192,PixelFormats.Pbgra32);bitmap.Render(drawing);
                                    var pixels=new byte[width*height*4];bitmap.CopyPixels(pixels,width*4,0);return pixels;
                                }
                                Check($"Sweep pixels remain identical at {size.Item1}x{size.Item2}, shape {size.Item3}, rotation {rotation}",Raster(true).SequenceEqual(Raster(false)));
                            }
                        }
                    }
                    reference.Active=false;sweepType.GetProperty("Active")!.SetValue(sweep,false);
                    Directory.CreateDirectory(output);File.WriteAllText(Path.Combine(output,"checks.json"),JsonSerializer.Serialize(new{build=assembly.ManifestModule.ModuleVersionId,checks},new JsonSerializerOptions{WriteIndented=true}));
                    return;
                }
                var phases=new List<object>();
                foreach(int page in new[]{0,2}) {
                    type.GetMethod("ChangePage",Flags)!.Invoke(window,new object[]{page});
                    State("Hidden",false);await Task.Delay(800);
                    for(int repeat=0;repeat<4;repeat++) {
                        State("Peek",false);await Task.Delay(500);
                        foreach(string name in new[]{"Expanded","Hidden"}) {
                            var intervals=new List<double>();var completed=new TaskCompletionSource();
                            TimeSpan renderingTime=TimeSpan.MinValue;long started=Stopwatch.GetTimestamp(),previous=started;
                            double cpu=Process.GetCurrentProcess().TotalProcessorTime.TotalMilliseconds;
                            long allocated=GC.GetTotalAllocatedBytes();int renders=(int)renderCount.GetValue(surface)!;
                            EventHandler? frame=null;
                            frame=(_,e)=>{
                                if(e is RenderingEventArgs rendering){if(renderingTime==rendering.RenderingTime)return;renderingTime=rendering.RenderingTime;}
                                long now=Stopwatch.GetTimestamp();intervals.Add(Stopwatch.GetElapsedTime(previous,now).TotalMilliseconds);previous=now;
                                if(!(bool)moving.GetValue(window)!)completed.TrySetResult();
                            };
                            CompositionTarget.Rendering+=frame;
                            try {
                                State(name,true);
                                await completed.Task.WaitAsync(TimeSpan.FromSeconds(4));
                            } finally {CompositionTarget.Rendering-=frame;}
                            double elapsed=Stopwatch.GetElapsedTime(started).TotalMilliseconds;
                            var sorted=intervals.Order().ToArray();
                            phases.Add(new {page,repeat,state=name,elapsed,frames=intervals.Count,p50=sorted[sorted.Length/2],p95=sorted[Math.Min(sorted.Length-1,(int)(sorted.Length*.95))],max=sorted[^1],over33=intervals.Count(t=>t>33.4),cpuMs=Process.GetCurrentProcess().TotalProcessorTime.TotalMilliseconds-cpu,allocatedBytes=GC.GetTotalAllocatedBytes()-allocated,renders=(int)renderCount.GetValue(surface)!-renders,intervals});
                            await Task.Delay(350);
                        }
                    }
                }
                Directory.CreateDirectory(output);
                File.WriteAllText(Path.Combine(output,"results.json"),JsonSerializer.Serialize(new {build=assembly.ManifestModule.ModuleVersionId,variant,architecture=System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture.ToString(),dpi=VisualTreeHelper.GetDpi(window).DpiScaleX,renderTier=RenderCapability.Tier>>16,phases},new JsonSerializerOptions{WriteIndented=true}));
                Console.WriteLine("Captured "+phases.Count+" full-window open/close phases.");
            } catch(Exception e){Console.Error.WriteLine(e);exit=1;}
            finally {app.Shutdown();}
        };
        app.Run();return exit;
    }
}

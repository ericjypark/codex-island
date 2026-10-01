using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Windows.Media;

namespace IslandPrototype;

internal static class FrameDiagnostics
{
    private sealed record Sample(double At, string Kind, double Milliseconds, int Page, double Progress,long Ticks);
    private static readonly List<Sample> samples = new();
    private static readonly Stopwatch clock = new();
    private static double previousFrame;
    private static TimeSpan previousRenderingTime;
    private static int currentPage;
    private static double currentProgress=1;
    internal static bool Enabled {get; private set;}
    internal static void Start()
    {
        Enabled=true;clock.Start();CompositionTarget.Rendering+=OnFrame;
    }
    private static void OnFrame(object? sender,EventArgs args)
    {
        if(args is RenderingEventArgs rendering){if(rendering.RenderingTime==previousRenderingTime)return;previousRenderingTime=rendering.RenderingTime;}
        double now=clock.Elapsed.TotalMilliseconds;
        if(previousFrame>0&&samples.Count<20000)samples.Add(new(now,"frame",now-previousFrame,currentPage,currentProgress,Stopwatch.GetTimestamp()));
        previousFrame=now;
    }
    internal static long Begin()=>Enabled?Stopwatch.GetTimestamp():0;
    internal static void Mark(string kind,int page,double value)
    {
        if(Enabled&&samples.Count<20000)samples.Add(new(clock.Elapsed.TotalMilliseconds,kind,0,page,value,Stopwatch.GetTimestamp()));
    }
    internal static void End(long start,string kind,int page=0,double progress=1)
    {
        if(!Enabled)return;
        if(kind=="island"){currentPage=page;currentProgress=progress;}
        if(samples.Count<20000)samples.Add(new(clock.Elapsed.TotalMilliseconds,kind,Stopwatch.GetElapsedTime(start).TotalMilliseconds,page,progress,Stopwatch.GetTimestamp()));
    }
    internal static void Save()
    {
        if(!Enabled)return;
        CompositionTarget.Rendering-=OnFrame;Enabled=false;
        string directory=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"CodexIslandPrototype");
        Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory,"frame-trace.json"),JsonSerializer.Serialize(new {build=typeof(App).Assembly.ManifestModule.ModuleVersionId,recordedAt=DateTimeOffset.UtcNow,tickFrequency=Stopwatch.Frequency,samples}));
    }
}

using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Threading;

namespace IslandPrototype;

public sealed class GlowSweep : FrameworkElement
{
    private readonly DispatcherTimer timer = new() {Interval=TimeSpan.FromSeconds(1.0/30)};
    private readonly List<(Point A,Point B,double Angle)> segments = new();
    private readonly List<Pen> pens = new();
    private bool active,pathDirty=true;
    private Size pathSize;
    private double pillShape;
    internal double PillShape {get=>pillShape;set{if(pillShape==value)return;pillShape=value;pathDirty=true;InvalidateVisual();}}
    public Color Tint {get;set;} = Color.FromRgb(0,71,171);
    public bool Active {
        get=>active;
        set {
            if(active==value)return;
            active=value;
            if(value)timer.Start();else timer.Stop();
            InvalidateVisual();
        }
    }
    public GlowSweep()
    {
        IsHitTestVisible=false;
        Effect=new BlurEffect {Radius=3,RenderingBias=RenderingBias.Performance};
        timer.Tick+=(_,_)=>InvalidateVisual();
        SizeChanged+=(_,_)=>{pathDirty=true;InvalidateVisual();};
        Unloaded+=(_,_)=>timer.Stop();
    }
    private void RebuildPath()
    {
        segments.Clear();
        if(ActualWidth<=0||ActualHeight<=0)return;
        var path=ParityTheme.Silhouette(ActualWidth,ActualHeight,PillShape).GetFlattenedPathGeometry(.2,ToleranceType.Absolute);
        foreach(var figure in path.Figures) {
            Point previous=figure.StartPoint;
            foreach(var segment in figure.Segments) {
                if(segment is PolyLineSegment poly)foreach(var point in poly.Points){Append(previous,point);previous=point;}
                else if(segment is LineSegment line){Append(previous,line.Point);previous=line.Point;}
            }
            if(figure.IsClosed)Append(previous,figure.StartPoint);
        }
    }
    private void Append(Point start,Point end)
    {
        int count=Math.Max(1,(int)Math.Ceiling((end-start).Length/3));
        for(int i=0;i<count;i++) {
            Point a=start+(end-start)*(i/(double)count),b=start+(end-start)*((i+1.0)/count);
            double angle=Math.Atan2((a.Y+b.Y)/2-ActualHeight/2,(a.X+b.X)/2-ActualWidth/2)/(2*Math.PI);
            segments.Add((a,b,angle));
            if(pens.Count<segments.Count)pens.Add(new Pen(new SolidColorBrush(),4));
        }
    }
    protected override void OnRender(DrawingContext dc)
    {
        if(!active)return;
        long started=FrameDiagnostics.Begin();
        double rotation=(DateTime.UtcNow-new DateTime(2001,1,1)).TotalSeconds*100/360;
        DrawSweep(dc,rotation);
        FrameDiagnostics.End(started,"glow-sweep");
    }
    internal void DrawSweep(DrawingContext dc,double rotation)
    {
        if(!active)return;
        if(pathDirty||pathSize!=RenderSize){RebuildPath();pathSize=RenderSize;pathDirty=false;}
        for(int i=0;i<segments.Count;i++) {
            var segment=segments[i];
            double p=segment.Angle-rotation;p-=Math.Floor(p);
            if(p<.55)continue;
            Color color;double alpha;
            if(p<.78){color=Tint;alpha=(p-.55)/.23;}
            else if(p<.92){double t=(p-.78)/.14;color=Color.FromRgb((byte)(Tint.R+(255-Tint.R)*t),(byte)(Tint.G+(255-Tint.G)*t),(byte)(Tint.B+(255-Tint.B)*t));alpha=1-.05*t;}
            else{double t=(p-.92)/.08;color=Color.FromRgb((byte)(255+(Tint.R-255)*t),(byte)(255+(Tint.G-255)*t),(byte)(255+(Tint.B-255)*t));alpha=.95*(1-t);}
            var pen=pens[i];var brush=(SolidColorBrush)pen.Brush;
            brush.Color=color;brush.Opacity=alpha;
            dc.DrawLine(pen,segment.A,segment.B);
        }
    }
}

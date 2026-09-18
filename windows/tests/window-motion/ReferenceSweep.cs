// Preserves the pre-optimization stroke construction for deterministic raster comparisons.
using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Threading;



internal sealed class ReferenceSweep : FrameworkElement
{
    internal static Func<double,double,double,Geometry> Silhouette=null!;
    private readonly DispatcherTimer timer = new() {Interval=TimeSpan.FromSeconds(1.0/30)};
    private readonly List<(Point A,Point B,double Angle)> segments = new();
    private bool active;
    private double pillShape;
    internal double PillShape {get=>pillShape;set{if(pillShape==value)return;pillShape=value;RebuildPath();}}
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
    public ReferenceSweep()
    {
        IsHitTestVisible=false;
        Effect=new BlurEffect {Radius=3,RenderingBias=RenderingBias.Performance};
        timer.Tick+=(_,_)=>InvalidateVisual();
        SizeChanged+=(_,_)=>RebuildPath();
        Unloaded+=(_,_)=>timer.Stop();
    }
    private void RebuildPath()
    {
        segments.Clear();
        if(ActualWidth<=0||ActualHeight<=0)return;
        var path=Silhouette(ActualWidth,ActualHeight,PillShape).GetFlattenedPathGeometry(.2,ToleranceType.Absolute);
        foreach(var figure in path.Figures) {
            Point previous=figure.StartPoint;
            foreach(var segment in figure.Segments) {
                if(segment is PolyLineSegment poly)foreach(var point in poly.Points){Append(previous,point);previous=point;}
                else if(segment is LineSegment line){Append(previous,line.Point);previous=line.Point;}
            }
            if(figure.IsClosed)Append(previous,figure.StartPoint);
        }
        InvalidateVisual();
    }
    private static SolidColorBrush Brush(Color color,double alpha){var brush=new SolidColorBrush(color){Opacity=alpha};brush.Freeze();return brush;}
    private void Append(Point start,Point end)
    {
        int count=Math.Max(1,(int)Math.Ceiling((end-start).Length/3));
        for(int i=0;i<count;i++) {
            Point a=start+(end-start)*(i/(double)count),b=start+(end-start)*((i+1.0)/count);
            double angle=Math.Atan2((a.Y+b.Y)/2-ActualHeight/2,(a.X+b.X)/2-ActualWidth/2)/(2*Math.PI);
            segments.Add((a,b,angle));
        }
    }
    internal void DrawSweep(DrawingContext dc,double rotation)
    {
        if(!active)return;
        RebuildPath();
        foreach(var segment in segments) {
            double p=segment.Angle-rotation;p-=Math.Floor(p);
            if(p<.55)continue;
            Color color;double alpha;
            if(p<.78){color=Tint;alpha=(p-.55)/.23;}
            else if(p<.92){double t=(p-.78)/.14;color=Color.FromRgb((byte)(Tint.R+(255-Tint.R)*t),(byte)(Tint.G+(255-Tint.G)*t),(byte)(Tint.B+(255-Tint.B)*t));alpha=1-.05*t;}
            else{double t=(p-.92)/.08;color=Color.FromRgb((byte)(255+(Tint.R-255)*t),(byte)(255+(Tint.G-255)*t),(byte)(255+(Tint.B-255)*t));alpha=.95*(1-t);}
            dc.DrawLine(new Pen(Brush(color,alpha),4),segment.A,segment.B);
        }

    }
}

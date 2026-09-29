using System;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace IslandPrototype;

internal static class ParityTheme
{
    public const double PillHeight = 52, PillTop = 12, PillHiddenOffset = -60, ExpandedWidth = 800;
    public static double PillWidth(int providers) => providers > 1 ? 192 : 112;
    public const double HeaderHeight = 38, TileHeight = 96, FooterHeight = 44, PanelHeight = 226;
    public static Color Codex = Color.FromRgb(90, 168, 240), Antigravity = Color.FromRgb(182, 156, 255);
    public static Color Claude = Color.FromRgb(204, 120, 92), Teal = Color.FromRgb(61, 214, 140);
    public static readonly FontFamily TextFont = new("Segoe UI");
    public static readonly FontFamily NumberFont = new("Cascadia Mono, Consolas");

    public static SolidColorBrush White(double opacity = 1) => Brush(Colors.White, opacity);
    public static SolidColorBrush Brush(Color color, double opacity = 1)
    {
        var brush = new SolidColorBrush(color) { Opacity = opacity }; brush.Freeze(); return brush;
    }

    public static Geometry Silhouette(double width, double height, double pill = 0)
    {
        pill=Math.Clamp(pill,0,1);
        double radius=Math.Min(26,Math.Min(width,height)/2);
        if(pill==1){var capsule=new RectangleGeometry(new Rect(0,0,width,height),radius,radius);capsule.Freeze();return capsule;}
        const double e=21.4013092518,k=.5522847498307936;
        Point[] corners=[new(0,e),new(0,15.2388601303),new(0,12.1576981544),new(1.0487596095,8.8409157991),
            new(2.3668400943,5.2195361853),new(5.2195361853,2.3668400943),new(8.8409157991,1.0487596095),
            new(12.1576981544,0),new(15.2388601303,0),new(e,0)];
        if(pill>0) {
            double tangent=4.0/3*Math.Tan(Math.PI/24);
            Point At(double angle)=>new(radius*(1-Math.Cos(angle)),radius*(1-Math.Sin(angle)));
            Vector Tangent(double angle)=>new(radius*Math.Sin(angle)*tangent,-radius*Math.Cos(angle)*tangent);
            var circular=new Point[10];circular[0]=At(0);
            for(int i=0;i<3;i++) {
                double a=i*Math.PI/6,b=(i+1)*Math.PI/6;
                circular[i*3+1]=At(a)+Tangent(a);circular[i*3+2]=At(b)-Tangent(b);circular[i*3+3]=At(b);
            }
            for(int i=0;i<corners.Length;i++)corners[i]+=pill*(circular[i]-corners[i]);
        }
        double top=radius*pill;
        Point Right(Point p)=>new(width-p.X,height-p.Y);
        Point Left(Point p)=>new(p.X,height-p.Y);
        var path=new StreamGeometry();
        using(var c=path.Open()) {
            c.BeginFigure(new Point(top,0),true,true);c.LineTo(new Point(width-top,0),true,false);
            if(top>0)c.BezierTo(new Point(width-top+top*k,0),new Point(width,top-top*k),new Point(width,top),true,false);
            c.LineTo(Right(corners[0]),true,false);
            for(int i=0;i<3;i++)c.BezierTo(Right(corners[i*3+1]),Right(corners[i*3+2]),Right(corners[i*3+3]),true,false);
            c.LineTo(Left(corners[9]),true,false);
            for(int i=2;i>=0;i--)c.BezierTo(Left(corners[i*3+2]),Left(corners[i*3+1]),Left(corners[i*3]),true,false);
            c.LineTo(new Point(0,top),true,false);
            if(top>0)c.BezierTo(new Point(0,top-top*k),new Point(top-top*k,0),new Point(top,0),true,false);
        }
        path.Freeze(); return path;
    }

    public static DoubleAnimation Ease(double to, double seconds, double delay = 0, bool page = false)
    {
        return new DoubleAnimation(to, TimeSpan.FromSeconds(seconds))
        {
            BeginTime = TimeSpan.FromSeconds(delay),
            EasingFunction = new BezierEase { X1 = page ? .25 : .23, Y1 = page ? .82 : 1, X2 = page ? .25 : .32, Y2 = 1 }
        };
    }
}

internal sealed class BezierEase : EasingFunctionBase
{
    public double X1 = .23, Y1 = 1, X2 = .32, Y2 = 1;
    public BezierEase() { EasingMode = EasingMode.EaseIn; }
    protected override double EaseInCore(double t)
    {
        if(t<=0)return 0;
        if(t>=1)return 1;
        double lo=0,hi=1,u=t;
        for(int i=0;i<18;i++)
        {
            u=(lo+hi)/2;
            double x=3*(1-u)*(1-u)*u*X1+3*(1-u)*u*u*X2+u*u*u;
            if(x<t)lo=u;else hi=u;
        }
        return 3*(1-u)*(1-u)*u*Y1+3*(1-u)*u*u*Y2+u*u*u;
    }
    protected override Freezable CreateInstanceCore() => new BezierEase { X1=X1,Y1=Y1,X2=X2,Y2=Y2 };
}

internal sealed class SpringAnimation : DoubleAnimationBase
{
    public double From { get; set; }
    public double To { get; set; }
    public double Response { get; set; } = .42;
    public double Damping { get; set; } = .82;
    protected override Freezable CreateInstanceCore() => new SpringAnimation { From=From,To=To,Response=Response,Damping=Damping,Duration=Duration };
    protected override double GetCurrentValueCore(double origin,double destination,AnimationClock clock)
    {
        if(clock.CurrentProgress >= 1)return To;
        double t=clock.CurrentTime?.TotalSeconds ?? 0;
        double omega=2*Math.PI/Response, wd=omega*Math.Sqrt(1-Damping*Damping);
        double progress=1-Math.Exp(-Damping*omega*t)*(Math.Cos(wd*t)+Damping*omega/wd*Math.Sin(wd*t));
        return From+(To-From)*progress;
    }
}

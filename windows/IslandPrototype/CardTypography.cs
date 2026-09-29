using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Media;

namespace IslandPrototype;

internal static class CardTypography
{
    private static readonly FontFamily TextFace=new(new Uri("pack://application:,,,/CodexIslandPrototype;component/"),"./Assets/Fonts/#Card Text");
    private static readonly FontFamily DisplayFace=new(new Uri("pack://application:,,,/CodexIslandPrototype;component/"),"./Assets/Fonts/#Card Display");
    private const double CapScale=0.9684563758389262;
    private static readonly Dictionary<(char Character,double Size,bool Semibold),Geometry> RoundedGlyphs=new();
    private static readonly Dictionary<char,double> RoundedAdvances=new() {
        ['0']=.6064453125,['1']=.443359375,['2']=.56591796875,['3']=.591796875,['4']=.6044921875,
        ['5']=.5849609375,['6']=.5986328125,['7']=.546875,['8']=.59912109375,['9']=.5986328125,
        ['B']=.6044921875,['K']=.615234375,['M']=.8310546875,['.']=.25390625,[',']=.25390625,['$']=.6044921875 };
    internal static Typeface Face(double size,bool semibold=false,bool rounded=false,bool mono=false)=>new(mono?ParityTheme.NumberFont:size>=20?DisplayFace:TextFace,FontStyles.Normal,semibold||(!rounded&&size<20&&!mono)?FontWeights.SemiBold:rounded?FontWeights.Normal:FontWeights.Medium,FontStretches.Normal);
    internal static FormattedText Make(string text,double size,Brush brush,double dpi,bool semibold=false,bool rounded=false,bool mono=false)=>new(text,UsageCardSnapshot.English,FlowDirection.LeftToRight,Face(size,semibold,rounded,mono),size,brush,dpi);
    internal static double Ascent(double size)=>size*0.966796875;
    internal static double LineHeight(double size)=>Math.Round(size*1.177734375,MidpointRounding.AwayFromZero);
    private static double WidthScale(double size,bool rounded,bool mono)=>mono?1:rounded?.977:size>=20?.98:1;
    private static double Advance(char ch,double size,double dpi,bool semibold,bool rounded,bool mono)=>rounded&&!semibold&&RoundedAdvances.TryGetValue(ch,out var advance)?advance*size:Make(ch.ToString(),size,Brushes.Black,dpi,semibold,rounded,mono).WidthIncludingTrailingWhitespace*WidthScale(size,rounded,mono);
    internal static double Width(string text,double size,double dpi,double tracking=0,bool semibold=false,bool rounded=false,bool mono=false)
    {
        double scale=WidthScale(size,rounded,mono);
        if(tracking==0&&!rounded)return Make(text,size,Brushes.Black,dpi,semibold,rounded,mono).WidthIncludingTrailingWhitespace*scale;
        double width=0;foreach(char ch in text)width+=Advance(ch,size,dpi,semibold,rounded,mono)+tracking;
        return width;
    }
    internal static string Ellipsize(string text,double size,double dpi,double max)
    {
        if(Width(text,size,dpi)<=max)return text;
        var starts=StringInfo.ParseCombiningCharacters(text);
        for(int count=starts.Length-1;count>=0;count--) {string candidate=text[..starts[count]]+"…";if(Width(candidate,size,dpi)<=max)return candidate;}
        return "";
    }
    internal static double Draw(DrawingContext dc,string text,double x,double y,double size,Brush brush,double dpi,bool right=false,bool center=false,bool semibold=false,bool rounded=false,bool mono=false,double max=double.PositiveInfinity,double tracking=0)
    {
        double width=Width(text,size,dpi,tracking,semibold,rounded,mono),fit=Math.Min(1,max/Math.Max(1,width));
        double origin=right?x-width*fit:center?x-width*fit/2:x,baseline=y+Ascent(size);
        dc.PushTransform(new ScaleTransform(fit,fit,origin,y));
        double sx=WidthScale(size,rounded,mono),sy=mono?1:CapScale;
        void Glyph(string value,double left)
        {
            var run=Make(value,size,brush,dpi,semibold,rounded,mono);
            double advance=rounded?Advance(value[0],size,dpi,semibold,true,mono):run.WidthIncludingTrailingWhitespace*sx;
            double opticalInset=rounded?(advance-run.WidthIncludingTrailingWhitespace*sx)/2:0;
            dc.PushTransform(new TranslateTransform(left+opticalInset,baseline));dc.PushTransform(new ScaleTransform(sx,sy));
            if(rounded) {
                var key=(value[0],size,semibold);
                if(!RoundedGlyphs.TryGetValue(key,out var geometry)) {
                    geometry=RoundCorners(run.BuildGeometry(new Point(0,-run.Baseline)),size*.036);
                    geometry.Freeze();RoundedGlyphs[key]=geometry;
                }
                dc.DrawGeometry(brush,null,geometry);
            } else dc.DrawText(run,new Point(0,-run.Baseline));
            dc.Pop();dc.Pop();
        }
        if(tracking==0&&!rounded)Glyph(text,origin);
        else {double offset=origin;foreach(char ch in text){Glyph(ch.ToString(),offset);offset+=Advance(ch,size,dpi,semibold,rounded,mono)+tracking;}}
        dc.Pop();return width*fit;
    }
    private static Geometry RoundCorners(Geometry source,double radius)
    {
        var flat=source.GetOutlinedPathGeometry(.025,ToleranceType.Absolute).GetFlattenedPathGeometry(.025,ToleranceType.Absolute);
        var contours=flat.Figures.Select(figure=>new[]{figure.StartPoint}.Concat(figure.Segments.SelectMany(segment=>segment is PolyLineSegment poly?poly.Points.AsEnumerable():segment is LineSegment line?new[]{line.Point}:Array.Empty<Point>())).ToList()).ToArray();
        foreach(var points in contours)if(points.Count>1&&(points[0]-points[^1]).Length<.001)points.RemoveAt(points.Count-1);
        double Area(IReadOnlyList<Point> points)=>Enumerable.Range(0,points.Count).Sum(i=>points[i].X*points[(i+1)%points.Count].Y-points[(i+1)%points.Count].X*points[i].Y);
        double orientation=Math.Sign(contours.OrderByDescending(p=>Math.Abs(Area(p))).Select(Area).FirstOrDefault());
        var cuts=new StreamGeometry {FillRule=FillRule.Nonzero};using(var context=cuts.Open())foreach(var points in contours) {
            if(points.Count<3)continue;
            for(int i=0;i<points.Count;i++) {
                Vector incoming=points[i]-points[(i+points.Count-1)%points.Count],outgoing=points[(i+1)%points.Count]-points[i];
                double a=incoming.Length,b=outgoing.Length;if(a<.001||b<.001)continue;
                incoming/=a;outgoing/=b;
                double turn=Vector.CrossProduct(incoming,outgoing)*orientation,cos=Vector.Multiply(incoming,outgoing);
                if(turn<=0||cos>Math.Cos(Math.PI/6))continue;
                double distance=Math.Min(radius/Math.Tan(Math.Acos(Math.Clamp(-cos,-1,1))/2),radius*3);
                Point before=points[i]-incoming*distance,after=points[i]+outgoing*distance;
                context.BeginFigure(points[i],true,true);
                context.LineTo(before,true,false);
                context.QuadraticBezierTo(points[i],after,true,false);
            }
        }
        return Geometry.Combine(source,cuts,GeometryCombineMode.Exclude,null,.025,ToleranceType.Absolute);
    }
}

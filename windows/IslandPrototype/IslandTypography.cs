using System;
using System.Collections.Generic;
using System.Globalization;
using System.Windows;
using System.Windows.Media;

namespace IslandPrototype;

internal static class IslandTypography
{
    internal static readonly FontFamily TextFace=new(new Uri("pack://application:,,,/CodexIslandPrototype;component/"),"./Assets/Fonts/#Island Text");
    private const double MonoAdvance=.6181640625, ReferenceCap=.70458984375;
    private static readonly Dictionary<(double Size,bool Bold,bool Mono),Typeface> faces=new();
    private static readonly Dictionary<Typeface,double> widthScales=new();
    private static readonly Dictionary<Typeface,double> heightScales=new();
    internal static Typeface Face(double size,bool bold,bool mono)
    {
        var key=(size,bold,mono);
        if(!faces.TryGetValue(key,out var face))faces[key]=face=new(mono?ParityTheme.NumberFont:TextFace,FontStyles.Normal,
            mono&&bold&&size==9?FontWeights.Bold:bold?FontWeights.SemiBold:mono?FontWeights.Normal:FontWeights.Medium,FontStretches.Normal);
        return face;
    }
    internal static FormattedText Make(string value,double size,Brush brush,double dpi,bool bold,bool mono)=>new(value,Localizer.Culture,FlowDirection.LeftToRight,Face(size,bold,mono),size,brush,dpi);
    internal static double WidthScale(double size,bool bold,bool mono)
    {
        if(!mono)return 1;
        var face=Face(size,bold,true);
        if(!widthScales.TryGetValue(face,out double scale)) {
            scale=face.TryGetGlyphTypeface(out var glyph)&&glyph.CharacterToGlyphMap.TryGetValue('0',out ushort zero)?MonoAdvance/glyph.AdvanceWidths[zero]:1;
            widthScales[face]=scale;
        }
        return scale;
    }
    internal static double Width(string value,double size,double dpi,bool bold=false,bool mono=false,double tracking=0)
        =>Make(value,size,Brushes.White,dpi,bold,mono).WidthIncludingTrailingWhitespace*WidthScale(size,bold,mono)+Math.Max(0,new StringInfo(value).LengthInTextElements-1)*tracking;
    // SwiftUI's measured line boxes differ from WPF's font boxes, including at the same point size.
    internal static double RowBaseline(double center,double size)=>center+(size switch {9=>3.5,10=>3.5,11=>4,12=>4.5,13=>5,15=>5.5,18=>6.5,38=>14.5,_=>size*.36});
    internal static double HeightScale(double size,bool bold,bool mono)
    {
        var face=Face(size,bold,mono);
        if(!heightScales.TryGetValue(face,out double scale))heightScales[face]=scale=face.TryGetGlyphTypeface(out var glyph)&&glyph.CapsHeight>0?ReferenceCap/glyph.CapsHeight:1;
        return scale;
    }
    internal static double Draw(DrawingContext dc,string value,double x,double y,double size,Brush brush,double dpi,bool bold=false,bool mono=false,bool right=false,bool center=false,double tracking=0,double max=double.PositiveInfinity,double minimumScale=1,bool atBaseline=false)
    {
        double width=Width(value,size,dpi,bold,mono,tracking),fit=Math.Min(1,max/Math.Max(1,width));
        if(fit<minimumScale) {
            var starts=StringInfo.ParseCombiningCharacters(value);
            for(int count=starts.Length-1;count>=0;count--) {
                string candidate=value[..starts[count]]+"…";
                if(Width(candidate,size,dpi,bold,mono,tracking)<=max/minimumScale){value=candidate;break;}
                if(count==0)value="…";
            }
            width=Width(value,size,dpi,bold,mono,tracking);fit=Math.Min(1,max/Math.Max(1,width));
        }
        double left=right?x-width*fit:center?x-width*fit/2:x;
        dc.PushTransform(new ScaleTransform(fit,fit,left,y));
        void Run(string run,double origin)
        {
            var text=Make(run,size,brush,dpi,bold,mono);
            double sx=WidthScale(size,bold,mono),sy=HeightScale(size,bold,mono);
            double baseline=atBaseline?0:mono?text.Baseline:size*1.0791015625;
            dc.PushTransform(new TranslateTransform(origin,y+baseline));dc.PushTransform(new ScaleTransform(sx,sy));
            dc.DrawText(text,new Point(0,-text.Baseline));dc.Pop();dc.Pop();
        }
        if(tracking==0)Run(value,left);
        else {
            double origin=left;var elements=StringInfo.GetTextElementEnumerator(value);
            while(elements.MoveNext()){string element=elements.GetTextElement();Run(element,origin);origin+=Width(element,size,dpi,bold,mono)+tracking;}
        }
        dc.Pop();return width*fit;
    }
}

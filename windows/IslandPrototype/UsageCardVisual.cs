using System;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace IslandPrototype;

internal sealed class UsageCardVisual : FrameworkElement
{
    public UsageCardSnapshot Snapshot {get;set;}
    public CardFormat Format {get;set;}
    public CardMetric Metric {get;set;}
    public string Signature {get;set;}="";
    private double dpi=1;
    private Color background,foreground;
    private bool paper;
    public double CardHeight=>Format==CardFormat.Story?960:Format==CardFormat.Square?540:675;
    private readonly BitmapImage brand=new(new Uri("pack://application:,,,/Assets/codexisland.png"));
    public UsageCardVisual(UsageCardSnapshot snapshot) {Snapshot=snapshot;Width=540;Height=675;}
    public void Update() {Height=CardHeight;InvalidateVisual();}
    private Brush Ink(double opacity=1)=>ParityTheme.Brush(foreground,opacity);
    private double Secondary=>paper?.72:.70;
    private Color ProviderColor(string id)=> (paper,id) switch {
        (true,"claude")=>Color.FromRgb(191,77,51),(true,"codex")=>Color.FromRgb(31,97,201),
        (true,"antigravity")=>Color.FromRgb(120,82,181),(true,_)=>Color.FromRgb(48,77,77),
        (false,"claude")=>Color.FromRgb(245,145,107),(false,"codex")=>Color.FromRgb(133,204,250),
        (false,"antigravity")=>Color.FromRgb(194,168,250),_=>Color.FromRgb(222,245,186)};
    protected override void OnRender(DrawingContext dc)
    {
        dpi=VisualTreeHelper.GetDpi(this).PixelsPerDip;
        var tier=Snapshot.Tier(Metric);paper=tier==CardTier.White;
        background=tier==CardTier.White?Color.FromRgb(244,241,234):tier==CardTier.Black?Color.FromRgb(9,11,13):Color.FromRgb(14,43,201);
        foreground=paper?Color.FromRgb(26,38,48):Color.FromRgb(247,245,232);
        dc.DrawRectangle(ParityTheme.Brush(background),null,new Rect(0,0,540,CardHeight));
        double top=Format==CardFormat.Story?88:32;bool compact=Format==CardFormat.Square;
        string dateLabel=(Snapshot.IsDemo?"Demo · ":"")+Snapshot.DateLabel;
        double dateWidth=Text(dc,dateLabel,36,top,12,Ink(Secondary),max:330);
        Text(dc,CardTypography.Ellipsize(Signature.Trim(),12,dpi,468-dateWidth-12),504,top,12,Ink(Secondary),right:true);
        double headingTop=top+15+(compact?12:26);
        bool milestone=Metric==CardMetric.ApiValue&&Snapshot.MilestoneLabel!=null;
        double headingHeight=milestone?(compact?56:66):(compact?38:43);
        double headlineSize=(compact?32:36)*(milestone?.7:1);
        Text(dc,Metric==CardMetric.ApiValue?Snapshot.ValueHeadline:UsageCardSnapshot.TokenHeadlines[(int)Snapshot.Period],36,headingTop+(headingHeight-CardTypography.LineHeight(headlineSize))/2,headlineSize,Ink(),max:Metric==CardMetric.ApiValue&&Snapshot.MilestoneLabel!=null?380:468,tracking:-1.1);
        if(Metric==CardMetric.ApiValue && Snapshot.MilestoneLabel!=null)Seal(dc,new Rect(compact?436:428,headingTop,compact?68:76,compact?56:66),Snapshot.MilestoneLabel);
        double y=headingTop+headingHeight;
        if(Metric==CardMetric.ApiValue) {
            y+=compact?2:8;
            string money=UsageCardSnapshot.Money(Snapshot.TotalDollars);bool less=money.StartsWith('<');string[] parts=money[(less?2:1)..].Split('.');
            double integerSize=compact?70:108,currencySize=compact?42:50,fractionSize=compact?34:40;
            double baseline=y+CardTypography.Ascent(integerSize),x=36;
            double currencyWidth=CardTypography.Width(less?"<$":"$",currencySize,dpi,rounded:true);
            double integerWidth=CardTypography.Width(parts[0],integerSize,dpi,-3,rounded:true);
            double fractionWidth=CardTypography.Width("."+parts[1]+Snapshot.ValueSuffix,fractionSize,dpi,rounded:true);
            double overall=currencyWidth+3+integerWidth+2+fractionWidth,scale=Math.Min(1,468/overall);
            dc.PushTransform(new ScaleTransform(scale,scale,36,baseline));
            Text(dc,less?"<$":"$",x,baseline-CardTypography.Ascent(currencySize),currencySize,Ink(Secondary),rounded:true);x+=currencyWidth+3;
            Text(dc,parts[0],x,baseline-CardTypography.Ascent(integerSize),integerSize,Ink(),tracking:-3,rounded:true);x+=integerWidth+2;
            Text(dc,"."+parts[1]+Snapshot.ValueSuffix,x,baseline-CardTypography.Ascent(fractionSize),fractionSize,Ink(Secondary),rounded:true);dc.Pop();
            y+=compact?82:126;
            Text(dc,Snapshot.PartialPricing?"Known API value · USD":"API value · USD",36,y+2,12,Ink(Secondary));
            Text(dc,UsageCardSnapshot.Qualifiers[(int)Snapshot.Period],504,y+2,12,Ink(),right:true);
            y+=17+(compact?8:18);
            double tokenWidth=Text(dc,Snapshot.TokenLabel,36,y,13,Ink());
            Text(dc,"  ·  "+Snapshot.ActivityLabel,36+tokenWidth,y,13,Ink(Secondary));y+=16;
        } else {
            var tokens=UsageCardSnapshot.CompactTokens(Snapshot.TotalTokens);
            double size=compact?94:112;
            y+=compact?0:2;
            double valueWidth=CardTypography.Width(tokens.Value,size,dpi,-3,rounded:true),unitWidth=CardTypography.Width(tokens.Unit,size,dpi,-2,rounded:true);
            double scale=Math.Min(1,468/Math.Max(1,valueWidth+4+unitWidth));
            dc.PushTransform(new ScaleTransform(scale,scale,36,y+CardTypography.Ascent(size)));
            Text(dc,tokens.Value,36,y,size,Ink(),tracking:-3,rounded:true);
            Text(dc,tokens.Unit,40+valueWidth,y,size,Ink(Secondary),tracking:-2,rounded:true);dc.Pop();
            y+=(compact?111:132)+(compact?0:2);
            double w2=Text(dc,Snapshot.TotalTokens==1?"token":"tokens",36,y,13,Ink());
            Text(dc,"  ·  "+Snapshot.ActivityLabel,36+w2,y,13,Ink(Secondary));y+=16;
        }
        double bottom=CardHeight-top;
        double footerHeight=44.5,footerTop=bottom-footerHeight;
        double disclaimer=Metric==CardMetric.ApiValue?(compact?21:25):0;
        int legendRows=(Snapshot.Providers.Length+1)/2;
        double legendHeight=Math.Max(0,legendRows*15+Math.Max(0,legendRows-1)*10);
        double legendTop=footerTop-(compact?14:24)-disclaimer-legendHeight;
        double flowTop=y+(compact?14:28),flowBottom=legendTop-(compact?14:24);
        Text(dc,Metric==CardMetric.ApiValue?"Cumulative API value":"Cumulative tokens",36,flowTop,11,Ink(Secondary));
        Text(dc,Snapshot.DurationLabel,504,flowTop,11,Ink(Secondary),right:true);
        Flow(dc,new Rect(36,flowTop+24,468,Math.Max(20,flowBottom-flowTop-24)));
        var providers=Snapshot.Ranked(Metric);
        for(int i=0;i<providers.Length;i++) {
            var item=providers[i];double x=36+(i%2)*246,ly=legendTop+(i/2)*25;
            dc.DrawEllipse(ParityTheme.Brush(ProviderColor(item.Id)),null,new Point(x+3.5,ly+7.5),3.5,3.5);
            Text(dc,ParityData.Provider(item.Id).Name,x+14,ly,12,Ink());
            string value=Metric==CardMetric.Tokens?Snapshot.Percent(item.Tokens):item.UnpricedTokens==item.Tokens?"Unpriced":UsageCardSnapshot.Money(item.Dollars)+(item.UnpricedTokens>0?"+":"");
            Text(dc,value,x+222,ly,12,Ink(Secondary),right:true);
        }
        if(Metric==CardMetric.ApiValue)Text(dc,"API-rate estimate, not a bill.",36,legendTop+legendHeight+(compact?8:12),10,Ink(Secondary));
        dc.DrawLine(new Pen(Ink(.18),.5),new Point(36,footerTop),new Point(504,footerTop));
        dc.PushOpacityMask(new ImageBrush(brand) {Stretch=Stretch.Uniform});dc.DrawRectangle(Ink(),null,new Rect(36,footerTop+20,17,17));dc.Pop();
        Text(dc,"CodexIsland",59,footerTop+20,14,Ink(),semibold:true,tracking:-.3);
        Text(dc,Metric==CardMetric.ApiValue?Snapshot.ValueChallenge:UsageCardSnapshot.CallsToAction[(int)Snapshot.Period],488,footerTop+12.5,11,Ink(),right:true);
        Arrow(dc,new Point(495,footerTop+16.5));
        Text(dc,"codexisland.com",504,footerTop+30.5,11,Ink(Secondary),right:true);
    }
    private void Flow(DrawingContext dc,Rect rect)
    {
        dc.PushTransform(new TranslateTransform(rect.X,rect.Y));
        double baseline=Math.Max(16,rect.Height-24),height=Math.Max(1,baseline-12),width=rect.Width-24;
        double total=Metric==CardMetric.ApiValue?Snapshot.TotalDollars:Snapshot.TotalTokens,max=Math.Max(total,.000001);
        int n=Snapshot.Days.Length;var indices=Snapshot.PointIndices;
        Point[] Points(double[] values)=>indices.Select(i=>new Point(12+width*i/n,baseline-height*values[i]/max)).ToArray();
        double[] boundary=new double[n+1];
        foreach(var provider in Snapshot.Ranked(Metric)) {
            var values=Snapshot.Cumulative(provider.Id,Metric);var upper=boundary.Zip(values,(a,b)=>a+b).ToArray();
            var lowerPoints=Points(boundary);var upperPoints=Points(upper);var color=ProviderColor(provider.Id);
            var band=new StreamGeometry();using(var c=band.Open()) {
                c.BeginFigure(upperPoints[0],true,true);AppendCurve(c,upperPoints);
                c.LineTo(lowerPoints[^1],true,false);AppendCurve(c,lowerPoints.Reverse().ToArray());
            }
            var gradient=new LinearGradientBrush {StartPoint=new Point(0,0),EndPoint=new Point(0,baseline),MappingMode=BrushMappingMode.Absolute};
            gradient.GradientStops.Add(new GradientStop(color,0));gradient.GradientStops.Add(new GradientStop(Color.FromArgb(179,color.R,color.G,color.B),.5));gradient.GradientStops.Add(new GradientStop(Color.FromArgb(31,color.R,color.G,color.B),1));
            dc.DrawGeometry(gradient,null,band);dc.DrawGeometry(null,new Pen(ParityTheme.Brush(color),1.2),Curve(upperPoints));boundary=upper;
        }
        var ridge=Points(boundary);
        if(total>0) {
            dc.DrawGeometry(null,new Pen(Ink(.85),1.5),Curve(ridge));var markers=Snapshot.LabelIndices.Select(i=>i+1).ToHashSet();
            for(int i=0;i<indices.Length;i++)if(markers.Contains(indices[i]))dc.DrawEllipse(Ink(),null,ridge[i],2,2);
            dc.DrawEllipse(Ink(),null,ridge[^1],4,4);
        }
        dc.DrawLine(new Pen(Ink(.18),.5),new Point(12,baseline),new Point(rect.Width-12,baseline));
        foreach(int i in Snapshot.LabelIndices)Text(dc,Snapshot.ChartLabel(i),12+width*(i+1)/n,baseline+10,10,Ink(Secondary),right:i==n-1,center:i!=n-1,mono:true);
        dc.Pop();
    }
    private static Geometry Curve(Point[] points) {var g=new StreamGeometry();using(var c=g.Open()){c.BeginFigure(points[0],false,false);AppendCurve(c,points);}return g;}
    private static void AppendCurve(StreamGeometryContext c,Point[] points) {for(int i=1;i<points.Length;i++){double mid=(points[i-1].X+points[i].X)/2;c.BezierTo(new Point(mid,points[i-1].Y),new Point(mid,points[i].Y),points[i],true,false);}}
    private void Seal(DrawingContext dc,Rect rect,string label)
    {
        void Outline(Rect r,double opacity,double thickness) {
            var path=new StreamGeometry();using(var c=path.Open()){c.BeginFigure(new Point(r.X+10,r.Y),false,true);c.PolyLineTo([new(r.Right-10,r.Y),new(r.Right,r.Y+10),new(r.Right,r.Bottom-10),new(r.Right-10,r.Bottom),new(r.X+10,r.Bottom),new(r.X,r.Bottom-10),new(r.X,r.Y+10)],true,false);}dc.DrawGeometry(null,new Pen(Ink(opacity),thickness),path);
        }
        Outline(rect,.65,.75);rect.Inflate(-4,-4);Outline(rect,.18,.5);
        Text(dc,label,rect.X+rect.Width/2,rect.Y+rect.Height/2-18,21,Ink(),center:true,semibold:true,tracking:-.5,rounded:true,max:rect.Width-10);
        Text(dc,"CLUB",rect.X+rect.Width/2,rect.Y+rect.Height/2+7.5,8,Ink(),center:true,semibold:true,tracking:2.5);
    }
    private void Arrow(DrawingContext dc,Point top)
    {
        var ink=Ink();
        var pen=new Pen(ink,1.15) {StartLineCap=PenLineCap.Round,EndLineCap=PenLineCap.Round,LineJoin=PenLineJoin.Round};
        dc.DrawLine(pen,new Point(top.X,top.Y+6.5),new Point(top.X+6.5,top.Y));
        dc.DrawLine(pen,new Point(top.X+.5,top.Y),new Point(top.X+6.5,top.Y));
        dc.DrawLine(pen,new Point(top.X+6.5,top.Y),new Point(top.X+6.5,top.Y+6));
    }
    private double Text(DrawingContext dc,string text,double x,double y,double size,Brush brush,bool right=false,bool center=false,bool semibold=false,bool mono=false,double max=double.PositiveInfinity,double tracking=0,bool rounded=false)
        =>CardTypography.Draw(dc,text,x,y,size,brush,dpi,right,center,semibold,rounded,mono,max,tracking);
    public BitmapSource Bitmap()
    {
        Width=540;Height=CardHeight;Measure(new Size(540,CardHeight));Arrange(new Rect(0,0,540,CardHeight));UpdateLayout();
        var bitmap=new RenderTargetBitmap(1080,(int)(CardHeight*2),192,192,PixelFormats.Pbgra32);bitmap.Render(this);bitmap.Freeze();return bitmap;
    }
}

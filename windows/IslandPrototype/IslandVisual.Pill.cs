using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Media;

namespace IslandPrototype;

public sealed partial class IslandVisual
{
    internal double? PillPercent(DemoProvider provider)
    {
        double? used=UsageFeed.Primary(provider)?.Used;
        return used is double value&&double.IsFinite(value)?Math.Clamp(Remaining?100-value:value,0,100):null;
    }

    private void DrawPill(DrawingContext dc,double width)
    {
        var providers=Providers;
        for(int i=0;i<providers.Length;i++) {
            var provider=providers[i];
            bool left=providers.Length==2&&i==0;
            var center=PillMotion.IconCenter(width,providers.Length,i,1-PillShape);
            double? percent=PillPercent(provider);
            var severity=AlertSeverities.GetValueOrDefault(provider.Id);
            Color tint=severity==AlertSeverity.Critical?Color.FromRgb(229,72,77):severity==AlertSeverity.Warning?Color.FromRgb(245,165,36):provider.Color;
            const double radius=15.25;
            var track=new Pen(percent.HasValue?ParityTheme.Brush(tint,.22):ParityTheme.White(.3),2.25);
            if(!percent.HasValue)track.DashStyle=new DashStyle(new double[]{1.2,2.2},0);
            dc.DrawEllipse(null,track,center,radius,radius);
            if(percent is double value&&value>0) {
                var pen=new Pen(ParityTheme.Brush(tint),2.25) {StartLineCap=PenLineCap.Round,EndLineCap=PenLineCap.Round};
                if(value>=100)dc.DrawEllipse(null,pen,center,radius,radius);
                else {
                    double angle=value/100*2*Math.PI;
                    var start=new Point(center.X,center.Y-radius);
                    var end=new Point(center.X+Math.Sin(angle)*radius,center.Y-Math.Cos(angle)*radius);
                    var arc=new StreamGeometry();
                    using(var path=arc.Open()) {
                        path.BeginFigure(start,false,false);
                        path.ArcTo(end,new Size(radius,radius),0,value>50,SweepDirection.Clockwise,true,false);
                    }
                    arc.Freeze();dc.DrawGeometry(null,pen,arc);
                }
            }
            var metric=UsageFeed.Primary(provider);
            string amount=percent is double reading?$"{Math.Round(reading,MidpointRounding.AwayFromZero):0}%":"--";
            string reset=percent.HasValue?metric?.ResetAt!=null||IsDemo?metric?.Reset??Localizer.Text("No reset"):Localizer.Text("No reset"):Localizer.Text("No data");
            double textX=center.X+(left?-24:24);
            BaselineText(dc,amount,textX,24,13,percent.HasValue?ParityTheme.Brush(tint):ParityTheme.White(.5),true,true,left,max:44);
            BaselineText(dc,reset,textX,38,10,ParityTheme.White(percent.HasValue?.7:.45),false,true,left,max:44,minimumScale:.85);
        }
    }

    private void DrawProviderIcons(DrawingContext dc,double width)
    {
        var providers=Providers;
        double progress=Math.Clamp(1-PillShape,0,1),size=PillMotion.IconSize(progress);
        for(int i=0;i<providers.Length;i++) {
            var provider=providers[i];
            var center=PillMotion.IconCenter(width,providers.Length,i,progress);
            center.Y-=8*(1-ProviderOpacity);
            dc.PushOpacity(ProviderOpacity*(PillPercent(provider).HasValue?1:.5+.5*progress));
            Logo(dc,provider.Id,center.X-size/2,center.Y-size/2,size,provider.Color);
            dc.Pop();
        }
    }

    private string PillHelpAt(Point point)
    {
        var providers=Providers;
        var provider=providers.Length==2&&point.X>=ActualWidth/2?providers[1]:providers[0];
        var metric=UsageFeed.Primary(provider);
        string reading=PillPercent(provider) is double value
            ?$"{metric?.Label} · {Math.Round(value,MidpointRounding.AwayFromZero):0}% {Localizer.Text(Remaining?"remaining":"used")}"+(metric?.ResetAt!=null||IsDemo?$" · {metric?.Reset}":"")
            :Feed?.State(provider.Id)?.Message??Localizer.Text("No quota reading");
        return provider.Name+"\n"+reading+"\n"+Localizer.Text("Click to open usage");
    }
}

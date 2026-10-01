using System.Collections.Generic;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Effects;

namespace IslandPrototype;

internal sealed class DollarGlowLayer : DrawingVisual
{
    private sealed class Label : DrawingVisual
    {
        internal readonly DrawingVisual Text=new();
        internal readonly DropShadowEffect Inner=new() {ShadowDepth=0,BlurRadius=12,RenderingBias=RenderingBias.Performance};
        internal readonly DropShadowEffect Outer=new() {ShadowDepth=0,BlurRadius=28,RenderingBias=RenderingBias.Performance};
        internal Label(){Text.Effect=Inner;Effect=Outer;Children.Add(Text);}
    }
    private readonly List<Label> labels=new();
    private int index;
    internal Transform PageTransform {get=>Transform??Transform.Identity;set=>Transform=value;}
    internal void Begin(){index=0;Opacity=0;}
    internal void Draw(FormattedText text,Point position,Color color,double opacity,double scaleX=1,double scaleY=1)
    {
        if(index==labels.Count){var next=new Label();labels.Add(next);Children.Add(next);}
        var label=labels[index++];label.Opacity=1;
        label.Effect=label.Outer;label.Text.Transform=new ScaleTransform(scaleX,scaleY);
        label.Inner.BlurRadius=12;
        label.Inner.Color=color;label.Inner.Opacity=opacity;
        label.Outer.Color=color;label.Outer.Opacity=opacity*.5;
        label.Transform=new TranslateTransform(position.X,position.Y);
        using var dc=label.Text.RenderOpen();dc.DrawText(text,new Point());
    }
    internal void DrawGeometry(Geometry geometry,Color color,double opacity,double blur)
    {
        if(index==labels.Count){var next=new Label();labels.Add(next);Children.Add(next);}
        var label=labels[index++];label.Opacity=1;label.Effect=null;label.Transform=null;label.Text.Transform=null;
        label.Inner.Color=color;label.Inner.Opacity=opacity;label.Inner.BlurRadius=blur;
        using var dc=label.Text.RenderOpen();dc.DrawGeometry(ParityTheme.Brush(color),null,geometry);
    }
    internal void End(){for(int i=index;i<labels.Count;i++)labels[i].Opacity=0;}
}

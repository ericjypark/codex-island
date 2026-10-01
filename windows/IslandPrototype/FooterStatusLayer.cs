using System;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Threading;

namespace IslandPrototype;

// A retained layer lets the clock and dot update without rebuilding charts or calendar cells.
internal sealed class FooterStatusLayer : DrawingVisual
{
    internal const string TargetId="Refresh now";
    private readonly DrawingVisual text=new(),dot=new();
    private readonly DispatcherTimer timer;
    private readonly ScaleTransform press=new(),bump=new(),ringScale=new();
    private readonly DrawingGroup ring=new();
    private readonly SolidColorBrush background=new(Colors.White),labelBrush=new(Colors.White),ageBrush=new(Colors.White);
    private readonly Color teal=Color.FromRgb(61,214,140);
    private static readonly Typeface labelFace=new(new FontFamily(new Uri("pack://application:,,,/CodexIslandPrototype;component/"),"./Assets/Fonts/#Island Status"),FontStyles.Normal,FontWeight.FromOpenTypeWeight(650),FontStretches.Normal);
    private FooterStatus status=new("Idle");
    private double center,dpi=1;
    private bool showing,motion,hovered,focused,pressed,pulsing,ambientVisible=true;
    private string age="",culture="";
    private Point? pointer;
    internal Rect Bounds {get;private set;}=Rect.Empty;
    internal bool Loading=>status.Loading;
    internal string Spoken=>status.Notice??(Localizer.Text(status.Label)+(age.Length>0?" "+age:""));
    internal string Help=>status.Notice??Localizer.Text(TargetId);
    internal bool ClockRunning=>timer.IsEnabled;
    internal bool PulseRunning=>pulsing;
    internal int TextDrawCount {get;private set;}

    internal FooterStatusLayer()
    {
        Children.Add(text);Children.Add(dot);Transform=press;dot.Transform=bump;
        ring.Transform=ringScale;ring.Opacity=.11;ringScale.ScaleX=ringScale.ScaleY=1.48;
        using(var draw=ring.Open())draw.DrawEllipse(null,new Pen(new SolidColorBrush(teal),1),new Point(),3,3);
        timer=new DispatcherTimer(DispatcherPriority.Background) {Interval=TimeSpan.FromSeconds(1)};
        timer.Tick+=(_,_)=>UpdateAge();
    }
    internal void Update(FooterStatus next,double rowCenter,double pixelsPerDip,bool visible,bool animate,double opacity,Vector offset)
    {
        bool newStatus=next!=status,newLayout=center!=rowCenter||dpi!=pixelsPerDip||culture!=Localizer.Culture.Name;
        bool fresh=next.Active&&status.UpdatedAt.HasValue&&next.UpdatedAt!=status.UpdatedAt;
        status=next;center=rowCenter;dpi=pixelsPerDip;culture=Localizer.Culture.Name;
        showing=visible;motion=animate;Opacity=visible?opacity:0;Offset=offset;
        string nextAge=next.UpdatedAt is DateTimeOffset updated?FooterStatus.Relative(updated,DateTimeOffset.UtcNow,Localizer.IsChinese):"";
        if(newStatus||newLayout||age!=nextAge||Bounds.IsEmpty){age=nextAge;DrawText();DrawDot();}
        UpdateHover();UpdateActivity();
        if(fresh&&motion&&showing)Bump();
    }
    internal void Hide(){showing=false;Opacity=0;UpdateActivity();}
    internal void SetMotion(bool animate){motion=animate;UpdateActivity();if(!motion){SetColors(false);Animate(press,ScaleTransform.ScaleXProperty,1,0);Animate(press,ScaleTransform.ScaleYProperty,1,0);}}
    internal void SetAmbientVisible(bool visible){ambientVisible=visible;UpdateActivity();}
    internal void SetPointer(Point? point,bool keyboardFocus=false,bool down=false)
    {
        pointer=point;if(focused!=keyboardFocus){focused=keyboardFocus;DrawText();}bool nextPressed=down&&point is Point p&&Bounds.Contains(p)&&!Loading;
        if(pressed!=nextPressed){pressed=nextPressed;Animate(press,ScaleTransform.ScaleXProperty,pressed?.97:1,.12);Animate(press,ScaleTransform.ScaleYProperty,pressed?.97:1,.12);}
        UpdateHover();
    }
    private void UpdateAge()
    {
        if(status.UpdatedAt is not DateTimeOffset updated)return;
        string next=FooterStatus.Relative(updated,DateTimeOffset.UtcNow,Localizer.IsChinese);
        if(next==age)return;age=next;DrawText();DrawDot();UpdateHover();
    }
    private void DrawText()
    {
        TextDrawCount++;
        string label=Localizer.Text(status.Label);
        double ageWidth=age.Length>0?IslandTypography.Width(age,11,dpi,true,true):0;
        var labelText=new FormattedText(label,Localizer.Culture,FlowDirection.LeftToRight,labelFace,11,labelBrush,dpi);
        double labelWidth=labelText.WidthIncludingTrailingWhitespace;
        double labelLeft=770-ageWidth-(ageWidth>0?6:0)-labelWidth,dotX=labelLeft-9;
        Bounds=new Rect(dotX-9,center-9.5,776-(dotX-9),19);
        press.CenterX=Bounds.X+Bounds.Width/2;press.CenterY=center;
        bump.CenterX=0;bump.CenterY=0;dot.Offset=new Vector(dotX,center);
        using var draw=text.RenderOpen();
        draw.DrawRoundedRectangle(background,null,Bounds,5,5);
        if(focused)draw.DrawRoundedRectangle(null,new Pen(ParityTheme.White(.65),1),Bounds,4,4);
        double baseline=IslandTypography.RowBaseline(center,11);
        draw.PushTransform(new TranslateTransform(labelLeft,baseline-.5));
        draw.PushTransform(new ScaleTransform(1,IslandTypography.HeightScale(11,true,false)));
        draw.DrawText(labelText,new Point(0,-labelText.Baseline));draw.Pop();draw.Pop();
        if(ageWidth>0){
            // At 11 points Cascadia's bold weight and slightly taller cap height match SF Mono's small-text ink.
            var number=new FormattedText(age,Localizer.Culture,FlowDirection.LeftToRight,
                new Typeface(ParityTheme.NumberFont,FontStyles.Normal,FontWeights.Bold,FontStretches.Normal),11,ageBrush,dpi);
            draw.PushTransform(new TranslateTransform(770-ageWidth,baseline));
            draw.PushTransform(new ScaleTransform(IslandTypography.WidthScale(11,true,true),IslandTypography.HeightScale(11,true,true)*1.06));
            draw.DrawText(number,new Point(0,-number.Baseline));draw.Pop();draw.Pop();
        }
        SetColors(false);
    }
    private void UpdateHover()
    {
        bool next=pointer is Point p&&Bounds.Contains(p);
        if(hovered==next)return;hovered=next;SetColors(true);
    }
    private void SetColors(bool animate)
    {
        double labelOpacity=status.Label=="Synced"?(hovered?.85:.55):status.Label=="Idle"?(hovered?.7:.4):.55;
        // WPF gamma-corrects translucent glyph brushes, making white at .55 render near .71.
        // An opaque gray preserves the reference's actual ink luminance on this black surface.
        SetInk(labelBrush,labelOpacity,animate);
        SetInk(ageBrush,hovered?.95:.72,animate);
        Animate(background,Brush.OpacityProperty,hovered&&!Loading?.05:0,animate?.12:0);
    }
    private void SetInk(SolidColorBrush brush,double opacity,bool animate)
    {
        double behind=hovered&&!Loading?.05:0;
        byte value=(byte)Math.Round(255*(opacity+behind*(1-opacity)));
        Color color=Color.FromRgb(value,value,value);
        if(!motion||!animate){brush.BeginAnimation(SolidColorBrush.ColorProperty,null);brush.Color=color;}
        else brush.BeginAnimation(SolidColorBrush.ColorProperty,new ColorAnimation(color,TimeSpan.FromSeconds(.12)));
    }
    private void DrawDot()
    {
        using var draw=dot.RenderOpen();
        if(status.Active){draw.DrawEllipse(ParityTheme.Brush(teal,.9),null,new Point(),3,3);draw.DrawDrawing(ring);}
        else draw.DrawEllipse(ParityTheme.White(.25),null,new Point(),3,3);
        dot.Effect=status.Active?new DropShadowEffect {Color=teal,BlurRadius=6,ShadowDepth=0,Opacity=.55}:null;
    }
    private void UpdateActivity()
    {
        if(showing&&ambientVisible&&status.UpdatedAt.HasValue)timer.Start();else timer.Stop();
        bool next=showing&&ambientVisible&&motion&&status.Active;
        if(pulsing==next)return;pulsing=next;
        if(next){
            var duration=TimeSpan.FromSeconds(Math.PI/2.6);
            DoubleAnimation Breath(double from,double to)=>new(from,to,duration) {AutoReverse=true,RepeatBehavior=RepeatBehavior.Forever,EasingFunction=new SineEase {EasingMode=EasingMode.EaseInOut}};
            var scale=Breath(1.36,1.6);Timeline.SetDesiredFrameRate(scale,30);
            ringScale.BeginAnimation(ScaleTransform.ScaleXProperty,scale);ringScale.BeginAnimation(ScaleTransform.ScaleYProperty,scale);
            var opacity=Breath(.22,0);Timeline.SetDesiredFrameRate(opacity,30);ring.BeginAnimation(DrawingGroup.OpacityProperty,opacity);
        } else {
            ringScale.BeginAnimation(ScaleTransform.ScaleXProperty,null);ringScale.BeginAnimation(ScaleTransform.ScaleYProperty,null);
            ringScale.ScaleX=ringScale.ScaleY=1.48;ring.BeginAnimation(DrawingGroup.OpacityProperty,null);ring.Opacity=.11;
            bump.BeginAnimation(ScaleTransform.ScaleXProperty,null);bump.BeginAnimation(ScaleTransform.ScaleYProperty,null);
        }
    }
    private void Bump()
    {
        var animation=new DoubleAnimationUsingKeyFrames {Duration=TimeSpan.FromSeconds(.42)};
        animation.KeyFrames.Add(new EasingDoubleKeyFrame(1.18,KeyTime.FromTimeSpan(TimeSpan.FromSeconds(.14)),new CubicEase {EasingMode=EasingMode.EaseOut}));
        animation.KeyFrames.Add(new EasingDoubleKeyFrame(1,KeyTime.FromTimeSpan(TimeSpan.FromSeconds(.42)),new CubicEase {EasingMode=EasingMode.EaseOut}));
        Timeline.SetDesiredFrameRate(animation,30);bump.BeginAnimation(ScaleTransform.ScaleXProperty,animation);bump.BeginAnimation(ScaleTransform.ScaleYProperty,animation);
    }
    private void Animate(Animatable target,DependencyProperty property,double value,double seconds)
    {
        if(!motion||seconds==0){target.BeginAnimation(property,null);target.SetValue(property,value);return;}
        target.BeginAnimation(property,new DoubleAnimation(value,TimeSpan.FromSeconds(seconds)) {EasingFunction=new CubicEase {EasingMode=EasingMode.EaseOut}});
    }
}

using System;
using System.Linq;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Threading;

namespace IslandPrototype;

public sealed partial class IslandVisual
{
    public static readonly DependencyProperty ResetPopoverProgressProperty=Register("ResetPopoverProgress",0);
    public double ResetPopoverProgress {get=>(double)GetValue(ResetPopoverProgressProperty);set=>SetValue(ResetPopoverProgressProperty,value);}
    public static readonly DependencyProperty ResetBadgeHighlightProperty=Register("ResetBadgeHighlight",0);
    public double ResetBadgeHighlight {get=>(double)GetValue(ResetBadgeHighlightProperty);set=>SetValue(ResetBadgeHighlightProperty,value);}
    private readonly DrawingVisual resetPopover=new() {Effect=new DropShadowEffect {Color=Colors.Black,Opacity=.5,BlurRadius=16,ShadowDepth=8,Direction=270}};
    private readonly DispatcherTimer resetHide=new() {Interval=TimeSpan.FromMilliseconds(80)};
    private Rect resetBadge=Rect.Empty,resetCard=Rect.Empty;
    private bool resetPresented,resetHovered,resetHighlighted;
    private string resetHelp="";
    private readonly CodexResetCredits sampleResetCredits=new(2,[new("sample-1","available",DateTimeOffset.Now.AddDays(3).AddHours(4)),new("sample-2","available",DateTimeOffset.Now.AddDays(9).AddHours(1))]);
    private CodexResetCredits? ResetCredits=>IsDemo?sampleResetCredits:Feed?.State("codex")?.ResetCredits;
    private void InitializeResetPopover()
    {
        resetHide.Tick+=(_,_)=>{resetHide.Stop();if(!resetHovered&&!ResetHasFocus)SetResetPresented(false);};
        MouseLeave+=(_,_)=>{resetHovered=false;resetHide.Start();};
        LostKeyboardFocus+=(_,_)=>{if(!resetHovered)resetHide.Start();};
        Unloaded+=(_,_)=>DismissResetPopover(true);
    }
    private bool ResetHasFocus=>IsKeyboardFocusWithin&&FocusedTarget!=null&&(FocusedTarget==resetHelp||FocusedTarget.StartsWith(ResetExpirationPrefix,StringComparison.Ordinal));
    private string ResetExpirationPrefix=>Localizer.IsChinese?"Codex 重置到期日期：":"Codex reset expires ";
    private void UpdateResetFocus()
    {
        if(ResetHasFocus)SetResetPresented(true);else if(!resetHovered)resetHide.Start();
    }
    private void UpdateResetPointer(Point point)
    {
        point.Offset(-(ActualWidth-800)/2,8*(1-ContentOpacity));
        resetHovered=Expanded&&(resetBadge.Contains(point)||ResetPopoverProgress>0&&resetCard.Contains(point));
        if(resetHovered){SetResetPresented(true);ToolTip=null;}
        else if(resetPresented&&!resetHide.IsEnabled)resetHide.Start();
    }
    internal void SynchronizeResetPointer(Point? point)
    {
        if(point is Point position)UpdateResetPointer(position);
        else if(resetHovered){resetHovered=false;resetHide.Start();}
    }
    private void SetResetPresented(bool shown)
    {
        if(shown)resetHide.Stop();
        if(shown&&(resetBadge.IsEmpty||!Expanded))return;
        if(resetPresented==shown)return;
        resetPresented=shown;
        var animation=shown?ParityTheme.Ease(1,.18):ResetFade(0,.09);
        if(ReduceMotion)animation.Duration=TimeSpan.Zero;
        if(LowPower)Timeline.SetDesiredFrameRate(animation,30);
        BeginAnimation(ResetPopoverProgressProperty,animation);
        bool highlighted=resetHovered||resetPresented;
        if(resetHighlighted!=highlighted) {
            resetHighlighted=highlighted;
            var highlight=ResetFade(highlighted?1:0,.12);
            if(ReduceMotion)highlight.Duration=TimeSpan.Zero;
            if(LowPower)Timeline.SetDesiredFrameRate(highlight,30);
            BeginAnimation(ResetBadgeHighlightProperty,highlight);
        }
        InvalidateVisual();
    }
    private static DoubleAnimation ResetFade(double to,double seconds)=>new(to,TimeSpan.FromSeconds(seconds)) {EasingFunction=new BezierEase {X1=0,Y1=0,X2=.58,Y2=1}};
    internal bool DismissResetPopover(bool immediately=false)
    {
        bool wasOpen=resetPresented||ResetPopoverProgress>0;
        resetHide.Stop();resetHovered=false;
        SetResetPresented(false);
        if(immediately){BeginAnimation(ResetPopoverProgressProperty,null);ResetPopoverProgress=0;BeginAnimation(ResetBadgeHighlightProperty,null);ResetBadgeHighlight=0;resetHighlighted=false;}
        return wasOpen;
    }
    private void ResetBadge(DrawingContext dc,bool right,double nameX,double title,double chipWidth,Vector motionOffset)
    {
        var credits=ResetCredits;
        if(credits?.ShowBadge(DateTimeOffset.Now)!=true)return;
        string label=Localizer.IsChinese?$"{credits.AvailableCount} 次重置":credits.AvailableCount==1?"1 reset":$"{credits.AvailableCount} resets";
        resetHelp=(Localizer.IsChinese?$"{credits.AvailableCount} 次 Codex 重置可用":credits.AvailableCount==1?"1 Codex reset available":$"{credits.AvailableCount} Codex resets available")+(IsDemo?Localizer.IsChinese?"（示例）":" (sample)":"");
        double width=Measure(label,10,false,true)+28;
        double x=right?nameX-title-width-8:52+title+8+chipWidth+12;
        resetBadge=new Rect(x,9.5,width,19);
        double highlight=ResetBadgeHighlight;
        dc.DrawRoundedRectangle(ParityTheme.White(.05*highlight),null,resetBadge,5,5);
        ResetArrow(dc,x+6,14,.8+.2*highlight);
        BaselineText(dc,label,x+22,IslandTypography.RowBaseline(resetBadge.Top+resetBadge.Height/2,10),10,ParityTheme.White(.55+.3*highlight),false,true);
        resetBadge.Offset(motionOffset);
        AddTarget(resetBadge,resetHelp,()=>SetResetPresented(true));
    }
    private void RenderResetPopover(double width)
    {
        using var dc=resetPopover.RenderOpen();
        if(!Expanded||ContentOpacity<=0||resetBadge.IsEmpty) {resetCard=Rect.Empty;DismissResetPopover(true);return;}
        var credits=ResetCredits?.Available(DateTimeOffset.Now).Take(3).ToArray()??[];
        double progress=ResetPopoverProgress;
        if(progress<=0||credits.Length==0){resetCard=Rect.Empty;return;}
        double x=Math.Clamp(resetBadge.Right-210,8,582),y=resetBadge.Top+28;
        resetCard=new Rect(x,y,210,12+credits.Length*26+(credits.Length-1)*4);
        resetPopover.Transform=new TranslateTransform((width-800)/2,-8*(1-ContentOpacity));
        resetPopover.Opacity=progress*ContentOpacity;
        dc.PushTransform(new ScaleTransform(.97+.03*progress,.97+.03*progress,resetCard.Right,resetCard.Top));
        dc.DrawRoundedRectangle(Brushes.Black,null,resetCard,10,10);
        dc.DrawRoundedRectangle(ParityTheme.White(.04),new Pen(ParityTheme.White(.1),.5),resetCard,10,10);
        AddTarget(resetCard,resetHelp+". "+Localizer.Text("Hover to show reset expiration details"),()=>SetResetPresented(true));
        for(int index=0;index<credits.Length;index++) {
            double row=y+6+30*index;
            var bounds=new Rect(x+6,row,198,26);
            dc.DrawRoundedRectangle(ParityTheme.White(.05),null,bounds,6,6);
            ResetArrow(dc,x+14,row+9,.9);
            string expires=Localizer.Text("EXPIRES");double center=row+bounds.Height/2;
            BaselineText(dc,expires,x+32,IslandTypography.RowBaseline(center,10),10,ParityTheme.White(.4),true,tracking:.8);
            string date=credits[index].ExpiresAt.GetValueOrDefault().LocalDateTime.ToString(Localizer.IsChinese?"yyyy年M月d日":"MMM d, yyyy",Localizer.Culture);
            BaselineText(dc,date,x+196,IslandTypography.RowBaseline(center,11),11,ParityTheme.White(.95),true,true,true);
            AddTarget(bounds,ResetExpirationPrefix+date,()=>SetResetPresented(true));
        }
        dc.Pop();
    }
    private static void ResetArrow(DrawingContext dc,double x,double y,double opacity)
    {
        var path=new StreamGeometry();
        using(var c=path.Open()) {
            c.BeginFigure(new Point(x+1,y+3),false,false);
            c.ArcTo(new Point(x+2,y+8),new Size(4.3,4.3),0,true,SweepDirection.Clockwise,true,false);
            c.BeginFigure(new Point(x+1,y),false,false);c.LineTo(new Point(x+1,y+3.5),true,false);c.LineTo(new Point(x+4.5,y+3.5),true,false);
        }
        dc.DrawGeometry(null,new Pen(ParityTheme.Brush(ParityTheme.Codex,opacity),1) {StartLineCap=PenLineCap.Round,EndLineCap=PenLineCap.Round,LineJoin=PenLineJoin.Round},path);
    }
}

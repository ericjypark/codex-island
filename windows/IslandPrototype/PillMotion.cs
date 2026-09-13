using System;
using System.Windows;

namespace IslandPrototype;

internal sealed class PillMotion
{
    private readonly Spring expansion=new(),presence=new(),close=new();
    private readonly BezierEase fadeEase=new() {X1=0,Y1=0,X2=.58,Y2=1};
    private bool visible,expanded,edgeClose;
    private double closeDelay,fade=1,fadeFrom=1,fadeTarget=1,fadeElapsed,fadeDuration;
    internal PillMotion(){close.Snap(1);}
    internal double Expansion=>expansion.Value;
    internal double Presence=>presence.Value;
    internal double ExpansionVelocity=>expansion.Velocity;
    internal double PresenceVelocity=>presence.Velocity;
    internal double CloseProgress=>close.Value;
    internal double CloseVelocity=>close.Velocity;
    internal bool ClosingAtEdge=>edgeClose;
    internal bool Moving=>!expansion.Settled||!presence.Settled||!close.Settled||closeDelay>0||fade!=fadeTarget;
    internal double PanelHeight {get;set;}=ParityTheme.PanelHeight;
    internal double CompactWidth {get;set;}=296;
    internal double Top=>Mix(-Height(PanelHeight)-8,ParityTheme.PillTop*(1-Expansion)*(edgeClose?close.Value:1),Presence);
    internal double ContentOpacity=>Smooth((Expansion-.20)/.70)*fade;
    internal double ProviderOpacity=>fade;
    internal double PillOpacity=>(1-Smooth(Expansion/.55))*fade;
    internal double PillShape=>(1-Expansion)*(edgeClose?close.Value:1);
    internal double ShellOpacity=>edgeClose?Smooth(close.Value/.12):1;
    internal double Width(int count)=>Mix(CompactWidth,Mix(ParityTheme.PillWidth(count),ParityTheme.ExpandedWidth,Expansion),edgeClose?close.Value:1);
    internal double Height(double panelHeight)=>Mix(ParityTheme.HeaderHeight,Mix(ParityTheme.PillHeight,panelHeight,Expansion),edgeClose?close.Value:1);

    internal void Target(bool expand,bool show,bool immediate=false)
    {
        visible=show;
        if(immediate) {
            expanded=expand;edgeClose=false;closeDelay=0;close.Snap(1);fade=fadeFrom=fadeTarget=1;
            expansion.Snap(expand?1:0);presence.Snap(show?1:0);return;
        }
        if(!show&&(expanded&&Expansion>0||edgeClose)) {
            if(!edgeClose) {edgeClose=true;closeDelay=.020;}
            close.Target=0;
            StartFade(0,.10);
            return;
        }
        if(show) {
            expanded=expand;expansion.Target=expand?1:0;
            if(edgeClose){closeDelay=0;close.Target=1;StartFade(1,.28);}
        }
        presence.Target=show?1:0;
    }

    internal void Advance(double seconds)
    {
        if(seconds<=0)return;
        expansion.Advance(seconds,expanded?23:27);
        presence.Advance(seconds,visible?24:30);
        if(edgeClose) {
            double shapeSeconds=Math.Max(0,seconds-closeDelay);
            closeDelay=Math.Max(0,closeDelay-seconds);
            if(shapeSeconds>0)close.Advance(shapeSeconds,2*Math.PI/.30,.88);
            if(fade!=fadeTarget) {
                fadeElapsed=Math.Min(fadeDuration,fadeElapsed+seconds);
                fade=fadeElapsed>=fadeDuration?fadeTarget:Mix(fadeFrom,fadeTarget,fadeEase.Ease(fadeElapsed/fadeDuration));
            }
            if(close.Settled&&fade==fadeTarget) {
                if(!visible) {
                    expansion.Snap(0);presence.Snap(0);close.Snap(1);fade=fadeFrom=fadeTarget=1;
                }
                edgeClose=false;
            }
        }
        if(!visible&&!edgeClose&&presence.Settled)expansion.Snap(0);
    }

    private void StartFade(double target,double duration)
    {
        if(fadeTarget==target)return;
        fadeFrom=fade;fadeTarget=target;fadeElapsed=0;fadeDuration=duration;
    }

    internal static Point IconCenter(double width,int count,int index,double progress)
    {
        double start=count==1?-26:index==0?-22:22;
        double end=index==0?-366:366;
        return new Point(width/2+Mix(start,end,progress),Mix(26,19,progress));
    }
    internal static double IconSize(double progress)=>Mix(18,20,progress);
    private static double Mix(double from,double to,double progress)=>from+(to-from)*progress;
    private static double Smooth(double value){value=Math.Clamp(value,0,1);return value*value*(3-2*value);}

    private sealed class Spring
    {
        internal double Value,Velocity,Target;
        internal bool Settled=>Value==Target&&Velocity==0;
        internal void Snap(double value){Value=Target=value;Velocity=0;}
        internal void Advance(double seconds,double frequency,double damping=1)
        {
            if(Settled)return;
            double displacement=Value-Target;
            if(damping==1) {
                double coefficient=Velocity+frequency*displacement,decay=Math.Exp(-frequency*seconds);
                Value=Target+(displacement+coefficient*seconds)*decay;
                Velocity=(Velocity-frequency*coefficient*seconds)*decay;
            } else {
                double decayRate=damping*frequency,oscillation=frequency*Math.Sqrt(1-damping*damping);
                double coefficient=(Velocity+decayRate*displacement)/oscillation,decay=Math.Exp(-decayRate*seconds);
                double cos=Math.Cos(oscillation*seconds),sin=Math.Sin(oscillation*seconds);
                Value=Target+decay*(displacement*cos+coefficient*sin);
                Velocity=decay*((coefficient*oscillation-decayRate*displacement)*cos-(displacement*oscillation+decayRate*coefficient)*sin);
            }
            if(Value<0||Value>1){Value=Math.Clamp(Value,0,1);Velocity=0;}
            if(Math.Abs(Value-Target)<.0005&&Math.Abs(Velocity)<.01)Snap(Target);
        }
    }
}

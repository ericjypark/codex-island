using System;
using System.Diagnostics;
using System.Windows;
using System.Windows.Media;

namespace IslandPrototype;

public partial class MainWindow
{
    private readonly PillMotion pillMotion=new();
    private bool shellMoving;
    private long shellFrame;
    private TimeSpan shellRenderingTime=TimeSpan.MinValue;
    private double motionPanelHeight=ParityTheme.PanelHeight;

    private void AnimateShell(bool expanded,bool visible,bool animate)
    {
        if(!shellMoving) {
            motionPanelHeight=pillMotion.Expansion>.001
                ?ParityTheme.PillHeight+(Island.Height-ParityTheme.PillHeight)/pillMotion.Expansion:Surface.PanelHeight;
            Island.BeginAnimation(WidthProperty,null);Island.BeginAnimation(HeightProperty,null);
            Slide.BeginAnimation(TranslateTransform.YProperty,null);
        }
        if(pillMotion.Expansion==0||expanded&&(!animate||MotionOff))motionPanelHeight=Surface.PanelHeight;
        pillMotion.PanelHeight=motionPanelHeight;
        pillMotion.CompactWidth=preferences.Value.NotchWidth+76;
        pillMotion.Target(expanded,visible,!animate||MotionOff);
        ApplyShellFrame();
        if(!pillMotion.Moving){StopShellMotion();return;}
        if(shellMoving)return;
        shellMoving=true;shellFrame=Stopwatch.GetTimestamp();shellRenderingTime=TimeSpan.MinValue;
        CompositionTarget.Rendering+=AnimateShellFrame;
    }

    private void AnimateShellFrame(object? sender,EventArgs args)
    {
        if(args is RenderingEventArgs rendering) {
            if(shellRenderingTime==rendering.RenderingTime)return;
            shellRenderingTime=rendering.RenderingTime;
        }
        long now=Stopwatch.GetTimestamp();
        double elapsed=Stopwatch.GetElapsedTime(shellFrame,now).TotalSeconds;
        if(elapsed<(EffectiveLowPower?1.0/30-.001:1.0/240))return;
        shellFrame=now;
        pillMotion.Advance(elapsed);ApplyShellFrame();
        if(pillMotion.Moving)return;
        StopShellMotion();
        if(state==IslandState.Expanded&&Math.Abs(Island.Height-Surface.PanelHeight)>.01)ResizePanel();
    }

    private void ApplyShellFrame()
    {
        Island.Width=pillMotion.Width(preferences.Value.SelectedProviders.Length);
        Island.Height=pillMotion.Height(motionPanelHeight);
        Slide.Y=pillMotion.Top;
        Shell.Opacity=pillMotion.ShellOpacity;
        Surface.PillShape=pillMotion.PillShape;
        Surface.ProviderOpacity=pillMotion.ProviderOpacity;
        Surface.ContentOpacity=pillMotion.ContentOpacity;
        Surface.PillOpacity=pillMotion.PillOpacity;
        PanelShadow.Opacity=pillMotion.Presence*(.28+.22*pillMotion.Expansion)*pillMotion.ProviderOpacity;
        if(handle!=0)SetClickBehavior(state!=IslandState.Hidden&&InIsland(latestPointer));
    }

    private void StopShellMotion()
    {
        if(!shellMoving)return;
        CompositionTarget.Rendering-=AnimateShellFrame;shellMoving=false;
    }
}

using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Automation.Provider;
using System.Windows.Threading;

namespace IslandPrototype;

internal sealed class IslandVisualPeer : FrameworkElementAutomationPeer,IValueProvider,IInvokeProvider
{
    private IslandVisual Surface=>(IslandVisual)Owner;
    public IslandVisualPeer(IslandVisual owner):base(owner){}
    internal void FocusChanged(string? previous,string? current)
    {
        foreach(var peer in GetChildren()??[]) {
            string id=peer.GetAutomationId();
            if(previous!=current&&id=="island-"+previous)peer.RaisePropertyChangedEvent(AutomationElementIdentifiers.HasKeyboardFocusProperty,true,false);
            if(id=="island-"+current) {
                if(previous!=current)peer.RaisePropertyChangedEvent(AutomationElementIdentifiers.HasKeyboardFocusProperty,false,true);
                peer.RaiseAutomationEvent(AutomationEvents.AutomationFocusChanged);
            }
        }
        if(current==null&&Surface.IsKeyboardFocusWithin)RaiseAutomationEvent(AutomationEvents.AutomationFocusChanged);
    }
    protected override string GetClassNameCore()=>"CodexIsland";
    protected override string GetNameCore()=>Surface.AccessibleDescription;
    protected override AutomationControlType GetAutomationControlTypeCore()=>Surface.Expanded?AutomationControlType.Pane:AutomationControlType.Button;
    protected override string GetHelpTextCore()=>Surface.Expanded?"":"Open usage. Each ring shows the selected provider's primary quota.";
    protected override string GetAcceleratorKeyCore()=>"Ctrl+Alt+I";
    protected override List<AutomationPeer> GetChildrenCore()
    {
        var peers=new List<AutomationPeer>();
        if(Surface.Expanded)foreach(var target in Surface.AccessibleTargets)peers.Add(new IslandActionPeer(Surface,target.Bounds,target.Help,target.Action));
        return peers;
    }
    public override object? GetPattern(PatternInterface patternInterface)=>patternInterface==PatternInterface.Value||patternInterface==PatternInterface.Invoke&&!Surface.Expanded?this:base.GetPattern(patternInterface);
    public void Invoke()=>Surface.Dispatcher.BeginInvoke(DispatcherPriority.Input,new Action(Surface.ExpandPill));
    public bool IsReadOnly=>true;
    public string Value=>Surface.AccessibleDescription;
    public void SetValue(string value)=>throw new InvalidOperationException("Usage values are read-only.");
}

internal sealed class IslandActionPeer : AutomationPeer,IInvokeProvider
{
    private readonly IslandVisual surface;
    private readonly Rect bounds;
    private readonly string name;
    private readonly Action action;
    public IslandActionPeer(IslandVisual surface,Rect bounds,string name,Action action){this.surface=surface;this.bounds=bounds;this.name=name;this.action=action;}
    public override object? GetPattern(PatternInterface patternInterface)=>patternInterface==PatternInterface.Invoke?this:null;
    public void Invoke()=>surface.Dispatcher.BeginInvoke(DispatcherPriority.Input,new Action(()=>{if(surface.TargetEnabled(name)&&surface.ContentOpacity>.9)action();}));
    protected override string GetAcceleratorKeyCore()=>"";
    protected override string GetAccessKeyCore()=>"";
    protected override AutomationControlType GetAutomationControlTypeCore()=>AutomationControlType.Button;
    protected override string GetAutomationIdCore()=>"island-"+name;
    protected override Rect GetBoundingRectangleCore()
    {
        if(!surface.IsVisible)return Rect.Empty;
        var a=surface.PointToScreen(bounds.TopLeft);var b=surface.PointToScreen(bounds.BottomRight);return new Rect(a,b);
    }
    protected override string GetClassNameCore()=>"IslandAction";
    protected override Point GetClickablePointCore(){var rect=GetBoundingRectangleCore();return new Point(rect.X+rect.Width/2,rect.Y+rect.Height/2);}
    protected override string GetHelpTextCore()=>surface.TargetHelp(name);
    protected override string GetItemStatusCore()=>"";
    protected override string GetItemTypeCore()=>"";
    protected override AutomationPeer? GetLabeledByCore()=>null;
    protected override string GetNameCore()=>surface.TargetName(name);
    protected override AutomationOrientation GetOrientationCore()=>AutomationOrientation.None;
    protected override bool HasKeyboardFocusCore()=>surface.IsKeyboardFocusWithin&&surface.FocusedTarget==name;
    protected override bool IsContentElementCore()=>true;
    protected override bool IsControlElementCore()=>true;
    protected override bool IsEnabledCore()=>surface.TargetEnabled(name);
    protected override bool IsKeyboardFocusableCore()=>true;
    protected override bool IsOffscreenCore()=>!surface.Expanded||surface.ContentOpacity<.9;
    protected override bool IsPasswordCore()=>false;
    protected override bool IsRequiredForFormCore()=>false;
    protected override void SetFocusCore()=>surface.FocusTarget(name);
    protected override List<AutomationPeer>? GetChildrenCore()=>null;
}

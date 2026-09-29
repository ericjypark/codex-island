using System;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;

namespace IslandPrototype;

public partial class MainWindow
{
    private readonly DispatcherTimer introductionTimer=new(){Interval=TimeSpan.FromSeconds(8)};
    private Border? introduction;
    private Button? introductionDone;
    private bool introductionVisible,introductionPending,introductionKeyboard;
    private int introductionGeneration;
    private nint introductionForeground;

    internal async void OfferIntroduction(bool replay=false)
    {
        if(closing||!replay&&preferences.Value.HasSeenIntroduction)return;
        if(replay){CompleteIntroduction();Dismiss();ProcessPointer();}
        introductionPending=true;introductionKeyboard=replay;
        int generation=++introductionGeneration;
        await Task.Delay(450);
        if(closing||generation!=introductionGeneration)return;
        TryShowIntroduction();
    }

    private void TryShowIntroduction()
    {
        if(!introductionPending||closing)return;
        if(ContextSuppressed){introductionKeyboard=false;return;}
        if(settingsWindow!=null||cardWindow!=null||state==IslandState.Expanded){CompleteIntroduction();return;}
        EnsureIntroduction();
        introductionPending=false;introductionVisible=true;
        introduction!.Visibility=Visibility.Visible;
        introduction.Width=Math.Clamp((target?.Bounds.Width??900)/screenScale-32,240,356);
        introduction.IsHitTestVisible=true;
        introduction.BeginAnimation(OpacityProperty,null);
        introduction.Opacity=MotionOff?1:0;
        introduction.BeginAnimation(OpacityProperty,ParityTheme.Ease(1,MotionOff?0:.18));
        SetState(IslandState.Peek);
        dismissTimer.Stop();
        if(introductionKeyboard) {
            introductionForeground=Native.GetForegroundWindow();
            SetClickBehavior(InIsland(latestPointer));Activate();introductionDone!.Focus();
        } else introductionTimer.Start();
        var peer=UIElementAutomationPeer.FromElement(introduction)??UIElementAutomationPeer.CreatePeerForElement(introduction);
        peer?.RaiseAutomationEvent(AutomationEvents.LiveRegionChanged);
        WriteState();
    }

    private void EnsureIntroduction()
    {
        if(introduction!=null)return;
        var content=new StackPanel();
        content.Children.Add(SettingsControls.Label("CodexIsland lives here",13,.95,true));
        var body=SettingsControls.Label("Hover at the top center to reveal the pill.\nClick it to see your AI usage.",12,.72);
        body.Margin=new Thickness(0,6,0,0);content.Children.Add(body);
        var actions=new Grid{Margin=new Thickness(0,14,0,0)};
        actions.ColumnDefinitions.Add(new ColumnDefinition());
        actions.ColumnDefinitions.Add(new ColumnDefinition{Width=GridLength.Auto});
        actions.ColumnDefinitions.Add(new ColumnDefinition{Width=GridLength.Auto});
        var shortcut=SettingsControls.Label(shortcutAvailable?"Ctrl+Alt+I":"Also in your system tray",10,.5);
        shortcut.VerticalAlignment=VerticalAlignment.Center;actions.Children.Add(shortcut);
        var connect=SettingsControls.Button("Connect accounts",()=>{
            CompleteIntroduction();
            if(usageFeed.IsDemo)SwitchDataMode(true);else OpenProviderSettings();
        },10,6);
        AutomationProperties.SetAutomationId(connect,"IntroductionConnect");
        Grid.SetColumn(connect,1);actions.Children.Add(connect);
        introductionDone=SettingsControls.Button("Got it",()=>{CompleteIntroduction();ProcessPointer();},10,6,true);
        introductionDone.Margin=new Thickness(6,0,0,0);
        AutomationProperties.SetAutomationId(introductionDone,"IntroductionDone");
        Grid.SetColumn(introductionDone,2);actions.Children.Add(introductionDone);
        content.Children.Add(actions);
        introduction=new IntroductionPanel {
            Width=356,Padding=new Thickness(16),CornerRadius=new CornerRadius(12),
            Background=new SolidColorBrush(Color.FromRgb(22,22,26)),BorderBrush=ParityTheme.White(.15),BorderThickness=new Thickness(1),
            HorizontalAlignment=HorizontalAlignment.Center,VerticalAlignment=VerticalAlignment.Top,
            Margin=new Thickness(0,ParityTheme.PillTop+ParityTheme.PillHeight+12,0,0),Child=content,
            Visibility=Visibility.Collapsed
        };
        AutomationProperties.SetAutomationId(introduction,"Introduction");
        AutomationProperties.SetName(introduction,Localizer.Text("CodexIsland lives here")+". "+body.Text);
        AutomationProperties.SetLiveSetting(introduction,AutomationLiveSetting.Polite);
        KeyboardNavigation.SetTabNavigation(introduction,KeyboardNavigationMode.Cycle);
        introduction.MouseEnter+=(_,_)=>introductionTimer.Stop();
        introduction.MouseLeave+=(_,_)=>ArmIntroductionDismissal();
        introduction.GotKeyboardFocus+=(_,_)=>introductionTimer.Stop();
        introduction.LostKeyboardFocus+=(_,_)=>Dispatcher.BeginInvoke(new Action(ArmIntroductionDismissal));
        introductionTimer.Tick+=(_,_)=>{
            introductionTimer.Stop();
            if(!introductionVisible||InIntroduction(latestPointer)||introduction.IsKeyboardFocusWithin)return;
            CompleteIntroduction();ProcessPointer();
        };
        ((Grid)Content).Children.Add(introduction);
    }

    private void ArmIntroductionDismissal()
    {
        if(!introductionVisible)return;
        if(InIntroduction(latestPointer)||introduction?.IsKeyboardFocusWithin==true)introductionTimer.Stop();
        else introductionTimer.Start();
    }

    private bool InIntroduction(Native.Point point)
    {
        if(!introductionVisible||introduction==null||ContextSuppressed)return false;
        return new Rect(introduction.RenderSize).Contains(introduction.PointFromScreen(new Point(point.X,point.Y)));
    }

    private void CompleteIntroduction()
    {
        if(!introductionVisible&&!introductionPending)return;
        bool restoreFocus=introductionVisible&&Native.GetForegroundWindow()==handle;
        StopIntroduction();
        if(restoreFocus&&introductionForeground!=0)Native.SetForegroundWindow(introductionForeground);
        introductionForeground=0;
        preferences.Update(preferences.Value with{HasSeenIntroduction=true});
        if(handle!=0){SetClickBehavior(state!=IslandState.Hidden&&InIsland(latestPointer));WriteState();}
    }

    private void SuspendIntroduction()
    {
        if(!introductionVisible)return;
        introductionTimer.Stop();
        introductionVisible=false;introductionPending=true;
        introductionKeyboard=false;introductionForeground=0;
        introduction!.Visibility=Visibility.Collapsed;
    }

    private void StopIntroduction()
    {
        introductionGeneration++;introductionTimer.Stop();
        introductionVisible=false;introductionPending=false;introductionKeyboard=false;
        if(introduction!=null){introduction.Visibility=Visibility.Collapsed;introduction.BeginAnimation(OpacityProperty,null);}
    }

    private sealed class IntroductionPanel:Border
    {
        protected override AutomationPeer OnCreateAutomationPeer()=>new FrameworkElementAutomationPeer(this);
    }
}

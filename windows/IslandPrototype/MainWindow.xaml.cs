using System;
using System.IO;
using System.Linq;
using System.Net.NetworkInformation;
using System.Threading.Tasks;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media.Animation;
using System.Windows.Media;
using System.Windows.Threading;
using Microsoft.Win32;
using Forms = System.Windows.Forms;
using Windows.System.Power;

namespace IslandPrototype;

public partial class MainWindow : Window
{
    private enum IslandState { Hidden, Peek, Expanded }
    private IslandState state = IslandState.Hidden;
    private readonly DispatcherTimer revealTimer = new() { Interval = TimeSpan.FromMilliseconds(200) };
    private readonly DispatcherTimer dismissTimer = new() { Interval = TimeSpan.FromMilliseconds(400) };
    private readonly Native.MouseProc mouseCallback;
    private readonly string diagnosticPath = DataPaths.File("state.json");
    private readonly PreferenceStore preferences = new(PreferenceStore.DefaultPath);
    private readonly CurrencyStore currency=new(DataPaths.File("currency-rates.json"));
    private readonly DispatcherTimer refreshTimer = new();
    private readonly DispatcherTimer usageRetryTimer = new();
    private readonly DispatcherTimer credentialTimer = new() {Interval=TimeSpan.FromSeconds(5)};
    private readonly DispatcherTimer updateTimer=new();
    private readonly AppUpdates appUpdates=new(new WindowsUpdateBackend(),DataPaths.File("app-updates.json"));
    private DateTimeOffset? nextExpectedRefresh;
    private DateTimeOffset? nextExpectedRetry,nextExpectedCredentialCheck;
    private bool networkEventsRegistered;
    private CliCredentialWatch? credentialWatch;
    private bool checkingCredentials;
    private readonly UsageFeed usageFeed=new(App.Live?new LiveUsageCoordinator(new ProviderUsageClient(new FileCliCredentials()),quotaHistory:new QuotaHistoryStore(DataPaths.File("quota-history.json"))):null,App.Live?new HistoryCoordinator():null);
    private readonly AlertEngine alerts=new();
    private readonly PageScrollGesture pageScroll=new();
    private bool pulseHolding;
    private int pulseCount;
    private Color? haloTintTarget;
    private double haloOpacityTarget=double.NaN;
    private Forms.NotifyIcon? tray;
    private System.Drawing.Icon? trayIcon;
    private PreviewSettings? settingsWindow;
    private UsageCardStudio? cardWindow;
    private nint handle, mouseHook, previousForeground;
    private HwndSource? source;
    private WindowContext? windowContext;
    private bool fullscreen,cloaked,sessionLocked,suspended;
    private bool ContextSuppressed=>fullscreen||cloaked||sessionLocked||suspended;
    private Forms.Screen? target;
    private double screenScale = 1;
    private Native.Point latestPointer;
    private int feedbackGeneration;
    private bool moveQueued, closing, suppressUntilExit, reducedMotion;
    private bool systemLowPower, powerEventsRegistered;
    private bool EffectiveLowPower=>preferences.Value.LowPower||systemLowPower;
    private bool shortcutAvailable;

    public MainWindow()
    {
        InitializeComponent();
        Surface.PillShape=1;
        appUpdates.AutomaticChecks=preferences.Value.AutomaticUpdates;
        appUpdates.Changed+=OnAppUpdatesChanged;
        appUpdates.UpdateAvailable+=OnUpdateAvailable;
        updateTimer.Tick+=async (_,_)=>{
            updateTimer.Stop();
            if(closing||suspended)return;
            await appUpdates.CheckAsync(false);ArmUpdateTimer();
        };
        mouseCallback = OnGlobalMouse;
        Surface.Currency=currency;
        Surface.Feed=usageFeed;
        usageFeed.Changed+=OnUsageChanged;
        currency.Changed+=OnCurrencyChanged;
        Localizer.Language = preferences.Value.Language;
        ApplyPreferences(preferences.Value, preferences.Value);
        preferences.Changed += ApplyPreferences;
        refreshTimer.Tick += (_, _) => OnRefreshTimer();
        ArmRefreshTimer();
        usageRetryTimer.Tick+=(_,_)=>{
            usageRetryTimer.Stop();
            if(suspended||closing)return;
            if(WakeScheduling.IsOverdueFire(DateTimeOffset.UtcNow,nextExpectedRetry))DeferUsageAfterWake();
            else RefreshSource(false);
        };
        if(App.Live) {
            credentialWatch=new CliCredentialWatch(new FileCliCredentials().ChangeStamp);
            nextExpectedCredentialCheck=DateTimeOffset.UtcNow.AddSeconds(5);
            credentialTimer.Tick+=async (_,_)=>{
                bool overdue=WakeScheduling.IsOverdueFire(DateTimeOffset.UtcNow,nextExpectedCredentialCheck);
                nextExpectedCredentialCheck=DateTimeOffset.UtcNow.AddSeconds(5);
                if(checkingCredentials||closing||suspended||sessionLocked)return;
                if(overdue)DeferUsageAfterWake();
                if(usageFeed.InWakeGrace)return;
                checkingCredentials=true;
                try {
                    string[] changed=await Task.Run(credentialWatch.ChangedProviders);
                    foreach(string provider in changed)if(!closing)await usageFeed.RefreshAfterSignInAsync(provider);
                } finally {checkingCredentials=false;}
            };
            credentialTimer.Start();
        }
        Island.SizeChanged += (_, _) => UpdateShape();
        Surface.ShapeChanged += UpdateShape;
        Surface.PageRequested += ChangePage;
        Surface.ExpansionRequested += () => SetState(IslandState.Expanded);
        Surface.StyleRequested += CycleStyle;
        Surface.DetailChanged += () => {ResizePanel();WriteState();};
        Surface.SettingsRequested += OpenSettings;
        Surface.ProviderSettingsRequested += OpenProviderSettings;
        Surface.RefreshRequested += RefreshVisibleSource;
        Surface.ShareRequested += OpenCard;
        revealTimer.Tick += (_, _) =>
        {
            revealTimer.Stop();
            if (!suppressUntilExit && InTrigger(latestPointer)) SetState(IslandState.Peek);
        };
        dismissTimer.Tick += (_, _) =>
        {
            dismissTimer.Stop();
            if (state != IslandState.Hidden && !InIsland(latestPointer) && !InTrigger(latestPointer)) Dismiss();
        };
        SourceInitialized += OnReady;
        Closed += OnClosed;
    }

    private void OnReady(object? sender, EventArgs args)
    {
        handle = new WindowInteropHelper(this).Handle;
        source = HwndSource.FromHwnd(handle);
        source.AddHook(WindowMessage);
        SetClickBehavior(false);
        PositionOn(IslandDisplay.Resolve(preferences.Value.TargetDisplay).Screen);
        mouseHook = Native.SetWindowsHookEx(14, mouseCallback, Native.GetModuleHandle(null), 0);
        if (mouseHook == 0) throw new InvalidOperationException("Windows could not install cursor tracking.");
        windowContext=new WindowContext(handle,Dispatcher,UpdateWindowContext);
        UpdateWindowContext();
        shortcutAvailable = Native.RegisterHotKey(handle, 1, 0x4003, 0x49);
        SystemEvents.DisplaySettingsChanged += OnDisplaysChanged;
        SystemEvents.SessionSwitch += OnSessionSwitch;
        SystemEvents.PowerModeChanged += OnPowerChanged;
        if(App.Live) {
            try {
                NetworkChange.NetworkAvailabilityChanged+=OnNetworkAvailabilityChanged;networkEventsRegistered=true;
                _=usageFeed.NetworkChangedAsync(NetworkInterface.GetIsNetworkAvailable(),preferences.Value.RefreshSeconds);
            }catch(Exception error)when(error is NetworkInformationException or PlatformNotSupportedException){}
        }
        try {
            PowerManager.EnergySaverStatusChanged+=OnEnergySaverChanged;
            powerEventsRegistered=true;
            UpdateSystemPower();
        } catch (System.Runtime.InteropServices.COMException) { }
        CreateTray();
        ArmUpdateTimer();
        Native.GetCursorPos(out latestPointer);
        if (preferences.Value.AlwaysShowUsage) SetState(IslandState.Peek);
        ProcessPointer();
        WriteState();
        _=currency.RefreshAsync();
        if(!usageFeed.IsDemo)RefreshSource(false);
    }

    private void CreateTray()
    {
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add(usageFeed.IsDemo?"Open sample usage":"Open usage", null, (_, _) => Dispatcher.Invoke(() => SetState(IslandState.Expanded)));
        menu.Items.Add("Hide island", null, (_, _) => Dispatcher.Invoke(()=>Dismiss()));
        var motion = new Forms.ToolStripMenuItem("Reduce motion") { CheckOnClick = true, Checked = preferences.Value.ReduceMotion };
        motion.CheckedChanged += (_, _) => preferences.Update(preferences.Value with { ReduceMotion = motion.Checked });
        menu.Items.Add(motion);
        menu.Items.Add(usageFeed.IsDemo?"Use live accounts":"Preview sample usage",null,(_,_)=>Dispatcher.Invoke(()=>SwitchDataMode(usageFeed.IsDemo)));
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add(Localizer.Text("Settings")+"…",null,(_,_)=>Dispatcher.Invoke(OpenGeneralSettings));
        menu.Items.Add(Localizer.Text("Show introduction"),null,(_,_)=>Dispatcher.Invoke(()=>OfferIntroduction(true)));
        menu.Items.Add("Check for updates…",null,(_,_)=>Dispatcher.Invoke(()=>{OpenGeneralSettings();_=appUpdates.CheckAsync(true);}));
        menu.Items.Add(Localizer.Text("Quit"), null, (_, _) => Dispatcher.Invoke(Close));
        tray = new Forms.NotifyIcon
        {
            Icon = LoadTrayIcon(),
            Text = usageFeed.IsDemo?"CodexIsland - sample data":DataPaths.IsCustom?"CodexIsland Preview - separate history profile":"CodexIsland",
            Visible = true,
            ContextMenuStrip = menu
        };
        SystemEvents.UserPreferenceChanged+=OnThemeChanged;
        tray.DoubleClick += (_, _) => Dispatcher.Invoke(() => SetState(IslandState.Expanded));
        tray.BalloonTipClicked+=(_,_)=>Dispatcher.Invoke(OpenGeneralSettings);
    }

    private System.Drawing.Icon LoadTrayIcon()
    {
        using var key=Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        string theme=key?.GetValue("SystemUsesLightTheme") is int value&&value==1?"light":"dark";
        using var resource=Application.GetResourceStream(new Uri($"/Assets/tray-{theme}.ico",UriKind.Relative)).Stream;
        trayIcon=new System.Drawing.Icon(resource);return trayIcon;
    }
    private void OnThemeChanged(object sender,UserPreferenceChangedEventArgs args)=>Dispatcher.BeginInvoke(new Action(()=>{
        if(closing||tray==null)return;var previous=trayIcon;tray.Icon=LoadTrayIcon();previous?.Dispose();
        Surface.ReduceMotion=MotionOff;if(MotionOff)SettleMotion();UpdateAmbience();
    }));

    private nint OnGlobalMouse(int code, nint message, nint data)
    {
        if (code >= 0 && !closing)
        {
            var point = Marshal.PtrToStructure<Native.MouseData>(data).Point;
            if (message == 0x0200)
            {
                latestPointer = point;
                if (!moveQueued)
                {
                    moveQueued = true;
                    Dispatcher.BeginInvoke(DispatcherPriority.Input, new Action(() =>
                    {
                        moveQueued = false;
                        if (!closing) ProcessPointer();
                    }));
                }
            }
            else if (message == 0x0201 || message == 0x0204)
            {
                FrameDiagnostics.Mark("pointer-hook",Surface.Page,0);
                Dispatcher.BeginInvoke(DispatcherPriority.Input, new Action(() =>
                {
                    if (!closing && state == IslandState.Expanded && !InIsland(point)) Dismiss();
                }));
            }
        }
        return Native.CallNextHookEx(mouseHook, code, message, data);
    }

    private void ProcessPointer()
    {
        if (state == IslandState.Hidden)
        {
            var underPointer = Forms.Screen.FromPoint(new System.Drawing.Point(latestPointer.X, latestPointer.Y));
            var resolved = IslandDisplay.Resolve(preferences.Value.TargetDisplay, underPointer);
            if (target?.DeviceName != resolved.Screen.DeviceName) PositionOn(resolved.Screen);
        }
        if(ContextSuppressed){revealTimer.Stop();dismissTimer.Stop();SetClickBehavior(false);return;}
        bool trigger = InTrigger(latestPointer);
        bool inside = state != IslandState.Hidden && InIsland(latestPointer);
        SetClickBehavior(inside);
        // The first move can precede the overlay becoming interactive.
        if(state==IslandState.Expanded)Surface.SynchronizeResetPointer(inside?Surface.PointFromScreen(new Point(latestPointer.X,latestPointer.Y)):null);
        UpdateAmbience();
        ArmIntroductionDismissal();
        if (!trigger && !inside) suppressUntilExit = false;
        if (state == IslandState.Hidden)
        {
            if (trigger && !suppressUntilExit)
            {
                if (!revealTimer.IsEnabled) revealTimer.Start();
            }
            else revealTimer.Stop();
        }
        else if (state is IslandState.Peek or IslandState.Expanded)
        {
            if (inside || trigger || (state == IslandState.Peek && (preferences.Value.AlwaysShowUsage||pulseHolding||introductionVisible))) dismissTimer.Stop();
            else if(state==IslandState.Expanded) Dismiss();
            else if (!dismissTimer.IsEnabled) dismissTimer.Start();
        }
    }

    private bool InTrigger(Native.Point point)
    {
        if (target == null) return false;
        var bounds = target.Bounds;
        double halfWidth=ParityTheme.PillWidth(preferences.Value.SelectedProviders.Length)/2;
        double triggerHeight=state==IslandState.Hidden?4:ParityTheme.PillTop+ParityTheme.PillHeight;
        return Math.Abs(point.X - (bounds.Left + bounds.Width / 2.0)) <= halfWidth * screenScale
            && point.Y >= bounds.Top && point.Y < bounds.Top + triggerHeight * screenScale;
    }

    private bool InIsland(Native.Point point)
    {
        if (state == IslandState.Hidden || Island.Opacity < .05) return false;
        var local = Island.PointFromScreen(new Point(point.X, point.Y));
        return ParityTheme.Silhouette(Island.ActualWidth, Island.ActualHeight,Surface.PillShape).FillContains(local);
    }

    private void UpdateShape()
    {
        if(Island.ActualWidth<=0||Island.ActualHeight<=0)return;
        var shape=ParityTheme.Silhouette(Island.ActualWidth,Island.ActualHeight,Surface.PillShape);
        HaloShape.Data=shape;ShadowShape.Data=shape;Sweep.PillShape=Surface.PillShape;
    }

    private void SetClickBehavior(bool inside)
    {
        int previous = Native.GetWindowLong(handle, Native.ExtendedStyle);
        int next = previous | Native.ToolWindow;
        bool introductionHit=InIntroduction(latestPointer);
        next = state == IslandState.Expanded||introductionKeyboard ? next & ~Native.NoActivate : next | Native.NoActivate;
        next = inside||introductionHit ? next & ~Native.Transparent : next | Native.Transparent;
        if (next != previous) Native.SetWindowLong(handle, Native.ExtendedStyle, next);
    }

    private void PositionOn(Forms.Screen screen)
    {
        target = screen;
        var bounds = screen.Bounds;
        var monitor = Native.MonitorFromPoint(new Native.Point { X = bounds.Left + 1, Y = bounds.Top + 1 }, 2);
        screenScale = Native.GetDpiForMonitor(monitor, 0, out uint dpi, out _) == 0 ? dpi / 96.0 : 1;
        Native.SetWindowPos(handle, new nint(-1), bounds.Left + (bounds.Width - (int)(Width * screenScale)) / 2,
            bounds.Top, (int)(Width * screenScale), (int)(Height * screenScale), 0x0010);
        UpdateWindowContext();
    }

    private bool MotionOff => reducedMotion || !SystemParameters.ClientAreaAnimation;

    private void SetState(IslandState next,bool animate=true)
    {
        if(next!=IslandState.Expanded)pageScroll.Reset();
        if(ContextSuppressed)next=IslandState.Hidden;
        if (next == state || closing) return;
        if(next==IslandState.Expanded)CompleteIntroduction();
        revealTimer.Stop(); dismissTimer.Stop();
        var previous = state;
        state = next;
        bool expanded = next == IslandState.Expanded;
        if(next!=IslandState.Peek)pulseHolding=false;
        Surface.Expanded = expanded;
        Island.Cursor = expanded ? Cursors.Arrow : Cursors.Hand;
        if (next != IslandState.Expanded) feedbackGeneration++;
        AnimateShell(expanded,next!=IslandState.Hidden,animate&&!ContextSuppressed);
        if (next == IslandState.Hidden)
        {
            if (Native.GetForegroundWindow() == handle && previousForeground != 0)
                Native.SetForegroundWindow(previousForeground);
        }
        SetClickBehavior(next != IslandState.Hidden && InIsland(latestPointer));
        if (expanded)
        {
            Surface.StartCounter(MotionOff||Surface.Page!=1||Surface.CostStyle!=0);
            ShowDiscovery();
            previousForeground = Native.GetForegroundWindow();
            Activate(); Focus();
        }
        if (next == IslandState.Peek) {
            if (previous == IslandState.Expanded && Native.GetForegroundWindow() == handle && previousForeground != 0) Native.SetForegroundWindow(previousForeground);
            ProcessPointer();
        }
        UpdateAmbience();
        WriteState();
    }

    private void Fade(UIElement target, DependencyProperty property, double value, double duration, double delay = 0)
    {
        var animation=ParityTheme.Ease(value,MotionOff?0:duration,MotionOff?0:delay);
        if((property!=IslandVisual.ContentOpacityProperty&&property!=IslandVisual.SwapOpacityProperty)||value==0)animation.EasingFunction=new BezierEase {X1=0,Y1=0,X2=.58,Y2=1};
        target.BeginAnimation(property,animation);
    }

    private void Spring(FrameworkElement target, DependencyProperty property, double to, double response = .42, double damping = .82, double delay = 0)
    {
        target.BeginAnimation(property, new SpringAnimation {
            From = (double)target.GetValue(property), To = to, Response = response, Damping = damping, BeginTime = TimeSpan.FromSeconds(MotionOff ? 0 : delay),
            Duration = TimeSpan.FromSeconds(MotionOff ? 0 : .65)
        });
    }

    private void SettleMotion()
    {
        feedbackGeneration++;
        StopShellMotion();
        pillMotion.Target(state==IslandState.Expanded,state!=IslandState.Hidden,true);
        void Set(UIElement element,DependencyProperty property,double value){element.BeginAnimation(property,null);element.SetValue(property,value);}
        bool expanded=state==IslandState.Expanded,hidden=state==IslandState.Hidden;
        Set(Island,WidthProperty,expanded?800:ParityTheme.PillWidth(preferences.Value.SelectedProviders.Length));
        Set(Island,HeightProperty,expanded?Surface.PanelHeight:ParityTheme.PillHeight);
        Slide.BeginAnimation(TranslateTransform.YProperty,null);Slide.Y=hidden?ParityTheme.PillHiddenOffset:expanded?0:ParityTheme.PillTop;
        Shell.Opacity=1;
        Set(Surface,IslandVisual.ProviderOpacityProperty,1);
        Set(Surface,IslandVisual.ContentOpacityProperty,expanded?1:0);
        Set(Surface,IslandVisual.PillShapeProperty,expanded?0:1);
        Set(Surface,IslandVisual.LogoOpacityProperty,expanded?0:1);
        Set(Surface,IslandVisual.PillOpacityProperty,!expanded&&!hidden?1:0);
        Set(Surface,IslandVisual.PagePositionProperty,Surface.Page);
        Set(Surface,IslandVisual.SwapOpacityProperty,1);Set(Surface,IslandVisual.FeedbackOffsetProperty,0);
        PanelShadow.BeginAnimation(System.Windows.Media.Effects.DropShadowEffect.OpacityProperty,null);PanelShadow.Opacity=expanded?.5:hidden?0:.28;
        if(introductionVisible){introduction!.BeginAnimation(OpacityProperty,null);introduction.Opacity=1;}
    }

    private void ApplyPreferences(IslandPreferences previous, IslandPreferences next)
    {
        reducedMotion = next.ReduceMotion;
        SettingsControls.ReduceMotion = reducedMotion;
        currency.Selection=next.Currency;
        Surface.Preferences = next;
        usageFeed.Preferences=next;
        usageFeed.Select(next.SelectedProviders);
        Surface.ReduceMotion=MotionOff;
        Surface.LowPower=EffectiveLowPower;
        Surface.PreviousChartStyle = previous.ChartStyle; Surface.PreviousCostStyle = previous.CostStyle;
        Surface.ChartStyle = next.ChartStyle; Surface.CostStyle = next.CostStyle;
        Surface.Remaining = next.Remaining;
        Surface.HasCycled = next.Page == 0 ? next.HasCycledChart : next.HasCycledCost;
        Surface.Page = next.Page;
        UpdateAlerts();
        if(next.Page==1 && (previous.Page!=next.Page || previous.CostStyle!=next.CostStyle))Surface.StartCounter(MotionOff||Surface.Page!=1||Surface.CostStyle!=0);
        if (previous.Page != next.Page) Surface.BeginAnimation(IslandVisual.PagePositionProperty, ParityTheme.Ease(next.Page, MotionOff ? 0 : .36, page:true));
        else if (handle == 0) Surface.PagePosition = next.Page;
        if (previous.ChartStyle != next.ChartStyle || previous.CostStyle != next.CostStyle) {
            Surface.BeginAnimation(IslandVisual.SwapOpacityProperty, null); Surface.SwapOpacity = 0;
            Fade(Surface, IslandVisual.SwapOpacityProperty, 1, .22);
        }
        if(previous.RefreshSeconds!=next.RefreshSeconds)ArmRefreshTimer();
        if(previous.AutomaticUpdates!=next.AutomaticUpdates){appUpdates.AutomaticChecks=next.AutomaticUpdates;ArmUpdateTimer();}
        if (handle != 0) {
            if (previous.TargetDisplay != next.TargetDisplay) PositionOn(IslandDisplay.Resolve(next.TargetDisplay).Screen);
            if (previous.SelectedProviders.Length != next.SelectedProviders.Length && state != IslandState.Expanded && !shellMoving) Spring(Island, WidthProperty, ParityTheme.PillWidth(next.SelectedProviders.Length), .34, .9);
            if (previous.AlwaysShowUsage != next.AlwaysShowUsage) SetState(next.AlwaysShowUsage ? IslandState.Peek : IslandState.Hidden);
            ResizePanel();
        }
        if(MotionOff)SettleMotion();
        UpdateAmbience();
        Surface.InvalidateVisual();
        if(handle!=0)WriteState();
        if(handle!=0&&!previous.SelectedProviders.SequenceEqual(next.SelectedProviders))_=usageFeed.RefreshAsync(false,next.RefreshSeconds);
    }

    private void ChangePage(int page)
    {
        long started=FrameDiagnostics.Begin();
        feedbackGeneration++;
        if(!preferences.Value.HasNavigated)preferences.Update(preferences.Value with {HasNavigated=true});
        Surface.BeginAnimation(IslandVisual.FeedbackOffsetProperty,ParityTheme.Ease(0,MotionOff?0:.36,page:true));
        if (page == Surface.Page) return;
        if(page!=2)Surface.ClearSelection();
        preferences.Update(preferences.Value with { Page = page });
        FrameDiagnostics.End(started,"navigation",page,Surface.PagePosition);
    }

    private async void ShowDiscovery()
    {
        if(preferences.Value.HasNavigated || Surface.Page!=0 || MotionOff)return;
        int token=++feedbackGeneration;
        await Task.Delay(400);
        if(closing||token!=feedbackGeneration||state!=IslandState.Expanded)return;
        Surface.BeginAnimation(IslandVisual.FeedbackOffsetProperty,ParityTheme.Ease(-46,.36,page:true));
        await Task.Delay(580);
        if(closing||token!=feedbackGeneration||state!=IslandState.Expanded)return;
        Surface.BeginAnimation(IslandVisual.FeedbackOffsetProperty,ParityTheme.Ease(0,.36,page:true));
    }

    private async void Navigate(int direction)
    {
        int page=Surface.Page+direction;
        if(page>=0&&page<3){ChangePage(page);return;}
        if(MotionOff||Math.Abs(Surface.FeedbackOffset)>.01)return;
        int token=++feedbackGeneration;
        Surface.BeginAnimation(IslandVisual.FeedbackOffsetProperty,ParityTheme.Ease(direction>0?-12:12,.10));
        await Task.Delay(100);
        if(closing||token!=feedbackGeneration||state!=IslandState.Expanded)return;
        Surface.BeginAnimation(IslandVisual.FeedbackOffsetProperty,new SpringAnimation {From=Surface.FeedbackOffset,To=0,Response=.32,Damping=.62,Duration=TimeSpan.FromSeconds(.55)});
    }

    private void CycleStyle()
    {
        var value=preferences.Value;
        preferences.Update(Surface.Page == 0 ? value with { ChartStyle = (value.ChartStyle + 1) % 5, HasCycledChart = true }
            : value with { CostStyle = (value.CostStyle + 1) % 4, HasCycledCost = true });
    }

    private void UpdateAmbience()
    {
        if(Sweep==null)return;
        Color tint=alerts.Severity==AlertSeverity.Critical?Color.FromRgb(229,72,77):alerts.Severity==AlertSeverity.Warning?Color.FromRgb(245,165,36):Color.FromRgb(0,71,171);
        bool eventActive=InIsland(latestPointer)||alerts.Severity!=AlertSeverity.None||usageFeed.Loading||usageFeed.HistoryLoading;
        bool visible=state!=IslandState.Hidden&&!ContextSuppressed;
        Surface.AmbientVisible=visible;
        bool ambience=state==IslandState.Expanded||alerts.Severity!=AlertSeverity.None||usageFeed.Loading||usageFeed.HistoryLoading;
        Sweep.Tint=tint;Sweep.Active=visible&&ambience&&!MotionOff&&(!EffectiveLowPower||eventActive);
        if(haloTintTarget!=tint) {
            haloTintTarget=tint;
            Halo.BeginAnimation(System.Windows.Media.Effects.DropShadowEffect.ColorProperty,new ColorAnimation(tint,TimeSpan.FromSeconds(MotionOff?0:.45)) {EasingFunction=new BezierEase {X1=.42,Y1=0,X2=.58,Y2=1}});
        }
        double opacity=visible&&ambience&&(!EffectiveLowPower||eventActive)?.35:0;
        if(haloOpacityTarget!=opacity) {
            haloOpacityTarget=opacity;
            var animation=ParityTheme.Ease(opacity,MotionOff?0:.25);animation.EasingFunction=new BezierEase {X1=.42,Y1=0,X2=.58,Y2=1};
            Halo.BeginAnimation(System.Windows.Media.Effects.DropShadowEffect.OpacityProperty,animation);
        }
    }

    private void OnUsageChanged()
    {
        if(!Dispatcher.CheckAccess()){Dispatcher.BeginInvoke(new Action(OnUsageChanged));return;}
        if(closing)return;
        UpdateAlerts();Surface.InvalidateVisual();UpdateAmbience();settingsWindow?.RefreshProviderStatus();ScheduleUsageRetry();if(handle!=0)WriteState();
    }
    private void ScheduleUsageRetry()
    {
        usageRetryTimer.Stop();nextExpectedRetry=null;
        if(usageFeed.IsDemo||usageFeed.Loading)return;
        var retry=usageFeed.AutomaticRetryAt;
        if(retry is not DateTimeOffset date)return;
        nextExpectedRetry=date;
        usageRetryTimer.Interval=TimeSpan.FromSeconds(Math.Max(.1,(date-DateTimeOffset.UtcNow).TotalSeconds+.05));usageRetryTimer.Start();
    }
    private void UpdateAlerts()
    {
        var p=preferences.Value;
        var inputs=usageFeed.Providers.Select(provider=>{
            var metric=UsageFeed.Primary(provider);
            return new AlertWindow(provider.Id,p.SelectedProviders.Contains(provider.Id),metric?.Used,metric?.ResetAt,usageFeed.State(provider.Id)?.FromHistory==true);
        });
        var pulse=alerts.Update(inputs,p.AlertsEnabled,p.WarningPercent,p.CriticalPercent,usageFeed.HasUpdated,usageFeed.IsDemo&&!App.PreviewAlerts);
        Surface.AlertSeverities=alerts.ProviderSeverities;
        if(handle!=0&&pulse!=null)HandlePulse(pulse);
    }
    private async void HandlePulse(AlertPulse pulse)
    {
        if(closing||ContextSuppressed||state==IslandState.Expanded)return;
        pulseHolding=true;pulseCount++;dismissTimer.Stop();
        if(state==IslandState.Hidden)SetState(IslandState.Peek);
        WriteState();
        await Task.Delay(4000);
        if(closing)return;
        pulseHolding=false;WriteState();
        if(state!=IslandState.Peek||InIsland(latestPointer)||preferences.Value.AlwaysShowUsage)return;
        if(!closing&&state==IslandState.Peek&&!InIsland(latestPointer)&&!preferences.Value.AlwaysShowUsage)SetState(IslandState.Hidden);
    }
    private async void PreviewAlert(string mode)
    {
        if(!App.PreviewAlerts)return;
        if(mode=="Both in 3s") {
            await Task.Delay(3000);
            if(closing)return;
            mode="Both";
        }
        if(mode=="Demo"){usageFeed.Reset();return;}
        alerts.PreparePreview();usageFeed.Preview(preferences.Value.SelectedProviders,mode);
    }

    private void OnCurrencyChanged()
    {
        Surface.InvalidateVisual();
        settingsWindow?.RefreshCurrencyStatus();
        if(handle!=0)WriteState();
    }

    private void RefreshVisibleSource()
    {
        _=usageFeed.RefreshPageAsync(Surface.Page,preferences.Value.RefreshSeconds);
        ScheduleUsageRetry();Surface.InvalidateVisual();WriteState();
    }
    private void RefreshSource(bool manual=true)
    {
        _=currency.RefreshAsync();
        _=usageFeed.RefreshAsync(manual,preferences.Value.RefreshSeconds);
        ScheduleUsageRetry();
        Surface.InvalidateVisual();
        WriteState();
    }
    private void ArmRefreshTimer(DateTimeOffset? next=null)
    {
        refreshTimer.Stop();
        var now=DateTimeOffset.UtcNow;nextExpectedRefresh=next??now.AddSeconds(preferences.Value.RefreshSeconds);
        refreshTimer.Interval=TimeSpan.FromSeconds(Math.Max(.1,(nextExpectedRefresh.Value-now).TotalSeconds));
        if(!suspended&&!closing)refreshTimer.Start();
    }
    private void OnRefreshTimer()
    {
        if(suspended||closing)return;
        bool defer=WakeScheduling.IsOverdueFire(DateTimeOffset.UtcNow,nextExpectedRefresh)||usageFeed.InWakeGrace;
        ArmRefreshTimer();
        if(defer&&!usageFeed.IsDemo)usageFeed.Resume();else RefreshSource(false);
    }
    private void DeferUsageAfterWake()
    {
        usageFeed.Resume();
        ArmRefreshTimer(nextExpectedRefresh>DateTimeOffset.UtcNow?nextExpectedRefresh:null);
    }
    private void OnNetworkAvailabilityChanged(object? sender,NetworkAvailabilityEventArgs args)=>Dispatcher.BeginInvoke(new Action(()=>{
        if(closing)return;
        if(!suspended&&WakeScheduling.IsOverdueFire(DateTimeOffset.UtcNow,nextExpectedRefresh))DeferUsageAfterWake();
        _=usageFeed.NetworkChangedAsync(args.IsAvailable,preferences.Value.RefreshSeconds);
    }));

    private void ResizePanel()
    {
        if(shellMoving)return;
        if (state == IslandState.Expanded) {
            bool opening = Surface.PanelHeight > Island.ActualHeight;
            if (opening) Spring(Island, HeightProperty, Surface.PanelHeight, .36, .94);
            else Island.BeginAnimation(HeightProperty, ParityTheme.Ease(Surface.PanelHeight, MotionOff ? 0 : .20));
        }
    }

    private void OpenSettings()
    {
        CompleteIntroduction();
        Dismiss();
        if (settingsWindow != null) { settingsWindow.Activate(); return; }
        settingsWindow = new PreviewSettings(preferences, currency, () => { _=currency.RefreshAsync(true);_=usageFeed.RefreshPageAsync(1,preferences.Value.RefreshSeconds); }, OpenCard,App.PreviewAlerts?PreviewAlert:null,usageFeed,()=>RefreshSource(),appUpdates);
        settingsWindow.CheckUpdatesRequested += () => _=appUpdates.CheckAsync(true);
        settingsWindow.InstallUpdateRequested += () => {if(appUpdates.PrepareInstall(App.RestartArguments(settings:true)))Application.Current.Shutdown();};
        settingsWindow.RestartRequested += Restart;
        settingsWindow.DataModeRequested += SwitchDataMode;
        settingsWindow.Closed += (_, _) => settingsWindow = null;
        settingsWindow.Show();
        settingsWindow.Activate();
    }

    private void SwitchDataMode(bool live)
    {
        if(!preferences.Update(preferences.Value with {LiveMode=live,SettingsTab="providers"})) {
            IslandDialog.Show((Window?)settingsWindow??this,"Settings",preferences.Error??"Your settings could not be saved.","OK");return;
        }
        try {if(StartupRegistration.IsEnabled)StartupRegistration.Set(true,live);}
        catch(Exception error) when(error is UnauthorizedAccessException or System.Security.SecurityException or IOException) {
            IslandDialog.Show((Window?)settingsWindow??this,"Launch at Login","The data mode was saved, but the startup entry could not be updated. Toggle Launch at Login again to update it.","OK");
        }
        var app=(App)Application.Current;app.RestartLiveMode=live;app.RestartProviders=true;Restart();
    }

    internal void OpenProviderSettings()
    {
        preferences.Update(preferences.Value with {SettingsTab="providers"});OpenSettings();
    }

    internal void OpenGeneralSettings()
    {
        preferences.Update(preferences.Value with {SettingsTab="general"});OpenSettings();
    }
    private void OnAppUpdatesChanged()=>Dispatcher.BeginInvoke(new Action(()=>{if(!closing){ArmUpdateTimer();if(handle!=0)WriteState();}}));
    private void OnUpdateAvailable(string version)=>Dispatcher.BeginInvoke(new Action(()=>{
        if(!closing)tray?.ShowBalloonTip(5000,"CodexIsland "+version+" is available","Open Settings to download the update.",Forms.ToolTipIcon.Info);
    }));
    private void ArmUpdateTimer()
    {
        updateTimer.Stop();
        if(closing||suspended||!appUpdates.AutomaticChecks||appUpdates.State.Busy||appUpdates.State.Phase is AppUpdatePhase.Unavailable or AppUpdatePhase.Ready)return;
        updateTimer.Interval=TimeSpan.FromSeconds(Math.Max(15,(appUpdates.NextAutomaticCheck-DateTimeOffset.UtcNow).TotalSeconds));updateTimer.Start();
    }

    private void Restart()
    {
        ((App)Application.Current).RestartRequested=true;
        Application.Current.Shutdown();
    }

    private void OpenCard()
    {
        Dismiss();
        if(cardWindow!=null){if(cardWindow.WindowState==WindowState.Minimized)cardWindow.WindowState=WindowState.Normal;cardWindow.Activate();return;}
        cardWindow=new UsageCardStudio(preferences,usageFeed);cardWindow.Closed+=(_,_)=>cardWindow=null;cardWindow.Show();cardWindow.Activate();
    }

    private void Dismiss(bool animate=true)
    {
        CompleteIntroduction();
        suppressUntilExit = InTrigger(latestPointer)||InIsland(latestPointer);
        pulseHolding=false;
        SetState(preferences.Value.AlwaysShowUsage ? IslandState.Peek : IslandState.Hidden,animate);
    }

    private void OnIslandClick(object sender, MouseButtonEventArgs args)
    {
        FrameDiagnostics.Mark("pointer-action",Surface.Page,0);
        if (state == IslandState.Peek) { SetState(IslandState.Expanded); args.Handled = true; }
        else if (state == IslandState.Expanded)
        {
            if ((Keyboard.Modifiers & ModifierKeys.Control) != 0 && Surface.Page < 2) CycleStyle();
            else Surface.ActivateAt(args.GetPosition(Surface));
            args.Handled = true;
        }
    }

    private void OnHideClick(object sender, RoutedEventArgs args) { Dismiss(); args.Handled = true; }
    private void OnKeyDown(object sender, KeyEventArgs args)
    {
        if(state==IslandState.Expanded && args.Key==Key.Tab){Surface.FocusNext((Keyboard.Modifiers&ModifierKeys.Shift)!=0);args.Handled=true;}
        else if(state==IslandState.Expanded && Surface.IsKeyboardFocusWithin && args.Key is Key.Enter or Key.Space){args.Handled=Surface.ActivateFocused();}
        else if(args.Key==Key.OemComma && Keyboard.Modifiers==ModifierKeys.Control){OpenSettings();args.Handled=true;}
        else if (args.Key == Key.Escape) { if(!Surface.DismissResetPopover())Dismiss(false); args.Handled = true; }
        else if (state == IslandState.Expanded && (Keyboard.Modifiers & ModifierKeys.Control) != 0 && args.Key >= Key.D1 && args.Key <= Key.D3)
        { ChangePage(args.Key - Key.D1); args.Handled = true; }
        else if (state == IslandState.Expanded && (args.Key == Key.Left || args.Key == Key.Right))
        { Navigate(args.Key == Key.Right ? 1 : -1); args.Handled = true; }
    }

    private nint WindowMessage(nint window, int message, nint wParam, nint lParam, ref bool handled)
    {
        if(message==0x0201)FrameDiagnostics.Mark("pointer-window",Surface.Page,0);
        if(message is 0x020A or 0x020E)FrameDiagnostics.Mark(message==0x020A?"wheel-vertical":"wheel-horizontal",Surface.Page,(short)((long)wParam>>16));
        if(message is 0x020A or 0x020E&&state==IslandState.Expanded&&!ContextSuppressed) {
            var pointer=new Native.Point{X=(short)((long)lParam&0xffff),Y=(short)((long)lParam>>16)};
            if(InIsland(pointer)) {
                int direction=pageScroll.Push((short)((long)wParam>>16),message==0x020E,System.Diagnostics.Stopwatch.GetTimestamp()*1000.0/System.Diagnostics.Stopwatch.Frequency);
                if(direction!=0)Navigate(direction);
                handled=true;return 0;
            }
        }
        if (message == 0x0021 && state != IslandState.Expanded&&!introductionKeyboard) {handled=true;return 3;}
        if (message == 0x0312 && wParam == 1)
        {
            if (state == IslandState.Expanded) Dismiss(false);
            else SetState(IslandState.Expanded,false);
            handled = true;
        }
        return 0;
    }

    private void OnDisplaysChanged(object? sender, EventArgs args) => Dispatcher.BeginInvoke(new Action(() =>
    {
        Dismiss();
        PositionOn(IslandDisplay.Resolve(preferences.Value.TargetDisplay).Screen);
        WriteState();
    }));
    private void UpdateWindowContext()
    {
        if(closing||windowContext==null||target==null)return;
        var current=windowContext.Read(target.Bounds);
        bool wasSuppressed=Island.Opacity==0;
        bool changed=fullscreen!=current.Fullscreen||cloaked!=current.Cloaked;
        fullscreen=current.Fullscreen;cloaked=current.Cloaked;
        if(ContextSuppressed!=wasSuppressed) {
            Island.Opacity=ContextSuppressed?0:1;
            if(ContextSuppressed) {
                SuspendIntroduction();
                revealTimer.Stop();dismissTimer.Stop();pulseHolding=false;
                SetState(IslandState.Hidden);SetClickBehavior(false);
            } else {
                TryShowIntroduction();
                if(preferences.Value.AlwaysShowUsage)SetState(IslandState.Peek);
                Native.GetCursorPos(out latestPointer);ProcessPointer();
            }
            UpdateAmbience();changed=true;
        }
        if(changed)WriteState();
    }
    private void OnSessionSwitch(object sender, SessionSwitchEventArgs args) => Dispatcher.BeginInvoke(new Action(()=>{
        if(args.Reason is SessionSwitchReason.SessionLock or SessionSwitchReason.ConsoleDisconnect or SessionSwitchReason.RemoteDisconnect)sessionLocked=true;
        else if(args.Reason is SessionSwitchReason.SessionUnlock or SessionSwitchReason.ConsoleConnect or SessionSwitchReason.RemoteConnect)sessionLocked=false;
        UpdateWindowContext();
    }));
    private void OnPowerChanged(object sender, PowerModeChangedEventArgs args) => Dispatcher.BeginInvoke(new Action(()=>{
        if(closing)return;
        if(args.Mode==PowerModes.Suspend){suspended=true;refreshTimer.Stop();usageRetryTimer.Stop();updateTimer.Stop();usageFeed.Suspend();}
        else {
            if(args.Mode==PowerModes.Resume){
                suspended=false;DeferUsageAfterWake();ArmUpdateTimer();
            }
            UpdateSystemPower();
        }
        UpdateWindowContext();
    }));
    private void OnEnergySaverChanged(object? sender,object args)=>Dispatcher.BeginInvoke(new Action(UpdateSystemPower));
    private void UpdateSystemPower()
    {
        if(closing)return;
        try {systemLowPower=PowerManager.EnergySaverStatus==EnergySaverStatus.On;}
        catch(System.Runtime.InteropServices.COMException){return;}
        Surface.LowPower=EffectiveLowPower;
        UpdateAmbience();if(handle!=0)WriteState();
    }

    private void WriteState()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(diagnosticPath)!);
        File.WriteAllText(diagnosticPath, JsonSerializer.Serialize(new
        {
            state = state.ToString(), updatedAt = DateTimeOffset.UtcNow, build = typeof(App).Assembly.ManifestModule.ModuleVersionId,
            appVersion=appUpdates.State.CurrentVersion,appUpdate=appUpdates.State,
            window = handle.ToInt64(), foreground = Native.GetForegroundWindow().ToInt64(),
            display = target?.DeviceName, scale = screenScale,
            screen = target?.Bounds, reducedMotion, preferences = preferences.Value,
            currency=currency.DisplayCurrency, currencyUpdatedAt=currency.LastUpdated, currencyError=currency.Error,
            renderTier = System.Windows.Media.RenderCapability.Tier >> 16,
            systemLowPower, effectiveLowPower=EffectiveLowPower, powerEventsRegistered,networkEventsRegistered,
            nextExpectedRefresh,wakeGrace=usageFeed.InWakeGrace,automaticRetryAt=usageFeed.AutomaticRetryAt,
            alertSeverity=alerts.Severity.ToString(),providerAlerts=alerts.ProviderSeverities,pulseHolding,pulseCount,previewAlerts=App.PreviewAlerts,sweepActive=Sweep.Active,
            contextSuppressed=ContextSuppressed,fullscreen,cloaked,sessionLocked,suspended,contextHooksAvailable=windowContext?.HooksAvailable??false,
            introductionVisible,introductionPending,
            sampleData = usageFeed.IsDemo,usageLoading=usageFeed.Loading,
            providerStatus=preferences.Value.SelectedProviders.Select(id=>new {id,status=usageFeed.State(id)?.Status.ToString(),loading=usageFeed.State(id)?.Loading??false,attemptedAt=usageFeed.State(id)?.AttemptedAt}),
            page = Surface.Page, chartStyle = Surface.ChartStyle, costStyle = Surface.CostStyle,
            panelWidth = state == IslandState.Expanded ? 800 : ParityTheme.PillWidth(preferences.Value.SelectedProviders.Length), panelHeight = state == IslandState.Expanded ? Surface.PanelHeight : ParityTheme.PillHeight,
            panelTop=state==IslandState.Expanded?0:ParityTheme.PillTop
        }));
    }

    private void OnClosed(object? sender, EventArgs args)
    {
        closing = true;
        StopIntroduction();
        StopShellMotion();
        Sweep.Active=false;
        revealTimer.Stop(); dismissTimer.Stop(); refreshTimer.Stop();usageRetryTimer.Stop();credentialTimer.Stop();
        updateTimer.Stop();appUpdates.Changed-=OnAppUpdatesChanged;appUpdates.UpdateAvailable-=OnUpdateAvailable;appUpdates.Dispose();
        preferences.Changed -= ApplyPreferences;
        usageFeed.Changed-=OnUsageChanged;
        usageFeed.Dispose();
        currency.Changed-=OnCurrencyChanged;currency.Dispose();
        settingsWindow?.Close();
        cardWindow?.Close();
        if (mouseHook != 0) Native.UnhookWindowsHookEx(mouseHook);
        windowContext?.Dispose();
        Native.UnregisterHotKey(handle, 1);
        SystemEvents.UserPreferenceChanged-=OnThemeChanged;
        SystemEvents.DisplaySettingsChanged -= OnDisplaysChanged;
        SystemEvents.SessionSwitch -= OnSessionSwitch;
        SystemEvents.PowerModeChanged -= OnPowerChanged;
        if(networkEventsRegistered)NetworkChange.NetworkAvailabilityChanged-=OnNetworkAvailabilityChanged;
        if(powerEventsRegistered)PowerManager.EnergySaverStatusChanged-=OnEnergySaverChanged;
        source?.RemoveHook(WindowMessage);
        if (tray != null) { tray.Visible = false; tray.ContextMenuStrip?.Dispose(); tray.Dispose(); }
        trayIcon?.Dispose();
    }
}

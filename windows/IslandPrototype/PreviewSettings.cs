using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Linq;
using System.IO;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Shell;
using System.Windows.Shapes;
using static IslandPrototype.SettingsControls;

namespace IslandPrototype;

internal sealed class PreviewSettings : Window
{
    private readonly PreferenceStore preferences;
    private readonly Action refresh,share;
    private readonly Action<string>? previewAlert;
    private readonly UsageFeed? feed;
    private readonly Action? refreshUsage;
    private readonly AppUpdates? appUpdates;
    private Action? updateBinding;
    private readonly List<Action> providerBindings=new();
    private readonly Dictionary<string,(bool Busy,string? Message)> accountActions=new();
    private bool observingAccounts;
    private bool historyBusy;
    private readonly HashSet<string> expandedQuota=new();
    private readonly CurrencyStore currency;
    private TextBlock? currencyStatus;
    private Button? currencyRefresh;
    private readonly StackPanel content=new();
    private readonly StackPanel tabs=new() { Orientation=Orientation.Horizontal, Margin=new Thickness(18,4,18,10) };
    private readonly List<Action> bindings=new();
    private readonly ScrollViewer scroll;
    private readonly TextBlock saveError=Label("",11,.7);
    private IslandPreferences P => preferences.Value;
    public event Action? CheckUpdatesRequested, RestartRequested, InstallUpdateRequested;
    public event Action<bool>? DataModeRequested;

    public PreviewSettings(PreferenceStore preferences,CurrencyStore currency,Action refresh,Action share,Action<string>? previewAlert=null,UsageFeed? feed=null,Action? refreshUsage=null,AppUpdates? appUpdates=null)
    {
        this.preferences=preferences;this.currency=currency;this.refresh=refresh;this.share=share;this.previewAlert=previewAlert;
        this.feed=feed;this.refreshUsage=refreshUsage;
        this.appUpdates=appUpdates;if(appUpdates!=null)appUpdates.Changed+=RefreshUpdates;
        Title="CodexIsland Settings";Width=480;Height=720;MinWidth=440;MinHeight=560;
        WindowStyle=WindowStyle.None;ResizeMode=ResizeMode.CanResize;WindowStartupLocation=WindowStartupLocation.CenterScreen;
        Background=new SolidColorBrush(Color.FromRgb(5,5,7));Foreground=Brushes.White;FontFamily=ParityTheme.TextFont;
        TextOptions.SetTextRenderingMode(this,TextRenderingMode.Grayscale);
        WindowChrome.SetWindowChrome(this,new WindowChrome {CaptionHeight=28,ResizeBorderThickness=new Thickness(5),CornerRadius=new CornerRadius(10),GlassFrameThickness=new Thickness(0),UseAeroCaptionButtons=false});
        MouseLeftButtonDown+=(_,e)=>{if(e.ChangedButton==MouseButton.Left){DragMove();e.Handled=true;}};
        SourceInitialized+=(_,_)=> {int dark=1;Native.DwmSetWindowAttribute(new WindowInteropHelper(this).Handle,20,ref dark,4);};
        var root=new Grid();
        root.RowDefinitions.Add(new RowDefinition {Height=GridLength.Auto});
        root.RowDefinitions.Add(new RowDefinition {Height=GridLength.Auto});
        root.RowDefinitions.Add(new RowDefinition {Height=GridLength.Auto});
        root.RowDefinitions.Add(new RowDefinition());
        root.RowDefinitions.Add(new RowDefinition {Height=GridLength.Auto});
        var top=new StackPanel();top.Children.Add(Caption());top.Children.Add(Brand());root.Children.Add(top);
        Grid.SetRow(tabs,1);root.Children.Add(tabs);
        var rule=new Border {Height=1,Background=ParityTheme.White(.055)};Grid.SetRow(rule,2);root.Children.Add(rule);
        scroll=new ScrollViewer {Content=content,VerticalScrollBarVisibility=ScrollBarVisibility.Hidden,HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled,CanContentScroll=false};
        Grid.SetRow(scroll,3);root.Children.Add(scroll);
        var bottom=new StackPanel();saveError.Margin=new Thickness(24,8,24,0);saveError.Visibility=Visibility.Collapsed;bottom.Children.Add(saveError);
        bottom.Children.Add(new Border {Height=1,Background=ParityTheme.White(.055)});bottom.Children.Add(Footer());Grid.SetRow(bottom,4);root.Children.Add(bottom);
        Content=new Border {Child=root,CornerRadius=new CornerRadius(10),Background=Background,BorderBrush=ParityTheme.White(.12),BorderThickness=new Thickness(.5)};
        preferences.Changed+=OnPreferencesChanged;
        CliAccountActions.Changed+=RefreshProviderStatus;
        Closed+=(_,_)=>{preferences.Changed-=OnPreferencesChanged;CliAccountActions.Changed-=RefreshProviderStatus;feed?.ObserveAccounts(false);if(appUpdates!=null)appUpdates.Changed-=RefreshUpdates;};
        Activated+=(_,_)=>RefreshProviderStatus();
        KeyDown+=(_,e)=>{if(e.Key==Key.Escape){Close();e.Handled=true;}};
        RenderPage();
    }

    private FrameworkElement Caption()
    {
        var row=new StackPanel {Orientation=Orientation.Horizontal,Height=28,Margin=new Thickness(12,0,0,0),HorizontalAlignment=HorizontalAlignment.Left};
        (Color Color,string Label,Action Action)[] controls=[(Color.FromRgb(255,95,87),"Close",Close),(Color.FromRgb(40,201,64),"Zoom",()=>WindowState=WindowState==WindowState.Maximized?WindowState.Normal:WindowState.Maximized)];
        foreach(var item in controls) {
            var button=Button(item.Label,item.Action,0,0,true);button.Width=12;button.Height=12;button.BorderThickness=new Thickness(0);button.Margin=new Thickness(0,0,8,0);
            button.Content=new Ellipse {Fill=ParityTheme.Brush(item.Color),Stroke=ParityTheme.Brush(Colors.Black,.12),StrokeThickness=.5,Width=12,Height=12};
            button.ToolTip=Localizer.Text(item.Label);WindowChrome.SetIsHitTestVisibleInChrome(button,true);row.Children.Add(button);
        }
        return row;
    }

    private FrameworkElement Brand()
    {
        var row=new Grid {Margin=new Thickness(24,16,24,22)};
        row.ColumnDefinitions.Add(new ColumnDefinition {Width=GridLength.Auto});row.ColumnDefinitions.Add(new ColumnDefinition());row.ColumnDefinitions.Add(new ColumnDefinition {Width=GridLength.Auto});
        var mark=Mark("codexisland",26);mark.Margin=new Thickness(0,0,12,0);row.Children.Add(mark);
        var words=new StackPanel {VerticalAlignment=VerticalAlignment.Center};words.Children.Add(Label("CodexIsland",14,.92,true));
        var tagline=Label("Your AI usage limits, living in your notch.");tagline.Margin=new Thickness(0,2,0,0);words.Children.Add(tagline);Grid.SetColumn(words,1);row.Children.Add(words);
        string version=typeof(App).Assembly.GetName().Version?.ToString(3)??"0.0.0";
        var badge=new Border {Child=Label("v"+version,11,.34,true,true),CornerRadius=new CornerRadius(20),Background=ParityTheme.White(.04),Padding=new Thickness(9,4,9,4),Margin=new Thickness(8,0,0,0),VerticalAlignment=VerticalAlignment.Center};
        Grid.SetColumn(badge,2);row.Children.Add(badge);return row;
    }

    private FrameworkElement Footer()
    {
        var row=new DockPanel {Margin=new Thickness(24,12,24,14),LastChildFill=false};
        foreach(var item in new[]{("GitHub","https://github.com/ericjypark/codex-island"),("License","https://github.com/ericjypark/codex-island/blob/main/LICENSE")}) {
            var button=Button(item.Item1+" ↗",()=>Process.Start(new ProcessStartInfo(item.Item2) {UseShellExecute=true}),0,2,true);
            button.Content=Label(item.Item1+" ↗",11,.55);button.Margin=new Thickness(0,0,14,0);row.Children.Add(button);
        }
        var quit=Button("Quit",()=>Application.Current.Shutdown(),11,5);quit.Background=ParityTheme.White(.03);quit.Content=Label("Quit",11,.55);DockPanel.SetDock(quit,Dock.Right);row.Children.Add(quit);return row;
    }

    private void OnPreferencesChanged(IslandPreferences previous,IslandPreferences next)
    {
        if(previous.SettingsTab!=next.SettingsTab || previous.LeftProvider!=next.LeftProvider || previous.RightProvider!=next.RightProvider) {
            double offset=scroll.VerticalOffset;RenderPage();if(previous.SettingsTab==next.SettingsTab)scroll.ScrollToVerticalOffset(offset);else scroll.ScrollToTop();
        } else {foreach(var binding in bindings.ToArray())binding();if(previous.QuotaSelections!=next.QuotaSelections)RefreshProviderStatus();}
    }
    private void Save(IslandPreferences value)
    {
        bool okay=preferences.Update(value);
        saveError.Text=preferences.Error??"";saveError.Visibility=okay?Visibility.Collapsed:Visibility.Visible;
    }
    private void RenderPage()
    {
        bool observe=P.SettingsTab=="providers"&&feed?.IsDemo==false;
        if(observingAccounts!=observe){observingAccounts=observe;feed?.ObserveAccounts(observe);if(observe)refreshUsage?.Invoke();}
        bindings.Clear();providerBindings.Clear();updateBinding=null;currencyStatus=null;currencyRefresh=null;content.Children.Clear();tabs.Children.Clear();
        foreach(var item in new[]{("General","general"),("Display","display"),("Providers","providers")}) {
            bool selected=P.SettingsTab==item.Item2;var button=Button(item.Item1,()=>Save(P with {SettingsTab=item.Item2}),12,6,true);
            button.Content=Label(item.Item1,12,selected?.95:.5);button.Margin=new Thickness(0,0,4,0);button.Background=ParityTheme.White(selected?.08:0);button.BorderBrush=ParityTheme.White(selected?.08:0);tabs.Children.Add(button);
        }
        if(P.SettingsTab=="general") General();else if(P.SettingsTab=="providers") Providers();else Display();
    }

    private StackPanel Section(string title,double top=14,double bottom=6,string? hint=null)
    {
        var panel=new StackPanel {Margin=new Thickness(14,top,14,bottom)};panel.Children.Add(SectionTitle(title,hint));content.Children.Add(panel);return panel;
    }
    private IslandToggle Toggle(string title,Func<IslandPreferences,bool> read,Func<IslandPreferences,bool,IslandPreferences> write)
    {
        var toggle=new IslandToggle(title,read(P),value=>Save(write(P,value)));
        bindings.Add(()=>{if(toggle.IsChecked!=read(P))toggle.IsChecked=read(P);});return toggle;
    }
    private FrameworkElement Segment(string title,string[] items,Func<IslandPreferences,int> selected,Action<int> change)
    {
        var segment=Segmented(title,items,selected(P),change);
        bindings.Add(()=> {
            var row=(Panel)((Border)segment).Child;
            for(int i=0;i<row.Children.Count;i++) {
                var button=(Button)row.Children[i];bool on=i==selected(P);
                var brush=new SolidColorBrush(Colors.White) {Opacity=button.Background.Opacity};button.Background=brush;
                brush.BeginAnimation(Brush.OpacityProperty,ParityTheme.Ease(on?.10:0,.12));
                button.BorderBrush=ParityTheme.White(on?.08:0);((TextBlock)button.Content).Foreground=TextBrush(on?.95:.55);
            }
        });return segment;
    }
    private FrameworkElement Picker(string title,(string Label,string Value)[] values,Func<IslandPreferences,string> selected,Action<string> change)
    {
        var holder=new ContentControl();void Update()=>holder.Content=Menu(title,values,selected(P),change);
        Update();bindings.Add(Update);return holder;
    }

    private void General()
    {
        var section=Section("General",18);
        var launch=new IslandToggle("Launch at Login",StartupRegistration.IsEnabled,value=> {
            try {StartupRegistration.Set(value);}catch(Exception error){IslandDialog.Show(this,"Launch at Login",error.Message,"OK");}
        });
        section.Children.Add(Row("Launch at Login","Open CodexIsland when you sign in.",launch));
        section.Children.Add(Row("Refresh interval","How often to refresh.",Segment("Refresh interval",["5m","15m","30m"],p=>Array.IndexOf(new[]{300,900,1800},p.RefreshSeconds),i=>Save(P with {RefreshSeconds=new[]{300,900,1800}[i]}))));
        section.Children.Add(Row("Language",P.Language=="auto"?"Follows Windows":P.Language=="en"?"English":"简体中文",Picker("Language",[("Auto","auto"),("English","en"),("简体中文","zh-Hans")],p=>p.Language,value=>{
            if(value==P.Language)return;Save(P with {Language=value});
            if(IslandDialog.Show(this,"Restart CodexIsland to apply language?","Your language change will take effect after CodexIsland restarts.","Restart now","Later"))RestartRequested?.Invoke();
        })));
        section.Children.Add(Row("Keep pill visible","When off, hover at the top center of your screen to reveal the pill.",Toggle("Keep pill visible",p=>p.AlwaysShowUsage,(p,v)=>p with {AlwaysShowUsage=v})));
        section.Children.Add(Row("Low Power Mode","Glow only on refresh, hover, or limit alerts.",Toggle("Low Power Mode",p=>p.LowPower,(p,v)=>p with {LowPower=v})));
        var extras=new StackPanel {Margin=new Thickness(14,0,14,0)};content.Children.Add(extras);
        extras.Children.Add(Row("Usage card","Your time with AI, ready to share.",Button("Create card…",share)));
        var recovery=Button("Recover Claude usage…",()=>{});recovery.IsEnabled=false;recovery.Opacity=.4;recovery.ToolTip=Localizer.Text(feed?.IsDemo==false?"Usage recovery is not available on Windows.":"Usage recovery is unavailable in demo mode.");
        extras.Children.Add(Row("Usage history","Find older Claude counts.",recovery));
        var backups=new StackPanel {Orientation=Orientation.Horizontal};
        var import=Button("Import…",()=>_=ManageHistory(false),9,5);
        var backup=Button("Back up…",()=>_=ManageHistory(true),9,5);backup.Margin=new Thickness(5,0,0,0);
        import.IsEnabled=backup.IsEnabled=feed?.CanManageHistory==true&&!historyBusy;
        if(feed?.CanManageHistory!=true)import.ToolTip=backup.ToolTip=Localizer.Text("Switch to live data to manage saved usage.");
        backups.Children.Add(import);backups.Children.Add(backup);
        extras.Children.Add(Row("History backup",historyBusy?"Working…":"Import Mac or Windows history.",backups));
        var alerts=Section("Alerts");
        alerts.Children.Add(Row("Approaching-limit alerts","Tint the island and pulse the peek pill when 5-hour usage nears your limit.",Toggle("Approaching-limit alerts",p=>p.AlertsEnabled,(p,v)=>p with {AlertsEnabled=v})));
        var thresholds=new StackPanel {Margin=new Thickness(10,8,10,8),IsEnabled=P.AlertsEnabled,Opacity=P.AlertsEnabled?1:.4};
        thresholds.Children.Add(Threshold("Warning",Color.FromRgb(245,165,36),p=>p.WarningPercent,(p,v)=>p with {WarningPercent=Math.Clamp(v,50,p.CriticalPercent-1)}));
        var critical=Threshold("Critical",Color.FromRgb(229,72,77),p=>p.CriticalPercent,(p,v)=>p with {CriticalPercent=Math.Clamp(v,p.WarningPercent+1,99)});critical.Margin=new Thickness(0,6,0,0);thresholds.Children.Add(critical);
        bindings.Add(()=>{thresholds.IsEnabled=P.AlertsEnabled;thresholds.BeginAnimation(OpacityProperty,ParityTheme.Ease(P.AlertsEnabled?1:.4,.28));});alerts.Children.Add(thresholds);
        if(previewAlert!=null) {
            var buttons=new StackPanel {Orientation=Orientation.Horizontal};
            foreach(string title in new[]{"Demo","Warn","Crit","Both","Both in 3s"})buttons.Children.Add(Button(title,()=>previewAlert(title),8,4));
            var preview=Row("Preview","Inject fixture percentages for the selected providers.",buttons);
            void UpdatePreview()=>preview.Visibility=P.AlertsEnabled?Visibility.Visible:Visibility.Collapsed;
            UpdatePreview();bindings.Add(UpdatePreview);alerts.Children.Add(preview);
        }
        var updates=Section("Updates");updates.Children.Add(Row("Check for updates automatically","Check for new versions in the background and notify you when one's available.",Toggle("Check for updates automatically",p=>p.AutomaticUpdates,(p,v)=>p with {AutomaticUpdates=v})));
        var check=Button("Check",()=>CheckUpdatesRequested?.Invoke());AutomationProperties.SetAutomationId(check,"CheckForUpdates");
        var download=Button("Download",()=>{if(appUpdates?.State.Phase==AppUpdatePhase.Ready)InstallUpdateRequested?.Invoke();else if(appUpdates!=null)_=appUpdates.DownloadAsync();});
        AutomationProperties.SetAutomationId(download,"ApplyUpdate");download.Margin=new Thickness(6,0,0,0);
        var actions=new StackPanel {Orientation=Orientation.Horizontal};actions.Children.Add(check);actions.Children.Add(download);
        updates.Children.Add(Row("App version",appUpdates?.State.CurrentVersion??typeof(App).Assembly.GetName().Version?.ToString(3)??"",actions));
        var status=Label("",11,.55);status.Margin=new Thickness(10,2,10,12);AutomationProperties.SetAutomationId(status,"UpdateStatus");updates.Children.Add(status);
        updateBinding=()=>{
            var state=appUpdates?.State;
            check.IsEnabled=state!=null&&!state.Busy&&state.Phase!=AppUpdatePhase.Unavailable;
            check.Opacity=check.IsEnabled?1:.4;
            bool ready=state?.Phase==AppUpdatePhase.Ready;
            string action=ready?"Restart and update":"Download";
            ((TextBlock)download.Content).Text=Localizer.Text(action);AutomationProperties.SetName(download,Localizer.Text(action));
            download.Visibility=state?.Phase is AppUpdatePhase.Available or AppUpdatePhase.Ready?Visibility.Visible:Visibility.Collapsed;
            status.Text=state?.Error??(state?.Phase switch {
                AppUpdatePhase.Checking=>"Checking for updates…",
                AppUpdatePhase.Current=>"You’re up to date.",
                AppUpdatePhase.Available=>"Version "+state.AvailableVersion+" is available.",
                AppUpdatePhase.Downloading=>"Downloading update… "+state.Progress+"%",
                AppUpdatePhase.Ready=>"Version "+state.AvailableVersion+" is ready. Restart to finish updating.",
                AppUpdatePhase.Installing=>"Restarting to install the update…",
                AppUpdatePhase.Idle=>state.LastChecked is { } date?"Last checked "+date.ToLocalTime().ToString("g"):"Check for a new version.",
                _=>"Install CodexIsland with the Windows installer to receive updates."
            });
        };updateBinding();
    }

    private void RefreshUpdates()=>Dispatcher.BeginInvoke(new Action(()=>updateBinding?.Invoke()));

    private async Task ManageHistory(bool backup)
    {
        if(historyBusy||feed?.CanManageHistory!=true)return;
        string path;
        if(backup) {
            var dialog=new Microsoft.Win32.SaveFileDialog{Title="Back up usage history",FileName="CodexIsland-history-"+DateTime.Today.ToString("yyyy-MM-dd")+".sqlite3",Filter="Usage history (*.sqlite3)|*.sqlite3",AddExtension=true,DefaultExt=".sqlite3",OverwritePrompt=true};
            if(dialog.ShowDialog(this)!=true)return;path=dialog.FileName;
        } else {
            var dialog=new Microsoft.Win32.OpenFileDialog{Title="Import usage history",Filter="Usage history (*.sqlite3;*.db)|*.sqlite3;*.db|All files (*.*)|*.*",CheckFileExists=true,Multiselect=false};
            if(dialog.ShowDialog(this)!=true)return;path=dialog.FileName;
        }
        historyBusy=true;double offset=scroll.VerticalOffset;RenderPage();scroll.ScrollToVerticalOffset(offset);
        try {
            if(backup) {
                bool saved=await feed.BackupHistoryAsync(path);
                if(IsVisible)IslandDialog.Show(this,"Usage history",saved?"Your usage history backup is saved. It contains usage counts, not conversations or credentials.":"There is no saved usage history to back up yet.","OK");
            } else {
                var result=await feed.ImportHistoryAsync(path);
                string message=$"Imported {result.AddedRecords:N0} usage records and {result.AddedDays:N0} recovered daily totals. Duplicate records were skipped.";
                if(result.BackupPath!=null)message+="\n\nYour previous history was backed up to:\n"+result.BackupPath;
                if(IsVisible)IslandDialog.Show(this,"Usage history imported",message,"OK");
            }
        }catch(Exception error) when(error is IOException or UnauthorizedAccessException or ArgumentException or InvalidOperationException or OperationCanceledException) {
            if(IsVisible)IslandDialog.Show(this,"Usage history",error is OperationCanceledException?"The history operation was canceled.":error.Message,"OK");
        }finally{historyBusy=false;if(IsVisible){offset=scroll.VerticalOffset;RenderPage();scroll.ScrollToVerticalOffset(offset);}}
    }

    private FrameworkElement Threshold(string title,Color color,Func<IslandPreferences,int> read,Func<IslandPreferences,int,IslandPreferences> write)
    {
        var row=new DockPanel {Margin=new Thickness(0,5,0,5),LastChildFill=false};
        var dot=new Ellipse {Width=7,Height=7,Fill=ParityTheme.Brush(color),Margin=new Thickness(0,0,10,0)};row.Children.Add(dot);row.Children.Add(Label(title,13,.92));
        var input=new TextBox {Text=read(P).ToString(),Width=22,Height=18,Background=Brushes.Transparent,BorderThickness=new Thickness(0),Foreground=ParityTheme.White(.95),FontFamily=ParityTheme.NumberFont,FontSize=11,FontWeight=FontWeights.SemiBold,TextAlignment=TextAlignment.Center,VerticalContentAlignment=VerticalAlignment.Center,SelectionBrush=ParityTheme.Brush(ParityTheme.Codex,.4),CaretBrush=Brushes.White};
        AutomationProperties.SetName(input,Localizer.Text(title)+" %");
        void Commit(){if(int.TryParse(input.Text,out int value))Save(write(P,value));input.Text=read(P).ToString();}
        input.LostKeyboardFocus+=(_,_)=>Commit();input.KeyDown+=(_,args)=>{if(args.Key==Key.Enter){Commit();args.Handled=true;}};
        bindings.Add(()=>{if(!input.IsKeyboardFocused)input.Text=read(P).ToString();});
        var valueRow=new StackPanel {Orientation=Orientation.Horizontal,HorizontalAlignment=HorizontalAlignment.Center,VerticalAlignment=VerticalAlignment.Center};valueRow.Children.Add(input);var suffix=Label("%",11,.55,true,true);suffix.Margin=new Thickness(3,0,0,0);valueRow.Children.Add(suffix);
        var border=new Border {Child=valueRow,Width=64,Height=28,Background=ParityTheme.White(.05),BorderBrush=ParityTheme.White(.1),BorderThickness=new Thickness(.5),CornerRadius=new CornerRadius(7)};
        DockPanel.SetDock(border,Dock.Right);row.Children.Add(border);return row;
    }

    private void Display()
    {
        var usage=Section("Usage display",18,14);
        usage.Children.Add(Row("Percentages and rings","Show used or remaining quota in the pill and expanded view.",Segment("Usage display",["Used","Remaining"],p=>p.Remaining?1:0,i=>Save(P with {Remaining=i==1}))));
        var charts=Section("Chart style",18,14,"Ctrl-click to cycle");charts.Children.Add(Tiles(false));
        var costs=Section("Cost view",14,14,"Ctrl-click to cycle");costs.Children.Add(Tiles(true));
        var target=Section("Target Display",14,14);var displays=IslandDisplay.All();
        var options=new List<(string,string)> {("Auto","auto")};options.AddRange(displays.Select(d=>(d.Name,d.Id)));
        var resolved=IslandDisplay.Resolve(P.TargetDisplay);
        target.Children.Add(Row("Show on",P.TargetDisplay=="auto"?$"Auto - currently on {resolved.Name}.":"Pinned to a specific display. Falls back to Auto if unplugged.",Picker("Target display",options.ToArray(),p=>p.TargetDisplay,id=>Save(P with {TargetDisplay=id}))));
    }

    private FrameworkElement Tiles(bool cost)
    {
        string[] labels=cost?["USD","VALUE","TOKENS","TREND"]:["Ring","Bar","Stepped","Numeric","Sparkline"];
        var row=new UniformGrid {Columns=labels.Length,Margin=new Thickness(7,4,7,0)};
        for(int i=0;i<labels.Length;i++) {
            int index=i;var body=new StackPanel {Margin=new Thickness(6,14,6,10)};body.Children.Add(new StylePreview {Kind=i,Cost=cost,Height=34});
            var label=Label(labels[i],10,.55);label.HorizontalAlignment=HorizontalAlignment.Center;label.Margin=new Thickness(0,7,0,0);body.Children.Add(label);
            var button=Button(labels[i],()=>Save(cost?P with {CostStyle=index,HasCycledCost=true}:P with {ChartStyle=index,HasCycledChart=true}),0,0,true);button.Content=body;button.Margin=new Thickness(3,0,3,0);button.BorderThickness=new Thickness(1);Template(button,9);row.Children.Add(button);
            void Update(){bool on=(cost?P.CostStyle:P.ChartStyle)==index;button.Background=on?ParityTheme.Brush(Color.FromRgb(0,71,171),.14):ParityTheme.White(.025);button.BorderBrush=on?ParityTheme.Brush(Color.FromRgb(0,71,171),.6):Brushes.Transparent;label.Foreground=on?ParityTheme.Brush(Color.FromRgb(148,191,255)):ParityTheme.White(.55);}
            Update();bindings.Add(Update);
        }
        return row;
    }

    private void Providers()
    {
        var panel=new StackPanel {Margin=new Thickness(24)};content.Children.Add(panel);
        panel.Children.Add(Label("On your island",15,.85,true));var subtitle=Label("Choose up to two providers.",12,.68);subtitle.Margin=new Thickness(0,6,0,18);panel.Children.Add(subtitle);
        var slots=new Grid();slots.ColumnDefinitions.Add(new ColumnDefinition());slots.ColumnDefinitions.Add(new ColumnDefinition {Width=new GridLength(52)});slots.ColumnDefinitions.Add(new ColumnDefinition());
        slots.Children.Add(ProviderSlot(0,P.LeftProvider));var right=ProviderSlot(1,P.RightProvider);Grid.SetColumn(right,2);slots.Children.Add(right);
        var swap=Button("Swap left and right",()=>Save(P.SwapProviders()),0,0,true);swap.Content=SettingsIcon("swap",16);swap.Width=32;swap.Height=44;swap.VerticalAlignment=VerticalAlignment.Bottom;swap.IsEnabled=P.RightProvider!=null;swap.Opacity=swap.IsEnabled?1:.3;AutomationProperties.SetName(swap,Localizer.Text("Swap left and right"));Grid.SetColumn(swap,1);slots.Children.Add(swap);panel.Children.Add(slots);
        panel.Children.Add(new Border {Height=1,Background=ParityTheme.White(.08),Margin=new Thickness(0,18,0,18)});
        foreach(string id in P.SelectedProviders) AddAccount(panel,id);
        var token=Section("Tokens",14,4);
        token.Children.Add(Row("Token counting",P.TokenMode=="all"?"Counts everything - input, output, and cache. Mirrors ccusage.":"Input + output only. Matches Anthropic's claude.ai stats.",Segment("Token counting",["All tokens","Input + output"],p=>p.TokenMode=="all"?0:1,i=>Save(P with {TokenMode=i==0?"all":"billable"}))));
        var cost=new Grid {Margin=new Thickness(24,14,24,14)};
        foreach(var width in new[]{GridLength.Auto,new GridLength(1,GridUnitType.Star),GridLength.Auto,GridLength.Auto})cost.ColumnDefinitions.Add(new ColumnDefinition {Width=width});
        var costTitle=new TrackedLabel {Text=Localizer.Text("Cost").ToUpper(Localizer.Culture),Size=10,Tracking=1.05,Opacity=.34,VerticalAlignment=VerticalAlignment.Center};cost.Children.Add(costTitle);
        var freshness=new StackPanel {Margin=new Thickness(10,0,8,0),VerticalAlignment=VerticalAlignment.Center};
        currencyStatus=Label("",11,.42);currencyStatus.TextWrapping=TextWrapping.NoWrap;currencyStatus.TextTrimming=TextTrimming.CharacterEllipsis;freshness.Children.Add(currencyStatus);
        var rate=Label("Rates by ExchangeRate-API",10,.34);rate.TextWrapping=TextWrapping.NoWrap;rate.TextTrimming=TextTrimming.CharacterEllipsis;rate.Margin=new Thickness(0,2,0,0);rate.Cursor=Cursors.Hand;rate.MouseLeftButtonUp+=(_,_)=>Process.Start(new ProcessStartInfo("https://www.exchangerate-api.com") {UseShellExecute=true});freshness.Children.Add(rate);Grid.SetColumn(freshness,1);cost.Children.Add(freshness);
        var currencyPicker=Picker("Display currency",[("USD  $","USD"),("CNY  ¥","CNY"),("EUR  €","EUR"),("GBP  £","GBP"),("JPY  ¥","JPY"),("KRW  ₩","KRW"),("CAD  C$","CAD"),("AUD  A$","AUD"),("CHF","CHF")],p=>p.Currency,value=>Save(P with {Currency=value}));currencyPicker.MinWidth=110;currencyPicker.VerticalAlignment=VerticalAlignment.Center;Grid.SetColumn(currencyPicker,2);cost.Children.Add(currencyPicker);
        currencyRefresh=Button("Refresh",refresh);currencyRefresh.Margin=new Thickness(10,0,0,0);currencyRefresh.VerticalAlignment=VerticalAlignment.Center;Grid.SetColumn(currencyRefresh,3);cost.Children.Add(currencyRefresh);
        content.Children.Add(cost);RefreshCurrencyStatus();
    }

    private void AddAccount(StackPanel panel,string id)
    {
        bool connectedProvider=id is "grok" or "antigravity";
        var provider=feed?.Provider(id)??ParityData.Provider(id);
        var section=new StackPanel {Margin=new Thickness(0,0,0,id==P.SelectedProviders.Last()?0:18)};
        AutomationProperties.SetAutomationId(section,"ProviderAccount_"+id);panel.Children.Add(section);
        var heading=new Grid();heading.ColumnDefinitions.Add(new ColumnDefinition());heading.ColumnDefinitions.Add(new ColumnDefinition {Width=GridLength.Auto});heading.ColumnDefinitions.Add(new ColumnDefinition {Width=GridLength.Auto});
        var identity=new StackPanel {Orientation=Orientation.Horizontal,VerticalAlignment=VerticalAlignment.Center};identity.Children.Add(Mark(id));
        var name=Label(provider.Name,13,.85,true);name.Margin=new Thickness(8,0,8,0);name.VerticalAlignment=VerticalAlignment.Center;identity.Children.Add(name);
        var plan=Label("",11,.65);plan.Foreground=TextBrush(.65,.06);
        var badge=new Border {Child=plan,Padding=new Thickness(6,3,6,3),CornerRadius=new CornerRadius(4),Background=ParityTheme.White(.06),VerticalAlignment=VerticalAlignment.Center};identity.Children.Add(badge);heading.Children.Add(identity);
        var usageButton=Button("Refresh "+provider.Name+" connection",()=>{accountActions.Remove(id);refreshUsage?.Invoke();RefreshProviderStatus();},0,0,true);
        usageButton.Content=SettingsIcon("refresh",14);usageButton.Width=28;usageButton.Height=28;usageButton.ToolTip=Localizer.Text("Refresh connection");AutomationProperties.SetAutomationId(usageButton,"RefreshAccount_"+id);Grid.SetColumn(usageButton,1);heading.Children.Add(usageButton);
        var options=Button(provider.Name+" account options",()=>{},0,0,true);options.Content=SettingsIcon("ellipsis",14);options.Width=20;options.Height=28;options.Margin=new Thickness(4,0,0,0);Grid.SetColumn(options,2);heading.Children.Add(options);
        void ShowOptions() {
            var menu=PopupMenu();var current=feed?.State(id);bool demo=feed?.IsDemo!=false;
            string title=demo?"Connect accounts":CliAccountActions.ActionLabel(id,CliAccountActions.FindExecutable(id)!=null,current?.Status??UsageStatus.NotConnected);
            var item=new MenuItem {Header=Localizer.Text(title)};item.Click+=(_,_)=>_=ConnectAccountAsync(id);menu.Items.Add(item);
            if(!connectedProvider&&!demo){var refreshItem=new MenuItem {Header=Localizer.Text("Refresh usage")};refreshItem.Click+=(_,_)=>refreshUsage?.Invoke();menu.Items.Add(refreshItem);}
            menu.PlacementTarget=heading;menu.Placement=PlacementMode.Bottom;menu.IsOpen=true;
        }
        options.Click+=(_,_)=>ShowOptions();identity.MouseRightButtonUp+=(_,e)=>{ShowOptions();e.Handled=true;};section.Children.Add(heading);
        var details=new StackPanel {Margin=new Thickness(28,8,0,0)};section.Children.Add(details);
        var statusRow=new StackPanel {Orientation=Orientation.Horizontal};var statusIcon=new ContentControl {Width=12,Height=12,Margin=new Thickness(0,0,4,0),VerticalAlignment=VerticalAlignment.Center};statusRow.Children.Add(statusIcon);
        var status=Label("",11,.55);statusRow.Children.Add(status);details.Children.Add(statusRow);
        var message=Label("",12,.65);message.Margin=new Thickness(0,8,0,0);details.Children.Add(message);
        var connect=Button("",()=>_=ConnectAccountAsync(id),8,3);connect.HorizontalAlignment=HorizontalAlignment.Left;connect.Margin=new Thickness(0,8,0,0);AutomationProperties.SetAutomationId(connect,"ConnectAccount_"+id);details.Children.Add(connect);
        var quota=new ContentControl {Margin=new Thickness(0,8,0,0),Visibility=Visibility.Collapsed};details.Children.Add(quota);string? quotaSignature=null;
        void Update() {
            var current=feed?.State(id);bool demo=feed?.IsDemo!=false;
            accountActions.TryGetValue(id,out var action);
            bool busy=action.Busy||CliAccountActions.IsBusy(id),loading=current?.Loading==true;
            bool needsLogin=current==null||current.Status is UsageStatus.NotConnected or UsageStatus.Expired or UsageStatus.NeedsLogin;
            bool signedIn=demo||!needsLogin&&current?.UpdatedAt!=null;
            bool installed=CliAccountActions.FindExecutable(id)!=null;
            string label=demo?"Connect accounts":busy?"Please wait…":CliAccountActions.ActionLabel(id,installed,current?.Status??UsageStatus.NotConnected);
            ((TextBlock)connect.Content).Text=Localizer.Text(label);AutomationProperties.SetName(connect,Localizer.Text(label));connect.IsEnabled=!busy;
            connect.Visibility=!demo&&(needsLogin||busy)?Visibility.Visible:Visibility.Collapsed;
            usageButton.Visibility=connectedProvider?Visibility.Visible:Visibility.Collapsed;usageButton.IsEnabled=!demo&&!busy&&!loading;usageButton.Opacity=loading?.4:1;
            options.Visibility=connectedProvider&&signedIn?Visibility.Visible:Visibility.Collapsed;options.IsEnabled=!busy;
            string? rawPlan=demo?provider.Plan:current?.Plan;
            plan.Text=id=="codex"?rawPlan?.ToLowerInvariant() switch {"pro" or "prolite"=>"Pro","plus"=>"Plus",_=>rawPlan??""}:rawPlan??"";badge.Visibility=plan.Text.Length>0?Visibility.Visible:Visibility.Collapsed;
            status.Text=Localizer.Text(loading?"Checking connection":signedIn?"Signed in":needsLogin?"Sign-in required":"Connection unavailable");statusIcon.Content=SettingsIcon(signedIn?"check":"info",11,.55);
            statusRow.Visibility=connectedProvider||needsLogin||loading?Visibility.Visible:Visibility.Collapsed;
            string? detail=action.Message??(busy?"Account setup is in progress…":demo||current?.Status==UsageStatus.Ready&&current.Windows.Any(w=>w.Used!=null)?null:current?.Message);
            if(!connectedProvider&&needsLogin&&installed&&!busy&&string.IsNullOrEmpty(action.Message))detail=null;
            if(!demo&&needsLogin&&!installed)detail="Install the official CLI, then sign in to connect your account.";
            message.Text=Localizer.Text(detail??"");message.Visibility=string.IsNullOrEmpty(detail)||loading?Visibility.Collapsed:Visibility.Visible;
            if(!connectedProvider&&current?.Status==UsageStatus.Ready&&string.IsNullOrEmpty(action.Message))details.Visibility=Visibility.Collapsed;
            else details.Visibility=demo&&!connectedProvider?Visibility.Collapsed:Visibility.Visible;
            if(connectedProvider&&!demo) {
                string signature=System.Text.Json.JsonSerializer.Serialize(new {current?.AccountKey,Windows=current?.Windows.Select(w=>new {w.Id,w.Label,w.GroupId,w.GroupLabel,w.Kind}),Selection=feed!.QuotaSelection(id)});
                if(signature!=quotaSignature){quotaSignature=signature;quota.Content=QuotaControls(id);quota.Visibility=quota.Content==null?Visibility.Collapsed:Visibility.Visible;}
            }
        }
        Update();providerBindings.Add(Update);
    }

    private static FrameworkElement SettingsIcon(string kind,double size,double opacity=.85)
    {
        string path=kind switch {
            "swap"=>"M 13 4 H 2 M 5 1 L 2 4 L 5 7 M 2 12 H 13 M 10 9 L 13 12 L 10 15",
            "refresh"=>"M 11 4 A 5.5 5.5 0 1 0 13 9 M 8 1 L 11 4 L 8 7",
            "down"=>"M 3 5 L 8 10 L 13 5",
            "right"=>"M 5 2 L 11 8 L 5 14",
            "check"=>"M 14.5 8 A 6.5 6.5 0 1 0 1.5 8 A 6.5 6.5 0 1 0 14.5 8 M 4.5 8 L 7 10.5 L 11.5 5",
            "info"=>"M 14.5 8 A 6.5 6.5 0 1 0 1.5 8 A 6.5 6.5 0 1 0 14.5 8 M 8 7 V 11 M 8 4.5 V 4.7",
            _=>"M 2 8 H 2.2 M 8 8 H 8.2 M 14 8 H 14.2"
        };
        var canvas=new Canvas {Width=16,Height=16};canvas.Children.Add(new System.Windows.Shapes.Path {Data=Geometry.Parse(path),Stroke=TextBrush(opacity),StrokeThickness=kind=="ellipsis"?2.2:1.35,StrokeStartLineCap=PenLineCap.Round,StrokeEndLineCap=PenLineCap.Round,StrokeLineJoin=PenLineJoin.Round});
        return new Viewbox {Child=canvas,Width=size,Height=size,Stretch=Stretch.Uniform};
    }
    private async System.Threading.Tasks.Task ConnectAccountAsync(string id)
    {
        if(feed?.IsDemo!=false){DataModeRequested?.Invoke(true);return;}
        if(accountActions.TryGetValue(id,out var previous)&&previous.Busy)return;
        if(!CliAccountActions.TryBegin(id))return;
        bool install=CliAccountActions.FindExecutable(id)==null;
        accountActions[id]=(true,install?"Installing the official CLI…":id=="antigravity"?"Select Google OAuth in the Antigravity window, then finish signing in in your browser.":"Finish signing in in your browser. This window will update when you return.");RefreshProviderStatus();
        try {
            if(install) {
                await CliAccountActions.InstallAsync(id);
                accountActions[id]=(false,"Installed. Sign in below to connect your account.");
            } else {
                bool success=await CliAccountActions.SignInAsync(id,feed.State(id)?.Status is not (UsageStatus.Ready or UsageStatus.Offline or UsageStatus.RateLimited or UsageStatus.Cached));
                accountActions[id]=(false,success?null:"Sign-in was not completed. Try again when you are ready.");
                if(success)await feed.RefreshAfterSignInAsync(id);
            }
        } catch(Exception error) when(error is System.ComponentModel.Win32Exception or InvalidOperationException or System.IO.IOException or UnauthorizedAccessException or System.Net.Http.HttpRequestException or System.Threading.Tasks.TaskCanceledException or TimeoutException) {
            accountActions[id]=(false,install?"Installation did not finish. Check your connection and try again.":"Sign-in could not start. Check that the CLI is installed, then try again.");
        } finally {CliAccountActions.End(id);}
        RefreshProviderStatus();
    }

    private FrameworkElement? QuotaControls(string id)
    {
        var windows=feed?.State(id)?.Windows??[];var selection=feed?.QuotaSelection(id)??new();
        if(windows.Length<=1&&selection.IsDefault)return null;
        var panel=new StackPanel();var controls=new StackPanel {Margin=new Thickness(0,8,0,0)};
        void SaveSelection(ProviderQuotaSelection next) {
            var selections=new Dictionary<string,ProviderQuotaSelection>(P.QuotaSelections) {[feed!.QuotaScope(id)]=next};
            Save(P with {QuotaSelections=selections});
        }
        var disclosure=new StackPanel {Orientation=Orientation.Horizontal};var arrow=new ContentControl {Width=10,Height=12,Margin=new Thickness(0,0,5,0),VerticalAlignment=VerticalAlignment.Center};disclosure.Children.Add(arrow);disclosure.Children.Add(Label("Usage display",12,.8));
        var toggle=Button("Usage display",()=>{},0,0,true);toggle.Content=disclosure;AutomationProperties.SetAutomationId(toggle,"QuotaDisclosure_"+id);
        void UpdateDisclosure(){bool open=expandedQuota.Contains(id);controls.Visibility=open?Visibility.Visible:Visibility.Collapsed;arrow.Content=SettingsIcon(open?"down":"right",10,.65);AutomationProperties.SetHelpText(toggle,open?"Expanded":"Collapsed");}
        toggle.Click+=(_,_)=>{if(!expandedQuota.Add(id))expandedQuota.Remove(id);UpdateDisclosure();};UpdateDisclosure();
        toggle.HorizontalAlignment=HorizontalAlignment.Left;panel.Children.Add(toggle);panel.Children.Add(controls);
        controls.Visibility=expandedQuota.Contains(id)?Visibility.Visible:Visibility.Collapsed;
        var displayed=ProviderQuotaSelection.Resolve(windows,selection);
        var groups=windows.Select(w=>w.GroupId).Distinct().OrderBy(g=>g,StringComparer.Ordinal).ToArray();
        string? group=selection.GroupId??displayed.FirstOrDefault()?.GroupId;
        var candidates=windows.Where(w=>w.GroupId==group).ToArray();
        void PickerRow(string title,(string Label,string Value)[] items,string value,Action<string> change) {
            var row=new Grid {Margin=new Thickness(0,0,0,10)};row.ColumnDefinitions.Add(new ColumnDefinition());row.ColumnDefinitions.Add(new ColumnDefinition {Width=GridLength.Auto});
            var label=Label(title,12,.65);label.VerticalAlignment=VerticalAlignment.Center;label.Margin=new Thickness(0,0,10,0);row.Children.Add(label);
            var picker=Menu(title,items,value,change);picker.Padding=new Thickness(8,2,8,2);Grid.SetColumn(picker,1);row.Children.Add(picker);controls.Children.Add(row);
        }
        if(!selection.IsDefault){var defaults=Button("Use defaults",()=>SaveSelection(new()));defaults.HorizontalAlignment=HorizontalAlignment.Right;defaults.Margin=new Thickness(0,0,0,8);controls.Children.Add(defaults);}
        if(groups.Length>1)PickerRow("Model group",groups.Select(g=>(windows.First(w=>w.GroupId==g).GroupLabel??g,g)).ToArray(),group??"",g=>SaveSelection(new(GroupId:g)));
        else if(displayed.FirstOrDefault()?.GroupLabel is string label)controls.Children.Add(Label(label,11,.65));
        if(candidates.Length>1) {
            foreach(int slot in new[]{0,1}) {
                var options=candidates.Select(w=>(w.Label,w.MetricId)).ToList();if(slot==1)options.Add(("None",""));
                PickerRow(slot==0?"First metric":"Second metric",options.ToArray(),displayed.ElementAtOrDefault(slot)?.MetricId??"",metric=>SaveSelection(selection.SelectMetric(displayed,slot,metric)));
            }
            if(displayed.Length>1)PickerRow("Peek and alerts",displayed.Select(w=>(w.Label,w.MetricId)).ToArray(),selection.PrimaryId??displayed[0].MetricId,metric=>SaveSelection(selection with {PrimaryId=metric}));
        } else controls.Children.Add(Label(string.Join(" · ",displayed.Select(w=>w.Label)),11,.65));
        if(displayed.Length==0)controls.Children.Add(Label("Selected metric is unavailable. Use defaults to choose an available metric.",11,.65));
        return panel;
    }

    public void RefreshCurrencyStatus()
    {
        if(currencyStatus==null)return;
        var updated=P.SelectedProviders.Select(id=>feed?.History(id)?.UpdatedAt).Where(t=>t.HasValue).Max();
        string? scan=updated is DateTimeOffset date?Localizer.Text("last scan %@").Replace("%@",FooterStatus.Relative(date,DateTimeOffset.Now,Localizer.IsChinese)):null;
        currencyStatus.Text=currency.Refreshing?Localizer.Text("updating exchange rate…"):feed?.HistoryLoading==true?Localizer.Text("scanning local logs…"):currency.Error??scan??Localizer.Text("swipe panel to view");
        currencyStatus.ToolTip=currencyStatus.Text;
        if(currencyRefresh!=null){bool busy=currency.Refreshing||feed?.HistoryLoading==true;currencyRefresh.IsEnabled=!busy;((TextBlock)currencyRefresh.Content).Text=Localizer.Text(busy?"Refreshing…":"Refresh");}
    }

    public void RefreshProviderStatus(){foreach(var binding in providerBindings.ToArray())binding();RefreshCurrencyStatus();}

    private FrameworkElement ProviderSlot(int slot,string? id)
    {
        var column=new StackPanel();var caption=Label(slot==0?"Left":"Right",11,.65);caption.Margin=new Thickness(0,0,0,8);column.Children.Add(caption);
        var choices=ParityData.Providers.Select(p=>(p.Name,p.Id)).ToList();if(slot==1)choices.Add(("None - use one provider",""));
        var button=Menu(slot==0?"Left provider":"Right provider",choices.ToArray(),id??"",value=>Save(P.SelectProvider(value.Length==0?null:value,slot)));
        var row=new StackPanel {Orientation=Orientation.Horizontal};if(id!=null)row.Children.Add(Mark(id));else row.Children.Add(Label("+",18,.65));
        var name=Label(id==null?"Add provider":ParityData.Provider(id).Name,13,.98);name.Margin=new Thickness(8,0,0,0);name.VerticalAlignment=VerticalAlignment.Center;row.Children.Add(name);var arrow=SettingsIcon("down",9,.7);arrow.Margin=new Thickness(4,0,0,0);arrow.VerticalAlignment=VerticalAlignment.Center;row.Children.Add(arrow);button.Content=row;button.HorizontalContentAlignment=HorizontalAlignment.Center;button.Padding=new Thickness(10);button.MinHeight=44;button.Background=ParityTheme.White(.065);button.BorderThickness=new Thickness(0);Template(button,8);column.Children.Add(button);return column;
    }
}
internal sealed class StylePreview : FrameworkElement
{
    public int Kind;public bool Cost;
    protected override void OnRender(DrawingContext dc)
    {
        double cx=ActualWidth/2,cy=17;
        var color=ParityTheme.Brush(ParityTheme.Claude);
        var pen=new Pen(color,1.5) { StartLineCap=PenLineCap.Round,EndLineCap=PenLineCap.Round };
        if(!Cost&&Kind==0) {
            dc.DrawEllipse(null,new Pen(ParityTheme.White(.1),3),new Point(cx,cy),13,13);
            var arc=new StreamGeometry();using(var c=arc.Open()){c.BeginFigure(new Point(cx,cy-13),false,false);c.ArcTo(new Point(cx+10.517,cy+7.641),new Size(13,13),0,false,SweepDirection.Clockwise,true,false);}
            dc.DrawGeometry(null,new Pen(color,3) { StartLineCap=PenLineCap.Round,EndLineCap=PenLineCap.Round },arc);
        }
        else if(!Cost&&Kind==1) {
            dc.DrawRoundedRectangle(ParityTheme.White(.1),null,new Rect(cx-14,cy-3,28,6),3,3);
            dc.DrawRoundedRectangle(color,null,new Rect(cx-14,cy-3,9.8,6),3,3);
        }
        else if(!Cost&&Kind==2) {
            for(int i=0;i<8;i++)dc.DrawRoundedRectangle(i<3?color:ParityTheme.White(.1),null,new Rect(cx-13.25+i*3.5,cy-6,2,12),.75,.75);
        }
        else if(Cost&&Kind==1) {
            dc.DrawRoundedRectangle(ParityTheme.White(.2),null,new Rect(cx-10,cy+3,8,6),4,4);
            dc.DrawRoundedRectangle(color,null,new Rect(cx+2,cy-9,8,18),4,4);
        }
        else if((!Cost&&Kind==4)||(Cost&&Kind==3)) {
            double[] ys=Cost?new[]{.92,.78,.65,.50,.38,.22,.10}:new[]{.75,.55,.70,.30,.45,.18,.40};
            double[] xs={0,.16,.34,.50,.69,.84,1};var path=new StreamGeometry();
            using(var c=path.Open()){for(int i=0;i<xs.Length;i++){var point=new Point(cx-16+32*xs[i],cy-8+16*ys[i]);if(i==0)c.BeginFigure(point,false,false);else c.LineTo(point,true,false);}}
            dc.DrawGeometry(null,pen,path);
        }
        else {
            string value=Cost?(Kind==0?"$87.0":"2.4M"):"35%";
            var text=new FormattedText(value,CultureInfo.InvariantCulture,FlowDirection.LeftToRight,new Typeface(ParityTheme.NumberFont,FontStyles.Normal,FontWeights.SemiBold,FontStretches.Normal),15,color,VisualTreeHelper.GetDpi(this).PixelsPerDip);
            dc.DrawText(text,new Point(cx-text.Width/2,cy-text.Height/2));
        }
    }
}

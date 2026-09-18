using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Media.Effects;
using System.Windows.Media.Animation;
using System.Windows.Automation.Peers;

namespace IslandPrototype;

public sealed partial class IslandVisual : FrameworkElement
{
    public static readonly DependencyProperty ContentOpacityProperty = Register("ContentOpacity",0);
    public static readonly DependencyProperty ProviderOpacityProperty=Register("ProviderOpacity",1);
    public double ProviderOpacity {get=>(double)GetValue(ProviderOpacityProperty);set=>SetValue(ProviderOpacityProperty,value);}
    public static readonly DependencyProperty PillOpacityProperty = Register("PillOpacity",0);
    public static readonly DependencyProperty PillShapeProperty=DependencyProperty.Register("PillShape",typeof(double),typeof(IslandVisual),
        new FrameworkPropertyMetadata(0.0,FrameworkPropertyMetadataOptions.AffectsRender,(d,_)=>((IslandVisual)d).ShapeChanged?.Invoke()));
    public double PillShape {get=>(double)GetValue(PillShapeProperty);set=>SetValue(PillShapeProperty,value);}
    internal event Action? ShapeChanged;
    public static readonly DependencyProperty LogoOpacityProperty = Register("LogoOpacity",1);
    public static readonly DependencyProperty PagePositionProperty = Register("PagePosition",0);
    public static readonly DependencyProperty FeedbackOffsetProperty = Register("FeedbackOffset",0);
    public double FeedbackOffset {get=>(double)GetValue(FeedbackOffsetProperty);set=>SetValue(FeedbackOffsetProperty,value);}
    public static readonly DependencyProperty CounterProgressProperty = Register("CounterProgress",1);
    public double CounterProgress {get=>(double)GetValue(CounterProgressProperty);set=>SetValue(CounterProgressProperty,value);}
    public static readonly DependencyProperty DetailProgressProperty = Register("DetailProgress",1);
    public double DetailProgress {get=>(double)GetValue(DetailProgressProperty);set=>SetValue(DetailProgressProperty,value);}
    private bool reduceMotion;
    public bool ReduceMotion {
        get=>reduceMotion;
        set {
            if(reduceMotion==value)return;reduceMotion=value;footerStatus.SetMotion(!reduceMotion&&!lowPower);
            if(!value)return;
            CompleteCounter();
            Settle(PagePositionProperty,Page);Settle(SwapOpacityProperty,1);Settle(FeedbackOffsetProperty,0);
            Settle(DetailProgressProperty,SelectedDay.HasValue?1:0);
            Settle(ResetPopoverProgressProperty,resetPresented?1:0);Settle(ResetBadgeHighlightProperty,resetHighlighted?1:0);
        }
    }
    private void Settle(DependencyProperty property,double value){BeginAnimation(property,null);SetValue(property,value);}
    private bool lowPower,counterRunning;
    private long counterStarted;
    private int counterGeneration;
    public bool LowPower {
        get=>lowPower;
        set {if(lowPower==value)return;lowPower=value;footerStatus.SetMotion(!reduceMotion&&!lowPower);if(counterRunning)ScheduleCounter();}
    }
    private DateTime? departingDay;
    public static readonly DependencyProperty SwapOpacityProperty = Register("SwapOpacity",1);
    private static DependencyProperty Register(string name,double initial) => DependencyProperty.Register(name,typeof(double),typeof(IslandVisual),new FrameworkPropertyMetadata(initial,FrameworkPropertyMetadataOptions.AffectsRender));
    public double ContentOpacity { get => (double)GetValue(ContentOpacityProperty); set => SetValue(ContentOpacityProperty,value); }
    public double PillOpacity { get => (double)GetValue(PillOpacityProperty); set => SetValue(PillOpacityProperty,value); }
    public double LogoOpacity { get => (double)GetValue(LogoOpacityProperty); set => SetValue(LogoOpacityProperty,value); }
    public double PagePosition { get => (double)GetValue(PagePositionProperty); set => SetValue(PagePositionProperty,value); }
    public double SwapOpacity { get => (double)GetValue(SwapOpacityProperty); set => SetValue(SwapOpacityProperty,value); }
    public CurrencyStore? Currency {get;set;}
    private string CurrencySymbol=>Currency?.Symbol??"$";
    private string Money(double value,bool symbol=true)=>Currency?.Format(value,symbol)??((symbol?"$":"")+HeroDollars(value));
    public IslandPreferences Preferences { get; set; } = new();
    internal UsageFeed? Feed {get;set;}
    private bool IsDemo=>Feed?.IsDemo??true;
    private bool HasHistory=>IsDemo||Feed?.HasHistory==true;
    private DemoDay[]? referenceDays;
    private DemoDay[] HistoryDays=>Feed?.Days??(referenceDays??=ParityData.Days.ToArray());
    public IReadOnlyDictionary<string,AlertSeverity> AlertSeverities {get;set;}=new Dictionary<string,AlertSeverity>();
    private DemoProvider[] Providers => Preferences.SelectedProviders.Select(id=>Feed?.Provider(id)??ParityData.Provider(id)).ToArray();
    public bool Expanded { get; set; }
    public int Page { get; set; }
    public int ChartStyle { get; set; } = 4;
    public int CostStyle { get; set; }
    public int PreviousChartStyle { get; set; } = 4;
    public int PreviousCostStyle { get; set; }
    public bool Remaining { get; set; }
    public bool HasCycled { get; set; }
    public DateTime? SelectedDay { get; private set; }
    public string? SelectedProvider { get; private set; }
    public event Action<int>? PageRequested;
    public event Action? ExpansionRequested;
    internal void ExpandPill(){if(!Expanded)ExpansionRequested?.Invoke();}
    public event Action? SettingsRequested, ProviderSettingsRequested, StyleRequested, DetailChanged, RefreshRequested, ShareRequested;
    private readonly VisualCollection layers;
    private readonly ContainerVisual clippedContent=new();
    private readonly DrawingVisual oldBody=new(), newBody=new(), detailBody=new();
    private readonly DrawingVisual calendarGrid=new() {CacheMode=new BitmapCache()};
    private readonly DrawingVisual calendarHover=new();
    private readonly DollarGlowLayer oldGlow=new(),newGlow=new(),oldUsageGlow=new(),newUsageGlow=new();
    private readonly FooterStatusLayer footerStatus=new();
    internal FooterStatusLayer StatusControl=>footerStatus;
    private bool ambientVisible=true;
    internal bool AmbientVisible {get=>ambientVisible;set{ambientVisible=value;footerStatus.SetAmbientVisible(value&&Expanded);}}
    private DollarGlowLayer? drawingGlow;
    protected override int VisualChildrenCount=>layers.Count;
    protected override Visual GetVisualChild(int index)=>layers[index];
    private readonly Dictionary<string,BitmapSource> logos = new();
    private readonly List<(Rect Bounds,string Help,Action Action)> targets = new();
    private double pixelsPerDip=1;
    private Rect hoveredTarget=Rect.Empty;
    internal int OverviewBuildCount {get;private set;}
    internal int RenderCount {get;private set;}
    internal int UsageBuildCount {get;private set;}
    internal int CostBuildCount {get;private set;}
    private sealed record OverviewKey(DemoDay[] Days,DateTime Today,DateTime? SelectedDay,string? Provider,string Culture,double Dpi);
    private OverviewKey? overviewKey;
    private DrawingGroup? overviewContent;
    private readonly List<(Rect Bounds,string Help,Action Action)> overviewTargets=new();
    private readonly TranslateTransform calendarPosition=new();
    private readonly Dictionary<Rect,(DateTime Date,double Border)> calendarCells=new();
    private sealed record BodyKey(IslandPreferences Preferences,UsageFeed? Feed,long Revision,IslandPreferences? Quotas,
        string Currency,double Rate,string Culture,double Dpi,long Minute,int ExpiredWindows,int Chart,int Cost,bool Remaining,double Counter,bool DollarModels);
    private sealed class PageContent {
        internal BodyKey? Key;
        internal DrawingGroup? Drawing;
        internal readonly List<(Rect Bounds,string Help,Action Action)> Targets=new();
    }
    private readonly PageContent[,] pageContents=new PageContent[,]{{new(),new()},{new(),new()}};
    private List<(Rect Bounds,string Help,Action Action)>? capturingTargets;

    internal (Rect Bounds,string Help,Action Action)[] AccessibleTargets {
        get {
            var available=Expanded&&ContentOpacity>.9&&!footerStatus.Bounds.IsEmpty
                ?targets.Append((footerStatus.Bounds,FooterStatusLayer.TargetId,(Action)RefreshFooter)):targets;
            var offset=new Vector((ActualWidth-800)/2,-8*(1-ContentOpacity));
            return available.Select(target=>{var bounds=target.Item1;bounds.Offset(offset);return (bounds,target.Item2,target.Item3);}).ToArray();
        }
    }
    internal bool TargetEnabled(string name)=>Expanded&&(name!=FooterStatusLayer.TargetId||!footerStatus.Loading);
    internal string TargetName(string name)=>name==FooterStatusLayer.TargetId?footerStatus.Spoken:Localizer.Text(name);
    internal string TargetHelp(string name)=>name==FooterStatusLayer.TargetId?footerStatus.Help:name;
    private void RefreshFooter(){if(!footerStatus.Loading)RefreshRequested?.Invoke();}
    internal string? FocusedTarget {get;private set;}
    internal string AccessibleDescription {
        get {
            if(!IsDemo) {
                string liveValues=Page==0||!Expanded?string.Join(". ",Providers.Select(p=>p.Name+": "+Feed?.State(p.Id)?.Message+". "+string.Join(", ",p.Limits.Select(m=>m.Label+" "+(m.Used is double value?$"{(Remaining?100-value:value):0}% {(Remaining?"remaining":"used")}":"no reading")))))
                    :Page==1?string.Join(". ",Providers.Select(p=>p.Name+": "+(p.Costs.Length==0?"Usage history unavailable.":string.Join(", ",p.Costs.Select(c=>c.Label+" "+(CostStyle==2?(Preferences.TokenMode=="billable"?c.BillableTokens:c.Tokens).ToString("N0")+" tokens":Money(c.Dollars)+(c.UnpricedTokens>0?" plus unpriced usage":""))))+". "+Feed?.History(p.Id)?.Notice)))
                    :HasHistory?OverviewAccessibleDescription():"Usage history unavailable.";
                return "CodexIsland "+(Expanded?ParityData.PageNames[Page]:"usage")+". "+liveValues+(Expanded?". "+footerStatus.Spoken:"");
            }
            if(!Expanded)return "CodexIsland. "+string.Join(". ",Providers.Select(p=>p.Name+": "+(UsageFeed.Primary(p)?.Used is double value?$"{Math.Round(Remaining?100-value:value,MidpointRounding.AwayFromZero):0}% {(Remaining?"remaining":"used")}":"no reading")+(AlertSeverities.TryGetValue(p.Id,out var severity)?", "+severity.ToString().ToLowerInvariant()+" usage alert":"")))+". Demo data.";
            string values=Page==0?string.Join(". ",Providers.Select(p=>p.Name+": "+string.Join(", ",p.Limits.Select(m=>m.Label+" "+(m.Used is double value?$"{(Remaining?100-value:value):0}% {(Remaining?"remaining":"used")}, resets in {m.Reset}":"no reading")))))
                :Page==1?string.Join(". ",Providers.Select(p=>p.Name+": "+string.Join(", ",p.Costs.Select(c=>c.Label+" "+(CostStyle==2?(Preferences.TokenMode=="billable"?c.BillableTokens:c.Tokens).ToString("N0")+" tokens":Money(c.Dollars))))))
                :OverviewAccessibleDescription();
            return "CodexIsland "+ParityData.PageNames[Page]+". "+values+". Demo data.";
        }
    }
    private string OverviewAccessibleDescription()
    {
        var days=HistoryDays.Where(d=>SelectedDay is DateTime date?d.Date==date:d.Date.Year==DateTime.Today.Year);
        var providers=ParityData.Providers.Where(p=>SelectedProvider==null||p.Id==SelectedProvider).Select(p=>(p.Name,Tokens:days.Sum(d=>d.Tokens.GetValueOrDefault(p.Id)))).ToArray();
        return (SelectedDay?.ToString("MMMM d, yyyy")??DateTime.Today.Year.ToString())+$": {providers.Sum(p=>p.Tokens):N0} tokens. "+string.Join(", ",providers.Select(p=>$"{p.Name} {p.Tokens:N0} tokens"));
    }
    protected override AutomationPeer OnCreateAutomationPeer()=>new IslandVisualPeer(this);
    internal void FocusTarget(string name){string? previous=FocusedTarget;FocusedTarget=name;Focus();UpdateResetFocus();NotifyFocusChanged(previous);InvalidateVisual();}
    private void NotifyFocusChanged(string? previous)=>(UIElementAutomationPeer.FromElement(this) as IslandVisualPeer)?.FocusChanged(previous,FocusedTarget);
    internal void FocusNext(bool backwards)
    {
        var available=AccessibleTargets.Where(t=>!t.Help.Contains(": ")&&TargetEnabled(t.Help)).ToArray();
        if(available.Length==0)return;
        int index=Array.FindIndex(available,t=>t.Help==FocusedTarget);
        index=(index+(backwards?-1:1)+available.Length)%available.Length;
        FocusTarget(available[index].Help);
    }
    internal bool ActivateFocused()
    {
        var target=AccessibleTargets.FirstOrDefault(t=>t.Help==FocusedTarget);if(target.Action==null||!TargetEnabled(target.Help))return false;target.Action();return true;
    }

    public IslandVisual()
    {
        layers=new VisualCollection(this) {clippedContent,resetPopover};
        clippedContent.Children.Add(oldBody);clippedContent.Children.Add(newBody);clippedContent.Children.Add(footerStatus);
        InitializeResetPopover();
        newBody.Children.Add(detailBody);
        newBody.Children.Add(calendarGrid);
        calendarGrid.Transform=calendarPosition;
        newBody.Children.Add(calendarHover);
        calendarHover.Transform=calendarPosition;
        oldBody.Children.Add(oldGlow);newBody.Children.Add(newGlow);
        oldBody.Children.Add(oldUsageGlow);newBody.Children.Add(newUsageGlow);
        SnapsToDevicePixels=false;
        Focusable=true;
        FocusVisualStyle=null; // Individual actions draw their own focus rings inside the island silhouette.
        GotKeyboardFocus+=(_,_)=>InvalidateVisual();LostKeyboardFocus+=(_,_)=>InvalidateVisual();
        foreach(string id in new[]{"claude","codex","antigravity","grok"})
        {
            var bitmap = new BitmapImage(new Uri("pack://application:,,,/Assets/"+(id=="codex"?"openai":id)+".png"));
            bitmap.Freeze();logos[id]=bitmap;
        }
        Unloaded+=(_,_)=>footerStatus.Hide();
        IsVisibleChanged+=(_,_)=>{if(!IsVisible)footerStatus.Hide();else InvalidateVisual();};
        MouseLeave+=(_,_)=>{ClearPointerFocus();hoveredTarget=Rect.Empty;DrawCalendarHover();footerStatus.SetPointer(null);};
        PreviewMouseLeftButtonDown+=(_,args)=>{ClearPointerFocus();footerStatus.SetPointer(ContentPoint(args.GetPosition(this)),false,true);};
        PreviewMouseLeftButtonUp+=(_,args)=>footerStatus.SetPointer(ContentPoint(args.GetPosition(this)),IsKeyboardFocusWithin&&FocusedTarget==FooterStatusLayer.TargetId);
        MouseMove += (_,args) =>
        {
            ClearPointerFocus();
            var point=args.GetPosition(this);
            var hit=AccessibleTargets.LastOrDefault(t=>t.Bounds.Contains(point));
            ToolTip=!Expanded?PillHelpAt(point):hit.Action!=null?TargetHelp(hit.Help):null;
            if(hoveredTarget!=hit.Bounds){hoveredTarget=hit.Bounds;DrawCalendarHover();}
            Cursor=hit.Action != null&&TargetEnabled(hit.Help) || !Expanded ? Cursors.Hand : Cursors.Arrow;
            footerStatus.SetPointer(ContentPoint(point),IsKeyboardFocusWithin&&FocusedTarget==FooterStatusLayer.TargetId,Mouse.LeftButton==MouseButtonState.Pressed);
            UpdateResetPointer(point);
        };
    }

    protected override void OnDpiChanged(DpiScale oldDpi,DpiScale newDpi)
    {
        base.OnDpiChanged(oldDpi,newDpi);
        InvalidateVisual();
    }

    public bool ActivateAt(Point point)
    {
        ClearPointerFocus();
        var target=AccessibleTargets.LastOrDefault(t=>t.Bounds.Contains(point));
        if(target.Action == null||!TargetEnabled(target.Help))return false;
        target.Action();return true;
    }
    private void ClearPointerFocus()
    {
        if(FocusedTarget==null)return;
        string previous=FocusedTarget;FocusedTarget=null;UpdateResetFocus();NotifyFocusChanged(previous);footerStatus.SetPointer(IsMouseOver?ContentPoint(Mouse.GetPosition(this)):null);
        InvalidateVisual();
    }
    private Point ContentPoint(Point point){point.Offset(-(ActualWidth-800)/2,8*(1-ContentOpacity));return point;}
    public void ClearSelection() { SelectedDay=null;departingDay=null;BeginAnimation(DetailProgressProperty,null);DetailProgress=0;InvalidateVisual(); }
    private void SelectDay(DateTime day)
    {
        bool wasOpen=SelectedDay.HasValue;
        departingDay=SelectedDay;
        SelectedDay=SelectedDay==day?null:day;
        if(wasOpen!=SelectedDay.HasValue) {
            double target=SelectedDay.HasValue?1:0;
            if(ReduceMotion)Settle(DetailProgressProperty,target);
            else {
                AnimationTimeline animation=target==1
                    ?new SpringAnimation {From=DetailProgress,To=1,Response=.36,Damping=.94,Duration=TimeSpan.FromSeconds(.65)}
                    :new DoubleAnimation(DetailProgress,0,TimeSpan.FromSeconds(.20)) {EasingFunction=new BezierEase()};
                if(LowPower)Timeline.SetDesiredFrameRate(animation,30);
                animation.Completed+=(_,_)=>{if((SelectedDay.HasValue?1:0)==target)Settle(DetailProgressProperty,target);};
                BeginAnimation(DetailProgressProperty,animation);
            }
        }
        DetailChanged?.Invoke();InvalidateVisual();
    }
    public double PanelHeight => Page==2 ? (SelectedDay.HasValue?335:277) : 226;

    protected override void OnRender(DrawingContext dc)
    {
        long started=FrameDiagnostics.Begin();
        base.OnRender(dc);
        RenderCount++;
        pixelsPerDip=VisualTreeHelper.GetDpi(this).PixelsPerDip;
        if(calendarGrid.CacheMode is BitmapCache calendarCache)calendarCache.RenderAtScale=pixelsPerDip;
        calendarGrid.Opacity=ContentOpacity>0&&Math.Abs(2-PagePosition)<1&&HasHistory?1:0;
        calendarHover.Opacity=calendarGrid.Opacity;
        double width=ActualWidth,height=ActualHeight;
        if(width<1||height<1)return;
        targets.Clear();resetBadge=Rect.Empty;
        var silhouette=ParityTheme.Silhouette(width,height,PillShape);
        clippedContent.Clip=PillShape>0||ProviderOpacity<1?silhouette:null;
        dc.DrawGeometry(Brushes.Black,Expanded?new Pen(ParityTheme.White(.12),.5):null,silhouette);
        dc.PushClip(silhouette);
        if(PillOpacity>0)
        {
            dc.PushOpacity(PillOpacity);
            DrawPill(dc,width);
            dc.Pop();
        }
        if(ContentOpacity>0)
        {
            dc.PushOpacity(ContentOpacity);
            dc.PushTransform(new TranslateTransform((width-800)/2,-8*(1-ContentOpacity)));
            Header(dc);
            double bodyHeight=Math.Max(0,height-82);
            RenderBody(oldBody,true,width,bodyHeight);
            RenderBody(newBody,false,width,bodyHeight);
            Footer(dc,height-44);
            dc.Pop();dc.Pop();
        }
        if(PillOpacity>0||ContentOpacity>0||PillShape<1)DrawProviderIcons(dc,width);
        if(IsKeyboardFocusWithin && FocusedTarget!=null) {
            var focused=AccessibleTargets.FirstOrDefault(t=>t.Help==FocusedTarget);
            if(focused.Action!=null)dc.DrawRoundedRectangle(null,new Pen(ParityTheme.White(.65),1),focused.Bounds,4,4);
        }
        if(ContentOpacity<=0) {using(oldBody.RenderOpen()){} using(newBody.RenderOpen()){} using(detailBody.RenderOpen()){} oldGlow.Opacity=0;newGlow.Opacity=0;oldUsageGlow.Opacity=0;newUsageGlow.Opacity=0;footerStatus.Hide(); }
        dc.Pop();
        RenderResetPopover(width);
        FrameDiagnostics.End(started,"island",Page,CounterProgress);
    }

    public void StartCounter(bool reducedMotion)
    {
        counterGeneration++;counterRunning=false;
        CounterProgress=reducedMotion?1:0;
        BeginAnimation(CounterProgressProperty,null);
        if(reducedMotion)return;
        counterStarted=Stopwatch.GetTimestamp();counterRunning=true;
        ScheduleCounter();
    }

    private void ScheduleCounter()
    {
        int generation=++counterGeneration;
        double elapsed=Math.Clamp(Stopwatch.GetElapsedTime(counterStarted).TotalSeconds,0,.65);
        if(elapsed>=.65){CompleteCounter();return;}
        double progress=Math.Max(CounterProgress,1-Math.Pow(1-elapsed/.65,3));
        var animation=new DoubleAnimation(progress,1,TimeSpan.FromSeconds(.65-elapsed)) {EasingFunction=new CubicEase {EasingMode=EasingMode.EaseOut}};
        if(LowPower)Timeline.SetDesiredFrameRate(animation,30);
        animation.Completed+=(_,_)=>{if(counterRunning&&generation==counterGeneration)CompleteCounter();};
        BeginAnimation(CounterProgressProperty,animation);
    }

    private void CompleteCounter()
    {
        counterRunning=false;CounterProgress=1;
        BeginAnimation(CounterProgressProperty,null);
    }

    private void RenderBody(DrawingVisual layer,bool old,double width,double bodyHeight)
    {
        using var draw=layer.RenderOpen();
        var glow=old?oldGlow:newGlow;glow.Opacity=0;
        var usageGlow=old?oldUsageGlow:newUsageGlow;usageGlow.Opacity=0;
        layer.Transform=new TranslateTransform((width-800)/2,38-8*(1-ContentOpacity));
        layer.Clip=new RectangleGeometry(new Rect(0,0,800,bodyHeight));
        layer.Opacity=ContentOpacity*(old?1-SwapOpacity:1);
        double blur=Page==2?0:3*(old?SwapOpacity:1-SwapOpacity);
        layer.Effect=blur>0?new BlurEffect {Radius=blur,RenderingBias=RenderingBias.Performance}:null;
        if(old && SwapOpacity>=1)return;
        draw.PushClip(new RectangleGeometry(new Rect(0,0,800,bodyHeight)));
        int chart=ChartStyle,cost=CostStyle;
        if(old){ChartStyle=PreviousChartStyle;CostStyle=PreviousCostStyle;}
        for(int page=0;page<3;page++) {
            if(Math.Abs(page-PagePosition)>=1 || (old&&page==2))continue;
            var pageGlow=page==0?usageGlow:glow;
            draw.PushTransform(new TranslateTransform((page-PagePosition)*800+FeedbackOffset,0));
            draw.PushOpacity(old||page==2?1:SwapOpacity);
            double scale=page==2?1:old?1-.04*SwapOpacity:.96+.04*SwapOpacity;
            draw.PushTransform(new ScaleTransform(scale,scale,400,bodyHeight/2));
            if(page<=1){
                pageGlow.PageTransform=new TransformGroup {Children=new TransformCollection {new ScaleTransform(scale,scale,400,bodyHeight/2),new TranslateTransform((page-PagePosition)*800+FeedbackOffset,0)}};
            }
            long pageStarted=FrameDiagnostics.Begin();
            if(page<2)RetainedPage(draw,page,old,pageGlow);else Overview(draw);
            if(page==1||page==0&&ChartStyle==3)pageGlow.Opacity=old?1:SwapOpacity;
            FrameDiagnostics.End(pageStarted,"page-body",page,PagePosition);
            draw.Pop();draw.Pop();draw.Pop();
        }
        ChartStyle=chart;CostStyle=cost;draw.Pop();
        drawingGlow=null;
        if(!old)RenderDetail(width,bodyHeight);
    }

    private void RetainedPage(DrawingContext draw,int page,bool old,DollarGlowLayer glow)
    {
        var now=DateTimeOffset.UtcNow;
        int expired=Feed==null?0:Preferences.SelectedProviders.Sum(id=>Feed.State(id)?.Windows.Count(w=>w.ResetAt<=now||w.RetainUntil<=now)??0);
        var key=new BodyKey(Preferences with{Page=0},Feed,Feed?.Revision??0,Feed==null?null:Feed.Preferences with{Page=0},
            Currency?.DisplayCurrency??"USD",Currency?.Rate??1,Localizer.Culture.Name,pixelsPerDip,now.ToUnixTimeSeconds()/60,expired,
            ChartStyle,CostStyle,Remaining,page==1&&CostStyle==0?CounterProgress:1,Preferences.RightProvider==null&&Page==1&&CostStyle!=2);
        var content=pageContents[old?1:0,page];
        if(content.Key!=key){
            var drawing=new DrawingGroup();content.Targets.Clear();capturingTargets=content.Targets;
            bool usesGlow=page==1||ChartStyle==3;
            if(usesGlow){glow.Begin();drawingGlow=glow;}
            try{using var context=drawing.Open();if(page==0)Usage(context);else Cost(context);}
            finally{capturingTargets=null;drawingGlow=null;if(usesGlow)glow.End();}
            if(drawing.CanFreeze)drawing.Freeze();content.Drawing=drawing;content.Key=key;
        }
        draw.DrawDrawing(content.Drawing);
        if(!old&&Page==page&&Math.Abs(PagePosition-page)<.005&&Expanded&&ContentOpacity>.9)targets.AddRange(content.Targets);
    }

    private void Header(DrawingContext dc)
    {
        var providers=Providers;
        for(int p=0;p<providers.Length;p++) {
            var provider=providers[p];bool right=p==1;
            double start=providers.Length==1?-26:right?22:-22;
            var offset=new Vector((start-(right?366:-366))*PillShape,7*PillShape+8*(1-ContentOpacity)-8*(1-ProviderOpacity));
            dc.PushTransform(new TranslateTransform(offset.X,offset.Y));
            double title=Measure(provider.Name,13,true),chipWidth=provider.Plan.Length==0?0:Measure(provider.Plan.ToUpperInvariant(),9,true,true)+10+(provider.Plan.Length-1)*.8;
            double nameX=right?748-chipWidth-(chipWidth>0?8:0):52;
            BaselineText(dc,provider.Name,nameX,24,13,ParityTheme.White(),true,false,right);
            if(chipWidth>0)Chip(dc,provider.Plan.ToUpperInvariant(),right?748-chipWidth:52+title+8,11.5,.6);
            if(provider.Id=="codex")ResetBadge(dc,right,nameX,title,chipWidth,offset);
            dc.Pop();
        }
    }

    private void Usage(DrawingContext dc)
    {
        UsageBuildCount++;
        Separator(dc);
        var providers=Providers;
        if(providers.Length==1 && providers[0].Id is "claude" or "codex")ModelBreakdown(dc,providers[0]);
        for(int p=0;p<providers.Length;p++)
        {
            var provider=providers[p];
            double start=36+p*376;
            var live=Feed?.State(provider.Id);
            if(!IsDemo&&provider.Id is "grok" or "antigravity"&&(!provider.Limits.Any(w=>w.Used!=null)||live?.Status is UsageStatus.NotConnected or UsageStatus.Expired or UsageStatus.NeedsLogin)) {
                ProviderEmptyState(dc,provider,live,start);continue;
            }
            if(provider.Limits.Length==0) {
                Text(dc,live?.Message??"Usage limits are not available yet.",start+175.5,55,11,ParityTheme.White(.55),false,false,false,true);
                if(!IsDemo) {
                    Text(dc,"Provider settings",start+175.5,80,11,ParityTheme.Brush(provider.Color,.8),true,false,false,true);
                    AddTarget(new Rect(start+110,109,131,28),provider.Name+" provider settings",()=>ProviderSettingsRequested?.Invoke());
                }
                continue;
            }
            int count=provider.Limits.Length;
            double available=count==1?(ChartStyle==3?180:240):351;
            start+=(351-available)/2;
            double tile=(available-(count-1)*18)/count;
            double contentTotal=provider.Limits.Sum(m=>70+Measure($"{(Remaining?100-m.Used:m.Used):0}",18,true,true)+8);
            double ringSpacing=(available-contentTotal)/(count+1),ringX=start+ringSpacing;
            for(int m=0;m<count;m++)
            {
                var metric=provider.Limits[m];double x=start+m*(tile+18);
                if(metric.Used==null) {
                    Text(dc,metric.Label,x,45,11,ParityTheme.White(.55));Text(dc,"--",x,65,18,ParityTheme.White(.4),true,true);continue;
                }
                double value=Remaining?100-metric.Used.Value:metric.Used.Value;
                if(ChartStyle==0) {
                    Ring(dc,metric,value,provider.Color,ringX-3,33.5);
                    ringX+=70+Measure($"{value:0}",18,true,true)+8+ringSpacing;
                }
                else Chart(dc,metric,value,provider.Color,x,24,tile);
            }
            if(live!=null&&live.Status!=UsageStatus.Ready)Text(dc,live.Message,36+p*376+175.5,128,10,ParityTheme.White(.55),false,false,false,true);
        }
    }

    private void ProviderEmptyState(DrawingContext dc,DemoProvider provider,LiveProviderState? state,double start)
    {
        bool free=state?.Message=="No active subscription";
        bool signIn=state?.Status is UsageStatus.NotConnected or UsageStatus.Expired or UsageStatus.NeedsLogin;
        double center=start+175.5;
        var pen=new Pen(ParityTheme.Brush(provider.Color,.85),1.35) {StartLineCap=PenLineCap.Round,EndLineCap=PenLineCap.Round};
        if(free) {
            dc.DrawRoundedRectangle(null,pen,new Rect(center-10,25,20,14),2,2);
            dc.DrawLine(pen,new Point(center-10,29),new Point(center+10,29));
            dc.DrawLine(pen,new Point(center-6,35),new Point(center-2,35));
        } else {
            dc.DrawLine(pen,new Point(center-10,40),new Point(center+10,40));
            for(int i=0;i<3;i++)dc.DrawRoundedRectangle(null,pen,new Rect(center-8+i*6,33-i*4,3,5+i*4),.7,.7);
        }
        Text(dc,free?"No active subscription":signIn?"Connect your account":"Usage unavailable",center,47,12,ParityTheme.White(.85),true,false,false,true);
        string message=free?"Connect a subscribed account or choose another provider.":signIn?"Sign in to see your usage limits.":"This provider hasn't reported usage limits.";
        var subtitle=Format(Localizer.Text(message),11,ParityTheme.White(.65),false,false);subtitle.MaxTextWidth=320;subtitle.TextAlignment=TextAlignment.Center;
        dc.DrawText(subtitle,new Point(center-160,67));
        string title=Localizer.Text("Open provider settings");double width=Measure(title,11)+16,y=72+subtitle.Height;
        dc.DrawRoundedRectangle(ParityTheme.White(.06),null,new Rect(center-width/2,y,width,23),5,5);
        Text(dc,title,center,y+4,11,ParityTheme.White(.8),false,false,false,true);
        AddTarget(new Rect(center-width/2,y+38,width,23),provider.Name+" provider settings",()=>ProviderSettingsRequested?.Invoke());
    }

    private void ModelBreakdown(DrawingContext dc,DemoProvider provider)
    {
        var history=Feed?.History(provider.Id);
        if(!IsDemo&&history?.HasEvidence!=true){Text(dc,"Usage history unavailable.",587.5,62,11,ParityTheme.White(.55),false,false,false,true);return;}
        BaselineText(dc,"BY MODEL",412,34,10,ParityTheme.White(.55),true,tracking:.6);
        dc.DrawRoundedRectangle(ParityTheme.Brush(provider.Color,.85),null,new Rect(683,28.5,8,4),2,2);
        BaselineText(dc,"5h",695,34,10,ParityTheme.White(.5),false,true);
        dc.DrawRoundedRectangle(ParityTheme.Brush(provider.Color,.255),null,new Rect(719,28.5,8,4),2,2);
        BaselineText(dc,"week",731,34,10,ParityTheme.White(.5),false,true);
        if(IsDemo||history!.Models[1].Length==0){BaselineText(dc,"no "+provider.Name+" activity in last 5h or this week",412,85,10,ParityTheme.White(.4),false,true);return;}
        bool dollars=Page==1&&CostStyle!=2;
        var rows=(dollars?history.Models[1].OrderByDescending(m=>m.Dollars):history.Models[1].AsEnumerable()).Take(4).ToArray();
        double[] weights=[.85,.55,.40,.30];
        for(int i=0;i<rows.Length;i++) {
            var row=rows[i];var recent=history.Models[0].FirstOrDefault(m=>m.Model==row.Model);
            double week=dollars?row.Dollars:row.Tokens,shortValue=dollars?recent?.Dollars??0:recent?.Tokens??0,rowCenter=50+i*19;
            BaselineText(dc,row.Name,412,IslandTypography.RowBaseline(rowCenter,11),11,ParityTheme.White(.78),max:84);
            var track=new Rect(504,rowCenter-2.5,179,5);dc.DrawRoundedRectangle(ParityTheme.White(.045),null,track,2.5,2.5);
            if(week>0) {
                dc.DrawRoundedRectangle(ParityTheme.Brush(provider.Color,weights[i]*.30),null,track,2.5,2.5);
                double fraction=Math.Clamp(shortValue/week,0,1);
                dc.DrawRoundedRectangle(ParityTheme.Brush(provider.Color,weights[i]),null,new Rect(track.X,track.Y,track.Width*fraction,track.Height),2.5,2.5);
            }
            string value=dollars?Money(row.Dollars):row.Tokens>=1_000_000?(row.Tokens/1_000_000.0).ToString("F1",CultureInfo.InvariantCulture)+"M":row.Tokens>=1000?(row.Tokens/1000)+"K":row.Tokens.ToString(CultureInfo.InvariantCulture);
            BaselineText(dc,value,747,IslandTypography.RowBaseline(rowCenter,10),10,ParityTheme.White(week>0?.55:.32),false,true,true);
        }
    }

    private void Ring(DrawingContext dc,UsageMetric metric,double value,Color tint,double x,double y)
    {
        var center=new Point(x+28,y+28);
        dc.DrawEllipse(null,new Pen(ParityTheme.White(.07),3),center,28,28);
        Arc(dc,center,28,value/100,tint,3);
        BaselineText(dc,metric.Label,x+70,y+19.5,11,ParityTheme.White(.55));
        double w=BaselineText(dc,$"{value:0}",x+70,y+43.5,18,Urgency(value),true,true);
        BaselineText(dc,"%",x+71+w,y+43.5,11,ParityTheme.White(.5));
        BaselineText(dc,ResetCaption(metric),x,y+74,10,ParityTheme.White(.4),false,true);
    }
    private static string ResetCaption(UsageMetric metric,bool compact=false)=>metric.Reset=="--"?"":compact?"↻ "+metric.Reset:Localizer.IsChinese?metric.Reset+" 后重置":"resets in "+metric.Reset;

    private void Chart(DrawingContext dc,UsageMetric metric,double value,Color tint,double x,double y,double width)
    {
        if(ChartStyle==3)
        {
            BaselineText(dc,metric.Label,x,y+21.5,11,ParityTheme.White(.55));
            BaselineText(dc,ResetCaption(metric,true),x+width,y+21.5,10,ParityTheme.White(.4),false,true,true);
            double number=BaselineText(dc,$"{value:0}",x,y+67.5,38,Urgency(value),true,true);
            BaselineText(dc,"%",x+number+2,y+67.5,15,ParityTheme.White(.4));
            dc.DrawRoundedRectangle(ParityTheme.White(.05),null,new Rect(x,y+81.5,width,3),1.5,1.5);
            drawingGlow?.DrawGeometry(new RectangleGeometry(new Rect(x,y+81.5,width*value/100,3),1.5,1.5),tint,.7,8);
            return;
        }
        double chartHeight=ChartStyle==1?58:ChartStyle==2?66:96;
        y+=(96-chartHeight)/2;
        BaselineText(dc,metric.Label,x,y+17,11,ParityTheme.White(.55));
        double suffix=Measure("%",11,false,false);
        BaselineText(dc,"%",x+width,y+17,11,ParityTheme.White(.5),false,false,true);
        BaselineText(dc,$"{value:0}",x+width-suffix-1,y+17,18,Urgency(value),true,true,true);
        if(ChartStyle==1)
        {
            double top=y+29;
            dc.DrawRoundedRectangle(ParityTheme.White(.06),null,new Rect(x,top+2,width,4),2,2);
            dc.DrawRoundedRectangle(ParityTheme.Brush(tint),null,new Rect(x,top+2,width*value/100,4),2,2);
            for(int i=1;i<=3;i++)dc.DrawRectangle(ParityTheme.White(.12),null,new Rect(x+width*i/4,top,1,8));
            BaselineText(dc,ResetCaption(metric),x,y+55,10,ParityTheme.White(.4),false,true);
        }
        else if(ChartStyle==2)
        {
            double step=(width-58)/30;
            for(int i=0;i<30;i++)dc.DrawRoundedRectangle(i<Math.Floor(value*.3)?ParityTheme.Brush(tint):ParityTheme.White(.1),null,new Rect(x+i*(step+2),y+29,step,16),1.5,1.5);
            BaselineText(dc,ResetCaption(metric),x,y+63,10,ParityTheme.White(.4),false,true);
        }
        else
        {
            if(IsDemo)Spark(dc,new Rect(x,y+27,width,50),value,tint,metric.Seed);
            else {
                var observations=metric.Observations??[];
                RecordedSpark(dc,new Rect(x,y+27,width,50),value,tint,observations.Select(v=>Remaining?100-v:v).ToArray());
                if(observations.Length<2)Text(dc,metric.Observations==null?"History unavailable":"Collecting history",x,y+61,9,ParityTheme.White(.35));
            }
            BaselineText(dc,ResetCaption(metric),x,y+93,10,ParityTheme.White(.4),false,true);
        }
    }

    private void Cost(DrawingContext dc)
    {
        CostBuildCount++;
        Separator(dc);
        var providers=Providers;
        if(providers.Length==1)ModelBreakdown(dc,providers[0]);
        for(int p=0;p<providers.Length;p++)for(int m=0;m<2;m++)
        {
            var provider=providers[p];
            if(provider.Costs.Length==0) {
                if(m==0)Text(dc,"Usage history unavailable.",36+p*376+175.5,74,12,ParityTheme.White(.55),false,false,false,true);
                continue;
            }
            var data=provider.Costs[m];
            double x=36+p*376+m*184.5,y=24,width=166.5;
            BaselineText(dc,data.Label,x,y+11,11,ParityTheme.White(.55));
            BaselineText(dc,"↻ "+(m==0?ParityData.TodayResetIn(DateTimeOffset.Now,TimeZoneInfo.Local):ParityData.MonthResetIn(DateTime.Today)),x+width,y+11,10,ParityTheme.White(.4),false,true,true);
            if(CostStyle==0)
            {
                double baseline=y+78;
                double symbolWidth=BaselineText(dc,CurrencySymbol,x,baseline,15,ParityTheme.White(.4));
                double number=GlowText(dc,Money(data.Dollars*CounterProgress,false),x+symbolWidth+1,baseline,38,provider.Color,data.Dollars,width-symbolWidth-1-(data.UnpricedTokens>0?13:0));
                if(data.UnpricedTokens>0)BaselineText(dc,"+",x+symbolWidth+number+3,baseline,17,ParityTheme.White(.55));
            }
            else if(CostStyle==2)
            {
                var tokens=ParityData.Tokens(Preferences.TokenMode=="billable"?data.BillableTokens:data.Tokens);
                double baseline=y+78;
                double w=GlowText(dc,tokens.Value,x,baseline,38,provider.Color,data.Dollars,width-Measure(tokens.Unit,15)-3);
                BaselineText(dc,tokens.Unit,x+w+3,baseline,15,ParityTheme.White(.4));
            }
            else if(CostStyle==1)
            {
                double? reference=IsDemo?provider.PlanDollars:LivePlanReference(provider);
                double plan=reference??0,max=Math.Max(.0001,Math.Max(plan,data.Dollars));
                double firstWidth=Math.Max(24,Measure(reference==null?"--":Money(plan),11,true,true));
                double secondWidth=Math.Max(24,Measure(Money(data.Dollars),11,true,true));
                double left=x+(width-firstWidth-secondWidth-14)/2;
                for(int b=0;b<2;b++)
                {
                    double amount=b==0?plan:data.Dollars,bx=left+(b==0?firstWidth/2:firstWidth+14+secondWidth/2)-12,h=Math.Max(3,amount/max*36);
                    BaselineText(dc,b==0&&reference==null?"--":Money(amount)+(b==1&&data.UnpricedTokens>0?"+":""),bx+12,y+38,11,b==0?ParityTheme.White(.78):ParityTheme.Brush(provider.Color),true,true,false,true);
                    if(b==0)dc.DrawRoundedRectangle(ParityTheme.White(.2),null,new Rect(bx,y+80-h,24,h),3,3);
                    else drawingGlow?.DrawGeometry(new RectangleGeometry(new Rect(bx,y+80-h,24,h),3,3),provider.Color,GlowOpacity(data.Dollars),10);
                    BaselineText(dc,b==0?string.IsNullOrEmpty(provider.Plan)?"Plan":provider.Plan:"You",bx+12,y+93,10,ParityTheme.White(.5),false,false,false,true);
                }
            }
            else
            {
                Trend(dc,new Rect(x,y+25.5,width,70.5),data.Series,provider.Color);
                BaselineText(dc,Money(data.Dollars)+(data.UnpricedTokens>0?"+":""),x+width,y+93,11,ParityTheme.Brush(provider.Color),true,true,true);
            }
        }
    }

    private static double? LivePlanReference(DemoProvider provider)=>(provider.Id,provider.Plan.ToLowerInvariant()) switch {
        ("claude","pro")=>20,("claude","max")=>200,("codex","plus")=>20,("codex","prolite")=>100,("codex","pro")=>200,("antigravity","google ai pro")=>19.99,_=>null};

    private void Overview(DrawingContext dc)
    {
        if(!HasHistory){using var empty=calendarGrid.RenderOpen();calendarGrid.Opacity=0;Text(dc,"Usage history unavailable.",400,86,12,ParityTheme.White(.55),false,false,false,true);return;}
        var history=HistoryDays;
        var key=new OverviewKey(history,DateTime.Today,SelectedDay,SelectedProvider,Localizer.Culture.Name,pixelsPerDip);
        if(overviewKey!=key) {
            overviewTargets.Clear();var content=new DrawingGroup();
            using(var drawing=content.Open())BuildOverview(drawing,history);
            if(content.CanFreeze)content.Freeze();overviewContent=content;overviewKey=key;DrawCalendarHover();
        }
        dc.DrawDrawing(overviewContent);
        calendarPosition.X=(2-PagePosition)*800+FeedbackOffset;
        if(Page==2&&Math.Abs(PagePosition-2)<.005&&Expanded&&ContentOpacity>.9)targets.AddRange(overviewTargets);
    }

    private void BuildOverview(DrawingContext dc,DemoDay[] history)
    {
        OverviewBuildCount++;
        calendarCells.Clear();
        DateTime today=DateTime.Today,first=new(today.Year,1,1),start=first.AddDays(-(int)first.DayOfWeek);
        var map=history.ToDictionary(d=>d.Date);
        Dictionary<string,long> Counts(DemoDay d)=>d.Tokens;
        long Total(DemoDay d)=>SelectedProvider==null?Counts(d).Values.Sum():Counts(d).GetValueOrDefault(SelectedProvider);
        var days=history.Where(d=>d.Date.Year==today.Year).ToList();
        var selected=SelectedDay is DateTime chosen?days.FirstOrDefault(d=>d.Date==chosen)??new DemoDay(chosen,new(),new(),new()):null;
        long total=selected!=null?Total(selected):days.Sum(Total);
        var tokens=ParityData.Tokens(total);
        string label=SelectedDay?.ToString("MMM d",Localizer.Culture).ToUpperInvariant()??(SelectedProvider==null?"":ParityData.Provider(SelectedProvider).Name.ToUpperInvariant()+" · ")+$"{today.Year} TOKENS";
        BaselineText(dc,label,16,22,10,ParityTheme.White(.55),true,tracking:.7);
        double number=BaselineText(dc,tokens.Value,16,46,18,ParityTheme.White(),true,true);
        BaselineText(dc,tokens.Unit,20+number,46,15,ParityTheme.White(.4));
        string dominance=total==0?"No Activity":"Mixed Use";
        if(selected!=null) {var leading=Counts(selected).FirstOrDefault(p=>(SelectedProvider==null||p.Key==SelectedProvider)&&p.Value>=total*.6);if(leading.Key!=null)dominance="Mostly "+ParityData.Provider(leading.Key).Name;}
        BaselineText(dc,selected!=null?dominance:$"{days.Count(d=>Total(d)>0)} Active Days",112,42,11,ParityTheme.White(.5));
        var legend=ParityData.Providers.Where(p=>days.Sum(d=>Counts(d).GetValueOrDefault(p.Id))>0).Select(p=>(Id:p.Id,Count:selected==null?days.Sum(d=>Counts(d).GetValueOrDefault(p.Id)):Counts(selected).GetValueOrDefault(p.Id))).ToArray();
        long legendTotal=legend.Sum(p=>p.Count);
        for(int i=0;i<legend.Length;i++)
        {
            var item=legend[i];double lx=555+(i%2)*120,ly=7+(i/2)*22;
            dc.DrawEllipse(ParityTheme.Brush(ParityData.Colors[item.Id]),null,new Point(lx+3,ly+6.5),2.5,2.5);
            string name=ParityData.Provider(item.Id).Name;
            double percent=item.Count*100.0/Math.Max(1,legendTotal);
            if(SelectedProvider==item.Id)dc.DrawRoundedRectangle(ParityTheme.Brush(ParityData.Colors[item.Id],.18),null,new Rect(lx-1,ly-3,110,17),4,4);
            BaselineText(dc,name+" "+(percent>0&&percent<1?"<1%":$"{percent:0}%"),lx+9,ly+10,10,ParityTheme.White(SelectedProvider==item.Id ? .95 : .46),false,true);
            overviewTargets.Add((new Rect(lx,ly+38,118,17),"Filter "+name,()=>{SelectedProvider=SelectedProvider==item.Id?null:item.Id;InvalidateVisual();}));
        }
        for(int month=1;month<=12;month++)
        {
            var date=new DateTime(today.Year,month,1);int week=(date-start).Days/7;
            BaselineText(dc,date.ToString("MMM",CultureInfo.InvariantCulture),16+week*13.95,71.5,10,ParityTheme.White(.4),false,true);
        }
        var positives=days.Select(Total).Where(x=>x>0).OrderBy(x=>x).ToArray();
        int Level(long tokens) {
            if (tokens <= 0 || positives.Length == 0) return 0;
            double rank = positives.Count(v=>v<=tokens)/(double)positives.Length;
            return rank<.15?1:rank<.35?2:rank<.60?3:rank<.80?4:rank<.93?5:6;
        }
        double[] levels = [.035,.14,.26,.42,.62,.82,.98];
        using var grid=calendarGrid.RenderOpen();
        grid.DrawRectangle(Brushes.Black,null,new Rect(0,80,800,98));
        for(DateTime date=first;date.Year==today.Year;date=date.AddDays(1))
        {
            int offset=(date-start).Days,col=offset/7,row=offset%7;
            double x=16+col*13.95,y=81+row*13.95;
            var rect=new Rect(x,y,11.6,11.6);
            var day=map.GetValueOrDefault(date);long count=day==null?0:Total(day);
            string? lead=(day==null?null:Counts(day))?.Where(t=>SelectedProvider==null||t.Key==SelectedProvider).OrderByDescending(t=>t.Value).FirstOrDefault().Key;
            Color tint=lead==null?Colors.White:ParityData.Colors[lead];
            double opacity=date > today ? .012 : levels[Level(count)];
            var cell=new RectangleGeometry(rect,2.55,2.55);cell.Freeze();grid.PushClip(cell);
            grid.DrawRectangle(ParityTheme.Brush(tint,opacity),null,rect);
            if(day!=null && SelectedProvider==null && count>0 && Counts(day).Count>1)
            {
                double stripeX=x;
                foreach(var item in ParityData.Providers.Where(p=>Counts(day).GetValueOrDefault(p.Id)>0).Select(p=>new KeyValuePair<string,long>(p.Id,Counts(day)[p.Id])))
                {
                    double portion=rect.Width*item.Value/count;
                    grid.DrawRectangle(ParityTheme.Brush(ParityData.Colors[item.Key],Math.Max(.35,opacity)),null,new Rect(stripeX,rect.Bottom-2.32,portion,2.32));
                    stripeX+=portion;
                }
            }
            grid.Pop();
            double border=SelectedDay==date?.72:date>today?.03:count>0?.06+Level(count)*.012:.04;
            grid.DrawRoundedRectangle(null,new Pen(ParityTheme.White(border),SelectedDay==date?1.2:.5),rect,2.55,2.55);
            if(date<=today)
            {
                DateTime dayDate=date;
                calendarCells[new Rect(x,y+38,11.6,11.6)]=(date,border);
                overviewTargets.Add((new Rect(x,y+38,11.6,11.6),$"{date:MMM d}: {count:N0} tokens",()=>SelectDay(dayDate)));
            }
        }
    }

    private void DrawCalendarHover()
    {
        using var draw=calendarHover.RenderOpen();
        if(!Expanded||Page!=2||!calendarCells.TryGetValue(hoveredTarget,out var cell)||SelectedDay==cell.Date)return;
        var rect=hoveredTarget;rect.Offset(0,-38);
        double opacity=(.22-cell.Border)/(1-cell.Border);
        draw.DrawRoundedRectangle(null,new Pen(ParityTheme.White(opacity),.5),rect,2.55,2.55);
    }

    private void RenderDetail(double width,double bodyHeight)
    {
        using var dc=detailBody.RenderOpen();
        double progress=Math.Clamp(DetailProgress,0,1);
        DateTime? date=SelectedDay??departingDay;
        detailBody.Opacity=progress;
        detailBody.Effect=progress<1?new BlurEffect {Radius=2*(1-progress),RenderingBias=RenderingBias.Performance}:null;
        detailBody.Clip=new RectangleGeometry(new Rect(0,0,800,bodyHeight));
        if(!HasHistory||date==null||progress<=0||Math.Abs(2-PagePosition)>=1)return;
        dc.PushTransform(new TranslateTransform((2-PagePosition)*800+FeedbackOffset,0));
        dc.PushTransform(new ScaleTransform(.98+.02*progress,.98+.02*progress,400,193));
        var selected=HistoryDays.FirstOrDefault(d=>d.Date==date)??new DemoDay(date.Value,new(),new(),new());
        long total=SelectedProvider==null?selected.Tokens.Values.Sum():selected.Tokens.GetValueOrDefault(SelectedProvider);
        dc.DrawLine(new Pen(ParityTheme.White(.075),.5),new Point(16,193),new Point(784,193));
        BaselineText(dc,date.Value.ToString("ddd, MMM d",Localizer.Culture).ToUpper(Localizer.Culture),16,211.5,10,ParityTheme.White(.58),true,tracking:.6);
        BaselineText(dc,"All Tokens",16,226.5,10,ParityTheme.White(.36),false,true);
        var detail=ParityData.Providers.Where(p=>(SelectedProvider==null||p.Id==SelectedProvider)&&selected.Tokens.GetValueOrDefault(p.Id)>0)
            .Select(p=>(p.Id,p.Name,Tokens:selected.Tokens.GetValueOrDefault(p.Id),p.Color)).ToList();
        detail.Insert(0,("total","TOTAL",total,Colors.White));
        double right=784;
        for(int i=detail.Count-1;i>=0;i--) {
            var metric=detail[i];
            BaselineText(dc,metric.Name.ToUpper(Localizer.Culture),right,211,9,ParityTheme.Brush(metric.Color,i==0?.546:.82),true,true,true,tracking:.5,max:82);
            BaselineText(dc,metric.Tokens.ToString("N0",Localizer.Culture),right,226,11,ParityTheme.White(.76),true,true,true,max:82,minimumScale:.72);
            right-=96;
        }
        dc.Pop();dc.Pop();
    }

    private void Footer(DrawingContext dc,double y)
    {
        double rowCenter=y+(Page==2?22:22.5);
        if(Page!=2)dc.DrawRectangle(new LinearGradientBrush(new GradientStopCollection { new(Colors.Transparent,0),new(Color.FromArgb(15,255,255,255),.2),new(Color.FromArgb(15,255,255,255),.8),new(Colors.Transparent,1) },new Point(0,0),new Point(1,0)),null,new Rect(24,y,752,1));
        Gear(dc,36,rowCenter);
        AddTarget(new Rect(24,y+8,24,28),"Settings",()=>SettingsRequested?.Invoke());
        string label=Page==0?ParityData.ChartNames[ChartStyle]:Page==1?(CostStyle==0?Currency?.DisplayCurrency??"USD":ParityData.CostNames[CostStyle]):DateTime.Today.Year.ToString();
        double chip=Chip(dc,label,60,rowCenter-8,.78,true);
        if(Page<2)
        {
            AddTarget(new Rect(57,y+8,chip+6,28),"Cycle visualization (Ctrl+click)",()=>StyleRequested?.Invoke());
            if(!HasCycled)BaselineText(dc,"Ctrl  click to cycle",70+chip,IslandTypography.RowBaseline(rowCenter,11),11,ParityTheme.White(.42));
        }
        else if(HasHistory)
        {
            ShareIcon(dc,76+chip,rowCenter-5.6);
            BaselineText(dc,"Share usage",94+chip,IslandTypography.RowBaseline(rowCenter,11),11,ParityTheme.White(.72),true);
            AddTarget(new Rect(70+chip,y+8,117,28),"Create your usage card",()=>ShareRequested?.Invoke());
        }
        for(int i=0;i<3;i++)
        {
            int index=i;double x=390+i*10;
            dc.DrawEllipse(ParityTheme.White(Page == i ? .78 : .22),null,new Point(x,rowCenter),2.5,2.5);
            AddTarget(new Rect(x-5,y+12,10,20),ParityData.PageNames[i]+$" (Ctrl+{i+1})",()=>PageRequested?.Invoke(index));
        }
        footerStatus.SetAmbientVisible(AmbientVisible&&Expanded);
        footerStatus.Update(FooterStatus.Read(Feed,Page,Preferences.SelectedProviders),rowCenter,pixelsPerDip,
            IsVisible,!ReduceMotion&&!LowPower,ContentOpacity,new Vector((ActualWidth-800)/2,-8*(1-ContentOpacity)));
        footerStatus.SetPointer(IsMouseOver?ContentPoint(Mouse.GetPosition(this)):null,IsKeyboardFocusWithin&&FocusedTarget==FooterStatusLayer.TargetId,Mouse.LeftButton==MouseButtonState.Pressed);
    }

    private static void ShareIcon(DrawingContext dc,double x,double y)
    {
        dc.PushTransform(new ScaleTransform(.8,.8,x,y));
        var pen=new Pen(ParityTheme.White(.72),1.3) {StartLineCap=PenLineCap.Round,EndLineCap=PenLineCap.Round,LineJoin=PenLineJoin.Round};
        var shape=new StreamGeometry();
        using(var path=shape.Open()) {
            path.BeginFigure(new Point(x+3,y+5),false,false);path.LineTo(new Point(x+1,y+5),true,false);path.LineTo(new Point(x+1,y+14),true,false);path.LineTo(new Point(x+11,y+14),true,false);path.LineTo(new Point(x+11,y+5),true,false);path.LineTo(new Point(x+9,y+5),true,false);
            path.BeginFigure(new Point(x+6,y+10),false,false);path.LineTo(new Point(x+6,y),true,false);
            path.BeginFigure(new Point(x+3,y+3),false,false);path.LineTo(new Point(x+6,y),true,false);path.LineTo(new Point(x+9,y+3),true,false);
        }
        dc.DrawGeometry(null,pen,shape);dc.Pop();
    }

    private void Separator(DrawingContext dc)
    {
        var brush=new LinearGradientBrush(Colors.Transparent,Colors.Transparent,new Point(0,0),new Point(0,1));
        brush.GradientStops.Insert(1,new GradientStop(Color.FromArgb(15,255,255,255),.5));
        dc.DrawRectangle(brush,null,new Rect(399.5,32,1,80));
    }
    private Brush Urgency(double value)
    {
        double used=Remaining?100-value:value;
        return used>=90?ParityTheme.Brush(Color.FromRgb(230,95,95)):used>=70?ParityTheme.Brush(Color.FromRgb(232,168,90)):ParityTheme.White();
    }
    private void Logo(DrawingContext dc,string id,double x,double y,double size,Color color)
    {
        dc.PushOpacityMask(new ImageBrush(logos[id]) { Stretch=Stretch.Fill });
        dc.DrawRectangle(ParityTheme.Brush(color),null,new Rect(x,y,size,size));dc.Pop();
    }
    private static string HeroDollars(double value) => value.ToString(value >= 100 ? "N0" : value >= 10 ? "N1" : "N2", CultureInfo.InvariantCulture);

    private static double GlowOpacity(double dollars)=>dollars<=0?0:Math.Min(.85,.20+Math.Log(dollars+1)/Math.Log(2000)*.65);
    private double GlowText(DrawingContext dc,string value,double x,double baseline,double size,Color color,double dollars,double max)
    {
        long started=FrameDiagnostics.Begin();
        var text = Format(value,size,ParityTheme.Brush(color),true,true);
        double scale=IslandTypography.WidthScale(size,true,true),fit=Math.Min(1,max/Math.Max(1,text.WidthIncludingTrailingWhitespace*scale));
        if(fit<.5){text.MaxTextWidth=max/(scale*.5);text.MaxLineCount=1;text.Trimming=TextTrimming.CharacterEllipsis;fit=.5;}
        double vertical=IslandTypography.HeightScale(size,true,true)*fit;
        drawingGlow?.Draw(text,new Point(x,baseline-text.Baseline*vertical),color,GlowOpacity(dollars),scale*fit,vertical);
        FrameDiagnostics.End(started,"dollar-glow",Page,CounterProgress);
        return Math.Min(max,text.WidthIncludingTrailingWhitespace*scale*fit);
    }

    private double Text(DrawingContext dc,string value,double x,double y,double size,Brush color,bool bold=false,bool mono=false,bool right=false,bool center=false,double tracking=0,double max=double.PositiveInfinity,double minimumScale=1)
    {
        return IslandTypography.Draw(dc,Localizer.Text(value),x,y,size,color,pixelsPerDip,bold,mono,right,center,tracking,max,minimumScale);
    }
    private FormattedText Format(string value,double size,Brush brush,bool bold,bool mono)=>IslandTypography.Make(value,size,brush,pixelsPerDip,bold,mono);
    private double BaselineText(DrawingContext dc,string value,double x,double baseline,double size,Brush color,bool bold=false,bool mono=false,bool right=false,bool center=false,double tracking=0,double max=double.PositiveInfinity,double minimumScale=1)
        =>IslandTypography.Draw(dc,Localizer.Text(value),x,baseline,size,color,pixelsPerDip,bold,mono,right,center,tracking,max,minimumScale,true);
    private double Measure(string value,double size,bool bold=false,bool mono=false)=>IslandTypography.Width(value,size,pixelsPerDip,bold,mono);
    private double Chip(DrawingContext dc,string value,double x,double y,double opacity,bool footer=false)
    {
        double padding=footer?6:5,height=footer?16:15;
        double width=Measure(value,9,true,true)+padding*2+(value.Length-1)*.8;
        dc.DrawRoundedRectangle(ParityTheme.White(footer ? .08 : .06),footer?new Pen(ParityTheme.White(.1),.5):null,new Rect(x,y,width,height),footer?4:3,footer?4:3);
        BaselineText(dc,value,x+padding,IslandTypography.RowBaseline(y+height/2,9),9,ParityTheme.White(opacity),true,true,tracking:.8);
        return width;
    }
    private static void Arc(DrawingContext dc,Point center,double radius,double fraction,Color color,double thickness)
    {
        double theta=Math.Clamp(fraction,.001,.99999)*Math.PI*2;
        var path=new StreamGeometry();using(var c=path.Open())
        { c.BeginFigure(new Point(center.X,center.Y-radius),false,false);c.ArcTo(new Point(center.X+Math.Sin(theta)*radius,center.Y-Math.Cos(theta)*radius),new Size(radius,radius),0,theta>Math.PI,SweepDirection.Clockwise,true,false); }
        dc.DrawGeometry(null,new Pen(ParityTheme.Brush(color),thickness) { StartLineCap=PenLineCap.Round,EndLineCap=PenLineCap.Round },path);
    }
    private static void Spark(DrawingContext dc,Rect rect,double value,Color color,int seed)
    {
        double acc=value*.85;var values=new List<double>();
        for(int i=0;i<36;i++) { double noise=Math.Sin((i+seed)*1.3)*14+Math.Cos((i+seed)*.7)*8;acc=acc*.65+(value+noise)*.35;values.Add(Math.Min(95,Math.Max(18,acc))); }
        values[^1]=value;
        for(int i=1;i<=3;i++)dc.DrawLine(new Pen(ParityTheme.White(.04),1),new Point(rect.Left,rect.Top+rect.Height*i/4),new Point(rect.Right,rect.Top+rect.Height*i/4));
        double baseline=rect.Bottom-value/100*(rect.Height-8)-4;
        dc.DrawLine(new Pen(ParityTheme.Brush(color,.25),1) { DashStyle=new DashStyle(new double[]{2,3},0) },new Point(rect.Left,baseline),new Point(rect.Right,baseline));
        var points=values.Select((v,i)=>new Point(rect.Left+i*rect.Width/35,rect.Bottom-v/100*(rect.Height-8)-4)).ToArray();
        Plot(dc,rect,points,color);
        dc.DrawEllipse(ParityTheme.Brush(color,.15),null,points[^1],5,5);dc.DrawEllipse(ParityTheme.Brush(color),null,points[^1],2.5,2.5);
    }
    private static void Trend(DrawingContext dc,Rect rect,double[] values,Color color)
    {
        double max=Math.Max(1,values.Max());
        var points=values.Select((v,i)=>new Point(rect.Left+i*rect.Width/(values.Length-1),rect.Bottom-v/max*rect.Height)).ToArray();
        Plot(dc,rect,points,color);
    }
    private static void RecordedSpark(DrawingContext dc,Rect rect,double value,Color color,double[] values)
    {
        for(int i=1;i<=3;i++)dc.DrawLine(new Pen(ParityTheme.White(.04),1),new Point(rect.Left,rect.Top+rect.Height*i/4),new Point(rect.Right,rect.Top+rect.Height*i/4));
        double baseline=rect.Bottom-value/100*(rect.Height-8)-4;
        dc.DrawLine(new Pen(ParityTheme.Brush(color,.25),1) {DashStyle=new DashStyle(new double[]{2,3},0)},new Point(rect.Left,baseline),new Point(rect.Right,baseline));
        if(values.Length==0)values=[value];else values[^1]=value;
        var points=values.Select((v,i)=>new Point(values.Length==1?rect.Right:rect.Left+i*rect.Width/(values.Length-1),rect.Bottom-Math.Clamp(v,0,100)/100*(rect.Height-8)-4)).ToArray();
        if(points.Length>1)Plot(dc,rect,points,color);
        dc.DrawEllipse(ParityTheme.Brush(color,.15),null,points[^1],5,5);dc.DrawEllipse(ParityTheme.Brush(color),null,points[^1],2.5,2.5);
    }
    private static void Plot(DrawingContext dc,Rect rect,Point[] points,Color color)
    {
        var line=new StreamGeometry();using(var c=line.Open()){c.BeginFigure(points[0],false,false);c.PolyLineTo(points.Skip(1).ToArray(),true,false);}
        var fill=new StreamGeometry();using(var c=fill.Open()){c.BeginFigure(points[0],true,true);c.PolyLineTo(points.Skip(1).ToArray(),true,false);c.LineTo(new Point(rect.Right,rect.Bottom),true,false);c.LineTo(new Point(rect.Left,rect.Bottom),true,false);}
        dc.DrawGeometry(new LinearGradientBrush(Color.FromArgb(71,color.R,color.G,color.B),Colors.Transparent,new Point(0,0),new Point(0,1)),null,fill);
        dc.DrawGeometry(null,new Pen(ParityTheme.Brush(color),1.4) { LineJoin=PenLineJoin.Round,StartLineCap=PenLineCap.Round,EndLineCap=PenLineCap.Round },line);
    }
    private void Gear(DrawingContext dc,double x,double y)
    {
        var path=new StreamGeometry();using(var c=path.Open())
        {
            for(int i=0;i<32;i++){double a=i*Math.PI/16,r=i%4<2?5.5:4.4;var p=new Point(x+Math.Cos(a)*r,y+Math.Sin(a)*r);if(i==0)c.BeginFigure(p,false,true);else c.LineTo(p,true,false);}
        }
        dc.DrawGeometry(null,new Pen(ParityTheme.White(.4),1),path);dc.DrawEllipse(null,new Pen(ParityTheme.White(.4),1),new Point(x,y),1.8,1.8);
    }
    private void AddTarget(Rect bounds,string help,Action action) {
        if(capturingTargets!=null)capturingTargets.Add((bounds,help,action));
        else if(Expanded&&ContentOpacity>.9)targets.Add((bounds,help,action));
    }
}

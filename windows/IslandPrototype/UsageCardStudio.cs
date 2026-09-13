using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shell;
using Microsoft.Win32;
using Clipboard=System.Windows.Clipboard;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage;
using Windows.Storage.Streams;
using static IslandPrototype.SettingsControls;

namespace IslandPrototype;

internal sealed class UsageCardStudio : Window
{
    private readonly PreferenceStore preferences;
    private readonly HashSet<string> included=ParityData.Providers.Select(p=>p.Id).ToHashSet();
    private CardPeriod period;
    private CardMetric metric;
    private CardFormat format;
    private string signature="";
    private bool actualSize;
    private readonly Grid canvas=new();
    private readonly StackPanel controls=new();
    private readonly TextBlock sizeLabel=Label("",10,.6,false,true),status=Label("",11,.75);
    private readonly Button sizeButton,shareButton,moreButton;
    private UsageCardSnapshot snapshot;
    private UsageCardVisual card;
    private NativeCardShare? sharing;

    private readonly UsageFeed? feed;
    private readonly System.Windows.Threading.DispatcherTimer dateTimer=new(){Interval=TimeSpan.FromMinutes(1)};
    private DateTime snapshotDate=DateTime.Today;
    private DemoDay[]? lastHistory;
    private readonly TextBlock pricingWarning=Label("Some tokens have no known price. The + marks a partial value.",11,.6);
    public UsageCardStudio(PreferenceStore preferences,UsageFeed? feed=null)
    {
        this.preferences=preferences;this.feed=feed;
        metric=preferences.Value.CardMetric=="tokens"?CardMetric.Tokens:CardMetric.ApiValue;
        format=Enum.TryParse<CardFormat>(preferences.Value.CardFormat,true,out var parsed)?parsed:CardFormat.Feed;
        snapshot=MakeSnapshot();card=new UsageCardVisual(snapshot);
        Title=Localizer.Text("Usage card");Width=900;Height=740;MinWidth=780;MinHeight=640;
        WindowStyle=WindowStyle.None;ResizeMode=ResizeMode.CanResize;WindowStartupLocation=WindowStartupLocation.CenterScreen;
        Background=new SolidColorBrush(Color.FromRgb(5,5,7));Foreground=Brushes.White;FontFamily=ParityTheme.TextFont;
        WindowChrome.SetWindowChrome(this,new WindowChrome {CaptionHeight=52,ResizeBorderThickness=new Thickness(5),CornerRadius=new CornerRadius(10),GlassFrameThickness=new Thickness(0),UseAeroCaptionButtons=false});
        MouseLeftButtonDown+=(_,e)=>{if(e.ChangedButton==MouseButton.Left){DragMove();e.Handled=true;}};
        SourceInitialized+=(_,_)=>{int dark=1;Native.DwmSetWindowAttribute(new WindowInteropHelper(this).Handle,20,ref dark,4);};
        var root=new Grid();root.RowDefinitions.Add(new RowDefinition {Height=new GridLength(52)});root.RowDefinitions.Add(new RowDefinition());
        root.Children.Add(Header());
        var body=new Grid();body.ColumnDefinitions.Add(new ColumnDefinition());body.ColumnDefinitions.Add(new ColumnDefinition {Width=new GridLength(1)});body.ColumnDefinitions.Add(new ColumnDefinition {Width=new GridLength(280)});Grid.SetRow(body,1);root.Children.Add(body);
        var preview=new Grid {Background=new SolidColorBrush(Color.FromRgb(17,17,20))};preview.RowDefinitions.Add(new RowDefinition());preview.RowDefinitions.Add(new RowDefinition {Height=new GridLength(40)});body.Children.Add(preview);preview.Children.Add(canvas);
        var caption=new DockPanel {Margin=new Thickness(24,0,24,0),LastChildFill=false};Grid.SetRow(caption,1);preview.Children.Add(caption);sizeLabel.VerticalAlignment=VerticalAlignment.Center;caption.Children.Add(sizeLabel);
        sizeButton=Button("Actual size",()=>{actualSize=!actualSize;UpdatePreview();},0,4,true);DockPanel.SetDock(sizeButton,Dock.Right);caption.Children.Add(sizeButton);
        var rule=new Border {Background=ParityTheme.White(.06)};Grid.SetColumn(rule,1);body.Children.Add(rule);
        var sidebar=new Grid {Margin=new Thickness(20)};Grid.SetColumn(sidebar,2);body.Children.Add(sidebar);
        sidebar.RowDefinitions.Add(new RowDefinition());sidebar.RowDefinitions.Add(new RowDefinition {Height=GridLength.Auto});
        var scroll=new ScrollViewer {Content=controls,VerticalScrollBarVisibility=ScrollBarVisibility.Hidden,HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled};sidebar.Children.Add(scroll);
        var exports=new StackPanel();Grid.SetRow(exports,1);sidebar.Children.Add(exports);
        exports.Children.Add(new Border {Height=1,Background=ParityTheme.White(.06),Margin=new Thickness(0,10,0,16)});
        status.TextAlignment=TextAlignment.Center;status.Margin=new Thickness(0,0,0,10);status.Visibility=Visibility.Collapsed;exports.Children.Add(status);
        var exportRow=new Grid();exportRow.ColumnDefinitions.Add(new ColumnDefinition());exportRow.ColumnDefinitions.Add(new ColumnDefinition {Width=new GridLength(40)});exports.Children.Add(exportRow);
        shareButton=Button("Share…",Share,12,7);shareButton.Height=32;exportRow.Children.Add(shareButton);
        moreButton=Button("More export options",ShowExportMenu,0,0);moreButton.Content=Label("•••",13,.9,true);moreButton.Width=32;moreButton.Height=32;Grid.SetColumn(moreButton,1);exportRow.Children.Add(moreButton);
        Content=new Border {Child=root,CornerRadius=new CornerRadius(10),BorderBrush=ParityTheme.White(.12),BorderThickness=new Thickness(.5),Background=Background};
        canvas.SizeChanged+=(_,_)=>UpdatePreview();
        if(feed!=null)feed.Changed+=HistoryChanged;
        dateTimer.Tick+=(_,_)=>{if(snapshotDate!=DateTime.Today)Refresh();};dateTimer.Start();
        Closed+=(_,_)=>{sharing?.Dispose();dateTimer.Stop();if(feed!=null)feed.Changed-=HistoryChanged;};
        KeyDown+=(_,e)=>{
            if(e.Key==Key.Escape){Close();e.Handled=true;}
            else if(e.Key==Key.S && Keyboard.Modifiers==ModifierKeys.Control){SavePng();e.Handled=true;}
            else if(e.Key==Key.C && Keyboard.Modifiers==(ModifierKeys.Control|ModifierKeys.Shift)){CopyImage();e.Handled=true;}
        };
        RenderControls();UpdatePreview();
    }
    private FrameworkElement Header()
    {
        var grid=new Grid {Margin=new Thickness(12,0,16,0)};
        var caption=new StackPanel {Orientation=Orientation.Horizontal,HorizontalAlignment=HorizontalAlignment.Left};
        foreach(var item in new[]{("Close",Color.FromRgb(255,95,87),(Action)Close),("Minimize",Color.FromRgb(255,189,46),(Action)(()=>WindowState=WindowState.Minimized)),("Zoom",Color.FromRgb(40,201,64),(Action)(()=>WindowState=WindowState==WindowState.Maximized?WindowState.Normal:WindowState.Maximized))}) {
            var button=Button(item.Item1,item.Item3,0,0,true);button.Content=new System.Windows.Shapes.Ellipse {Width=12,Height=12,Fill=ParityTheme.Brush(item.Item2)};button.Margin=new Thickness(0,0,8,0);WindowChrome.SetIsHitTestVisibleInChrome(button,true);caption.Children.Add(button);
        }
        grid.Children.Add(caption);
        var actions=new StackPanel {Orientation=Orientation.Horizontal,HorizontalAlignment=HorizontalAlignment.Right};
        var refresh=Button("Refresh records",RefreshRecords,0,0,true);refresh.Content=Label("↻",16,.65);refresh.Width=28;refresh.Height=28;refresh.Margin=new Thickness(0,0,12,0);WindowChrome.SetIsHitTestVisibleInChrome(refresh,true);actions.Children.Add(refresh);
        var info=Button("About this card",()=>IslandDialog.Show(this,"About this card","API value estimates your usage at API rates in USD, not your subscription bill. Tokens include cache reads and writes.\n\nThe card includes daily usage, provider totals, active days, and your signature. It does not include prompts or conversations."+(snapshot.IsDemo?"\n\nThese cards currently contain clearly labeled demo data.":"\n\nUsage comes from local records saved on this computer."),"OK"),0,0,true);info.Content=Label("ⓘ",16,.65);info.Width=28;info.Height=28;WindowChrome.SetIsHitTestVisibleInChrome(info,true);actions.Children.Add(info);grid.Children.Add(actions);return grid;
    }
    private void RenderControls()
    {
        controls.Children.Clear();
        void Caption(string title) {var label=Label(title,11,.6);label.Margin=new Thickness(0,0,0,8);controls.Children.Add(label);}
        Caption("Show");
        var metricSelector=Segmented("Show",["API value","Tokens"],(int)metric,i=>{metric=(CardMetric)i;preferences.Update(preferences.Value with {CardMetric=i==1?"tokens":"apiValue"});Refresh();RenderControls();});
        metricSelector.HorizontalAlignment=HorizontalAlignment.Left;
        controls.Children.Add(metricSelector);
        void PickerRow(string label,(string Label,string Value)[] choices,string current,Action<string> changed) {
            var row=new DockPanel {Margin=new Thickness(0,20,0,0),LastChildFill=false};var name=Label(label,11,.6);name.VerticalAlignment=VerticalAlignment.Center;row.Children.Add(name);
            var menu=Menu(label,choices,current,changed);DockPanel.SetDock(menu,Dock.Right);row.Children.Add(menu);controls.Children.Add(row);
        }
        PickerRow("Period",UsageCardSnapshot.PeriodTitles.Select((name,i)=>(name,i.ToString())).ToArray(),((int)period).ToString(),value=>{period=(CardPeriod)int.Parse(value);Refresh();RenderControls();});
        controls.Children.Add(new Border {Height=1,Background=ParityTheme.White(.06),Margin=new Thickness(0,20,0,0)});
        PickerRow("Format",[("Feed · 4:5","0"),("Square · 1:1","1"),("Story · 9:16","2")],((int)format).ToString(),value=>{format=(CardFormat)int.Parse(value);preferences.Update(preferences.Value with {CardFormat=format.ToString().ToLowerInvariant()});Refresh();RenderControls();});
        var signatureLabel=Label("Signature",11,.6);signatureLabel.Margin=new Thickness(0,20,0,8);controls.Children.Add(signatureLabel);
        var input=new TextBox {Text=signature,Padding=new Thickness(8,5,8,5),Background=ParityTheme.White(.06),BorderBrush=ParityTheme.White(.12),BorderThickness=new Thickness(1),Foreground=ParityTheme.White(.9),CaretBrush=Brushes.White,FontSize=12};
        AutomationProperties.SetName(input,"Name or handle on card");input.ToolTip=Localizer.Text("Name or @handle (optional)");
        input.TextChanged+=(_,_)=>{string cleaned=CleanSignature(input.Text);if(cleaned!=input.Text){int position=input.CaretIndex;input.Text=cleaned;input.CaretIndex=Math.Min(position,cleaned.Length);}signature=cleaned;UpdatePreview();SetStatus(null);};controls.Children.Add(input);
        var label2=Label("Providers",11,.6);label2.Margin=new Thickness(0,20,0,12);controls.Children.Add(label2);
        var grid=new UniformGrid {Columns=2};controls.Children.Add(grid);
        foreach(var provider in ParityData.Providers) {
            var checkbox=new CardCheckbox(provider.Name,provider.Color) {IsChecked=included.Contains(provider.Id),Margin=new Thickness(0,0,0,12)};
            AutomationProperties.SetName(checkbox,provider.Name);
            void InclusionChanged(){if(checkbox.IsChecked==true)included.Add(provider.Id);else included.Remove(provider.Id);Refresh();}
            checkbox.Checked+=(_,_)=>InclusionChanged();checkbox.Unchecked+=(_,_)=>InclusionChanged();grid.Children.Add(checkbox);
        }
        pricingWarning.Margin=new Thickness(0,8,0,0);pricingWarning.Visibility=snapshot.PartialPricing&&metric==CardMetric.ApiValue?Visibility.Visible:Visibility.Collapsed;controls.Children.Add(pricingWarning);
    }
    private static string CleanSignature(string input)
    {
        var text=StringInfo.GetTextElementEnumerator(input);var result=new System.Text.StringBuilder();int count=0;
        while(text.MoveNext()&&count<32) {string element=text.GetTextElement();if(element.Any(c=>c<32||c==127||c is '\u0085' or '\u2028' or '\u2029'))continue;result.Append(element);count++;}return result.ToString();
    }
    private UsageCardSnapshot MakeSnapshot(){lastHistory=feed?.Days;snapshotDate=DateTime.Today;return new(period,included,DateTime.Now,lastHistory,feed?.IsDemo??true);}
    private void HistoryChanged()=>Dispatcher.BeginInvoke(()=>{if(!ReferenceEquals(lastHistory,feed?.Days))Refresh();});
    private void RefreshRecords(){_=feed?.RefreshAsync(true);Refresh();}
    private void Refresh(){snapshot=MakeSnapshot();SetStatus(null);UpdatePreview();}
    private void UpdatePreview()
    {
        pricingWarning.Visibility=snapshot.PartialPricing&&metric==CardMetric.ApiValue?Visibility.Visible:Visibility.Collapsed;
        canvas.Children.Clear();card=new UsageCardVisual(snapshot) {Format=format,Metric=metric,Signature=signature};card.Update();
        sizeLabel.Text=$"1080 × {(int)(card.CardHeight*2)} PNG";sizeButton.Content=Label(actualSize?"Fit":"Actual size",11,.6);AutomationProperties.SetName(sizeButton,Localizer.Text(actualSize?"Fit":"Actual size"));
        bool enabled=snapshot.TotalTokens>0&&(metric==CardMetric.Tokens||snapshot.HasPricedUsage);shareButton.IsEnabled=enabled;moreButton.IsEnabled=enabled;sizeButton.IsEnabled=enabled;
        if(!enabled) {
            var empty=new StackPanel {VerticalAlignment=VerticalAlignment.Center,HorizontalAlignment=HorizontalAlignment.Center,MaxWidth=290};
            var title=Label(snapshot.TotalTokens==0?"No usage in this period.":"API prices are unavailable.",20,.8);title.TextAlignment=TextAlignment.Center;empty.Children.Add(title);
            var detail=Label(snapshot.TotalTokens==0?"No recorded tokens in this period. Try another period or include more providers.":"Refresh to load API prices, or choose Tokens.",12,.55);detail.TextAlignment=TextAlignment.Center;detail.Margin=new Thickness(0,14,0,14);empty.Children.Add(detail);empty.Children.Add(Button("Refresh records",RefreshRecords));canvas.Children.Add(empty);return;
        }
        if(actualSize) {canvas.Children.Add(new ScrollViewer {Content=new Border {Child=card,Padding=new Thickness(24)},HorizontalScrollBarVisibility=ScrollBarVisibility.Auto,VerticalScrollBarVisibility=ScrollBarVisibility.Auto});}
        else {
            var viewbox=new Viewbox {Child=card,Stretch=Stretch.Uniform,Margin=new Thickness(24),HorizontalAlignment=HorizontalAlignment.Center,VerticalAlignment=VerticalAlignment.Center};
            viewbox.MaxWidth=Math.Max(1,canvas.ActualWidth-48);viewbox.MaxHeight=Math.Max(1,canvas.ActualHeight-48);viewbox.Effect=new System.Windows.Media.Effects.DropShadowEffect {Color=Colors.Black,BlurRadius=32,ShadowDepth=8,Opacity=.25};canvas.Children.Add(viewbox);
        }
    }
    private string ExportFilename=>$"CodexIsland-{period}-{snapshot.Start:yyyy-MM-dd}-{metric}-{snapshot.Tier(metric)}-{format}.png";
    private BitmapSource ExportBitmap()=>new UsageCardVisual(snapshot) {Format=format,Metric=metric,Signature=signature}.Bitmap();
    private byte[] Png()
    {
        var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(ExportBitmap()));using var buffer=new MemoryStream();encoder.Save(buffer);return buffer.ToArray();
    }
    private void SetStatus(string? message) {status.Text=message??"";status.Visibility=message==null?Visibility.Collapsed:Visibility.Visible;}
    private void RunExport(Action action) {try {action();}catch(Exception error) when(error is IOException or UnauthorizedAccessException or ExternalException or InvalidOperationException){IslandDialog.Show(this,"Could not export card",error.Message,"OK");}}
    private void SavePng()=>RunExport(()=>{
        if(!shareButton.IsEnabled)return;
        var dialog=new SaveFileDialog {Filter="PNG image|*.png",FileName=ExportFilename};
        if(dialog.ShowDialog(this)!=true)return;File.WriteAllBytes(dialog.FileName,Png());SetStatus("Card saved.");
    });
    private void CopyImage()=>RunExport(()=>{if(!shareButton.IsEnabled)return;Clipboard.SetImage(ExportBitmap());SetStatus("Image copied. Paste it into your post.");});
    private void CopyCaption()=>RunExport(()=>{Clipboard.SetText(snapshot.Caption(metric));SetStatus("Caption copied.");});
    private void ShowExportMenu()
    {
        var menu=PopupMenu();
        foreach(var action in new[]{("Copy image",(Action)CopyImage),("Save PNG…",(Action)SavePng),("Copy caption",(Action)CopyCaption)}) {var option=new MenuItem {Header=Localizer.Text(action.Item1)};option.Click+=(_,_)=>action.Item2();menu.Items.Add(option);}
        menu.PlacementTarget=moreButton;menu.Placement=PlacementMode.Top;menu.IsOpen=true;
    }
    private async void Share()
    {
        if(!shareButton.IsEnabled)return;
        try {
            string directory=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"CodexIslandPrototype","shared-cards",Guid.NewGuid().ToString("N"));Directory.CreateDirectory(directory);
            string path=Path.Combine(directory,ExportFilename);File.WriteAllBytes(path,Png());
            var file=await StorageFile.GetFileFromPathAsync(path);
            sharing??=new NativeCardShare(new WindowInteropHelper(this).Handle);
            sharing.Show(file,snapshot.Caption(metric));
        } catch(Exception error) when(error is IOException or UnauthorizedAccessException or ExternalException or InvalidOperationException) {IslandDialog.Show(this,"Could not export card",error.Message,"OK");}
    }
}

internal sealed class NativeCardShare : IDisposable
{
    [ComImport,Guid("3A3DCD6C-3EAB-43DC-BCDE-45671CE800C8"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShareInterop {IntPtr GetForWindow(IntPtr window,ref Guid iid);void ShowShareUIForWindow(IntPtr window);}
    private readonly nint window;
    private readonly DataTransferManager manager;
    private StorageFile? file;
    private string caption="";
    public NativeCardShare(nint window)
    {
        this.window=window;Guid iid=new("a5caee9b-8708-49d1-8d36-67d25a8da00c");
        var pointer=DataTransferManager.As<IShareInterop>().GetForWindow(window,ref iid);
        try {manager=WinRT.MarshalInterface<DataTransferManager>.FromAbi(pointer);}finally{Marshal.Release(pointer);}
        manager.DataRequested+=Requested;
    }
    public void Show(StorageFile file,string caption){this.file=file;this.caption=caption;DataTransferManager.As<IShareInterop>().ShowShareUIForWindow(window);}
    private void Requested(DataTransferManager sender,DataRequestedEventArgs args)
    {
        if(file==null){args.Request.FailWithDisplayText("Create a card before sharing.");return;}
        var package=args.Request.Data;package.Properties.Title="CodexIsland usage card";package.Properties.Description="AI usage at API rates, with demo data clearly labeled.";
        package.SetText(caption);package.SetStorageItems([file]);package.SetBitmap(RandomAccessStreamReference.CreateFromFile(file));package.Properties.Thumbnail=RandomAccessStreamReference.CreateFromFile(file);package.RequestedOperation=DataPackageOperation.Copy;
    }
    public void Dispose()=>manager.DataRequested-=Requested;
}

internal sealed class CardCheckbox : CheckBox
{
    private readonly string title;
    private readonly Color tint;
    public CardCheckbox(string title,Color tint)
    {
        this.title=title;this.tint=tint;Height=20;MinWidth=104;Cursor=Cursors.Hand;
        Template=new ControlTemplate(typeof(CheckBox)) {VisualTree=new FrameworkElementFactory(typeof(Grid))};
        Checked+=(_,_)=>InvalidateVisual();Unchecked+=(_,_)=>InvalidateVisual();
        GotKeyboardFocus+=(_,_)=>InvalidateVisual();LostKeyboardFocus+=(_,_)=>InvalidateVisual();
        SettingsControls.Pressable(this,.97);
    }
    protected override void OnRender(DrawingContext dc)
    {
        bool on=IsChecked==true;
        dc.DrawRoundedRectangle(ParityTheme.White(on?.14:.03),new Pen(ParityTheme.White(IsKeyboardFocused?.75:.25),1),new Rect(.5,2.5,15,15),4,4);
        if(on) {
            var path=new StreamGeometry();using(var c=path.Open()){c.BeginFigure(new Point(4,10),false,false);c.LineTo(new Point(6.6,12.5),true,false);c.LineTo(new Point(12,7),true,false);}
            dc.DrawGeometry(null,new Pen(ParityTheme.White(.9),1.4) {StartLineCap=PenLineCap.Round,EndLineCap=PenLineCap.Round,LineJoin=PenLineJoin.Round},path);
        }
        dc.DrawEllipse(ParityTheme.Brush(tint),null,new Point(23.5,10),2.5,2.5);
        var text=new FormattedText(Localizer.Text(title),Localizer.Culture,FlowDirection.LeftToRight,new Typeface(ParityTheme.TextFont,FontStyles.Normal,FontWeights.Medium,FontStretches.Normal),12,ParityTheme.White(on?.85:.55),VisualTreeHelper.GetDpi(this).PixelsPerDip);
        dc.DrawText(text,new Point(31,(20-text.Height)/2));
    }
}

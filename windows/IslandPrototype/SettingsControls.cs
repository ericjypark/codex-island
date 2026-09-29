using System;
using System.Globalization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;

namespace IslandPrototype;

internal static class SettingsControls
{
    public static bool ReduceMotion { get; set; }
    public static bool MotionOff => ReduceMotion || !SystemParameters.ClientAreaAnimation;
    public static SolidColorBrush TextBrush(double opacity,double surface=0)
    {
        double blend=surface+(1-surface)*Math.Clamp(opacity,0,1);
        byte channel=(byte)Math.Round(5+250*blend);
        var brush=new SolidColorBrush(Color.FromRgb(channel,channel,(byte)Math.Round(7+248*blend)));brush.Freeze();return brush;
    }
    public static TextBlock Label(string text,double size=11,double opacity=.55,bool semibold=false,bool mono=false) => new() {
        Text=Localizer.Text(text),FontFamily=mono?ParityTheme.NumberFont:IslandTypography.TextFace,FontSize=size,
        FontWeight=semibold?FontWeights.SemiBold:FontWeights.Medium,Foreground=TextBrush(opacity),
        TextWrapping=TextWrapping.Wrap,LineHeight=Math.Ceiling(size*1.2),LineStackingStrategy=LineStackingStrategy.BlockLineHeight
    };

    public static Button Button(string text,Action action,double paddingX=12,double paddingY=5,bool plain=false)
    {
        var button=new Button { Content=Label(text,11,.9,true),Padding=new Thickness(paddingX,paddingY,paddingX,paddingY),
            Background=ParityTheme.White(plain?0:.10),BorderBrush=ParityTheme.White(plain?0:.08),BorderThickness=new Thickness(.5),
            Foreground=ParityTheme.White(.9),Cursor=Cursors.Hand,HorizontalContentAlignment=HorizontalAlignment.Center,VerticalContentAlignment=VerticalAlignment.Center };
        Template(button,6);
        AutomationProperties.SetName(button,Localizer.Text(text));
        button.Click+=(_,_)=>action();
        Pressable(button,.97);
        return button;
    }

    public static void Template(ButtonBase button,double radius)
    {
        var border=new FrameworkElementFactory(typeof(Border));
        border.SetValue(Border.CornerRadiusProperty,new CornerRadius(radius));
        foreach(var item in new[]{(Border.BackgroundProperty,"Background"),(Border.BorderBrushProperty,"BorderBrush"),(Border.BorderThicknessProperty,"BorderThickness"),(Border.PaddingProperty,"Padding")})
            border.SetBinding(item.Item1,new System.Windows.Data.Binding(item.Item2) { RelativeSource=System.Windows.Data.RelativeSource.TemplatedParent });
        var presenter=new FrameworkElementFactory(typeof(ContentPresenter));
        presenter.SetBinding(ContentPresenter.HorizontalAlignmentProperty,new System.Windows.Data.Binding("HorizontalContentAlignment") {RelativeSource=System.Windows.Data.RelativeSource.TemplatedParent});
        presenter.SetBinding(ContentPresenter.VerticalAlignmentProperty,new System.Windows.Data.Binding("VerticalContentAlignment") {RelativeSource=System.Windows.Data.RelativeSource.TemplatedParent});
        border.AppendChild(presenter);
        button.Template=new ControlTemplate(button.GetType()) { VisualTree=border };
    }

    public static void Pressable(ButtonBase button,double pressed)
    {
        var scale=new ScaleTransform(1,1);button.RenderTransform=scale;button.RenderTransformOrigin=new Point(.5,.5);
        void Animate(double value) {
            var animation=ParityTheme.Ease(value,MotionOff?0:.11);
            scale.BeginAnimation(ScaleTransform.ScaleXProperty,animation);scale.BeginAnimation(ScaleTransform.ScaleYProperty,animation);
        }
        button.PreviewMouseLeftButtonDown+=(_,_)=>Animate(pressed);
        button.PreviewMouseLeftButtonUp+=(_,_)=>Animate(1);
        button.MouseLeave+=(_,_)=>Animate(1);
        button.LostKeyboardFocus+=(_,_)=>Animate(1);
    }

    public static FrameworkElement Row(string title,string? subtitle,FrameworkElement trailing)
    {
        var grid=new Grid();grid.ColumnDefinitions.Add(new ColumnDefinition());grid.ColumnDefinitions.Add(new ColumnDefinition {Width=GridLength.Auto});
        var text=new StackPanel { VerticalAlignment=VerticalAlignment.Center };
        text.Children.Add(Label(title,13,.92));
        if(subtitle!=null) { var sub=Label(subtitle);sub.Margin=new Thickness(0,2,0,0);text.Children.Add(sub); }
        grid.Children.Add(text);Grid.SetColumn(trailing,1);trailing.Margin=new Thickness(36,0,0,0);trailing.VerticalAlignment=VerticalAlignment.Center;
        grid.Children.Add(trailing);
        var wash=new SolidColorBrush(Colors.White) { Opacity=0 };
        var border=new Border { Child=grid,Padding=new Thickness(10,11,10,11),CornerRadius=new CornerRadius(8),Background=wash };
        border.MouseEnter+=(_,_)=>wash.BeginAnimation(Brush.OpacityProperty,ParityTheme.Ease(.03,.12));
        border.MouseLeave+=(_,_)=>wash.BeginAnimation(Brush.OpacityProperty,ParityTheme.Ease(0,.12));
        return border;
    }

    public static FrameworkElement Segmented(string name,string[] items,int selected,Action<int> select)
    {
        Panel row;
        if(name=="Token counting") {
            var grid=new Grid {Width=162};grid.ColumnDefinitions.Add(new ColumnDefinition {Width=GridLength.Auto});grid.ColumnDefinitions.Add(new ColumnDefinition());row=grid;
        } else row=new StackPanel { Orientation=Orientation.Horizontal };
        for(int i=0;i<items.Length;i++) {
            int index=i;bool on=i==selected;
            var button=Button(items[i],()=>select(index),10,5,true);
            button.Content=Label(items[i],11,on?.95:.55,true,true);
            if(name=="Token counting"&&((TextBlock)button.Content).Text=="Input + output") {
                ((TextBlock)button.Content).Text="Input\n+ output";((TextBlock)button.Content).TextWrapping=TextWrapping.NoWrap;
            }
            ((TextBlock)button.Content).TextAlignment=TextAlignment.Center;button.VerticalAlignment=VerticalAlignment.Center;
            if(row is Grid)Grid.SetColumn(button,i);
            button.Background=ParityTheme.White(on?.10:0);button.BorderBrush=ParityTheme.White(on?.08:0);
            Template(button,5);AutomationProperties.SetName(button,Localizer.Text(name)+", "+Localizer.Text(items[i]));
            row.Children.Add(button);
        }
        return new Border { Child=row,Padding=new Thickness(2),CornerRadius=new CornerRadius(7),Background=ParityTheme.White(.04) };
    }

    public static Button Menu(string name,(string Label,string Value)[] items,string selected,Action<string> choose,double maxWidth=220)
    {
        var button=Button(Array.Find(items,v=>v.Value==selected).Label??selected,()=>{},10,5);
        var row=new DockPanel { LastChildFill=true };
        var chevron=new System.Windows.Shapes.Path {Data=Geometry.Parse("M 1 1 L 4 4 L 7 1"),Stroke=ParityTheme.White(.6),StrokeThickness=1.25,
            StrokeStartLineCap=PenLineCap.Round,StrokeEndLineCap=PenLineCap.Round,StrokeLineJoin=PenLineJoin.Round,Width=8,Height=5,Margin=new Thickness(12,0,0,0),VerticalAlignment=VerticalAlignment.Center};
        DockPanel.SetDock(chevron,Dock.Right);row.Children.Add(chevron);
        row.Children.Add(Label(Array.Find(items,v=>v.Value==selected).Label??selected,12,.85));button.Content=row;
        button.MaxWidth=maxWidth;button.HorizontalContentAlignment=HorizontalAlignment.Stretch;
        AutomationProperties.SetName(button,Localizer.Text(name));
        AutomationProperties.SetHelpText(button,Localizer.Text(Array.Find(items,v=>v.Value==selected).Label??selected));
        void Open() {
            var menu=PopupMenu();menu.MinWidth=Math.Max(144,button.ActualWidth);
            foreach(var item in items) {
                var option=new MenuItem { Header=Localizer.Text(item.Label),IsCheckable=true,IsChecked=item.Value==selected };
                option.Click+=(_,_)=>choose(item.Value);menu.Items.Add(option);
            }
            menu.PlacementTarget=button;menu.Placement=PlacementMode.Bottom;menu.VerticalOffset=4;menu.IsOpen=true;
        }
        button.Click+=(_,_)=>Open();
        button.PreviewKeyDown+=(_,e)=>{if(e.Key is Key.Down or Key.F4||e.Key==Key.System&&e.SystemKey==Key.Down){Open();e.Handled=true;}};
        return button;
    }

    public static ContextMenu PopupMenu()
    {
        var menu=new ContextMenu {Background=new SolidColorBrush(Color.FromRgb(24,24,27)),Foreground=ParityTheme.White(.92),BorderBrush=ParityTheme.White(.12),
            BorderThickness=new Thickness(1),Padding=new Thickness(4),FontFamily=ParityTheme.TextFont,FontSize=12,MaxWidth=320,MaxHeight=360,SnapsToDevicePixels=true};
        var border=new FrameworkElementFactory(typeof(Border));border.SetValue(Border.CornerRadiusProperty,new CornerRadius(8));
        foreach(var item in new[]{(Border.BackgroundProperty,"Background"),(Border.BorderBrushProperty,"BorderBrush"),(Border.BorderThicknessProperty,"BorderThickness"),(Border.PaddingProperty,"Padding")})
            border.SetBinding(item.Item1,new System.Windows.Data.Binding(item.Item2){RelativeSource=System.Windows.Data.RelativeSource.TemplatedParent});
        var scroll=new FrameworkElementFactory(typeof(ScrollViewer));scroll.SetValue(ScrollViewer.HorizontalScrollBarVisibilityProperty,ScrollBarVisibility.Disabled);
        scroll.SetValue(ScrollViewer.VerticalScrollBarVisibilityProperty,ScrollBarVisibility.Auto);scroll.SetValue(ScrollViewer.CanContentScrollProperty,true);
        scroll.AppendChild(new FrameworkElementFactory(typeof(ItemsPresenter)));border.AppendChild(scroll);
        menu.Template=new ControlTemplate(typeof(ContextMenu)){VisualTree=border};menu.ItemContainerStyle=PopupItemStyle;
        return menu;
    }

    private static readonly Style PopupItemStyle=CreatePopupItemStyle();
    private static Style CreatePopupItemStyle()
    {
        var item=new Style(typeof(MenuItem));item.Setters.Add(new Setter(Control.FocusVisualStyleProperty,null));
        item.Setters.Add(new Setter(Control.PaddingProperty,new Thickness(9,5,9,5)));
        item.Setters.Add(new Setter(Control.HorizontalContentAlignmentProperty,HorizontalAlignment.Stretch));
        var surface=new FrameworkElementFactory(typeof(Border),"ItemSurface");surface.SetValue(Border.CornerRadiusProperty,new CornerRadius(4));
        surface.SetValue(Border.BackgroundProperty,Brushes.Transparent);surface.SetValue(FrameworkElement.MinHeightProperty,28.0);
        surface.SetBinding(Border.PaddingProperty,new System.Windows.Data.Binding("Padding"){RelativeSource=System.Windows.Data.RelativeSource.TemplatedParent});
        var content=new FrameworkElementFactory(typeof(Grid));
        var title=new FrameworkElementFactory(typeof(TextBlock));title.SetBinding(TextBlock.TextProperty,new System.Windows.Data.Binding("Header"){RelativeSource=System.Windows.Data.RelativeSource.TemplatedParent});
        title.SetValue(TextBlock.TextTrimmingProperty,TextTrimming.CharacterEllipsis);title.SetValue(FrameworkElement.MarginProperty,new Thickness(0,0,24,0));
        title.SetValue(FrameworkElement.VerticalAlignmentProperty,VerticalAlignment.Center);content.AppendChild(title);
        var check=new FrameworkElementFactory(typeof(System.Windows.Shapes.Path),"Check");check.SetValue(System.Windows.Shapes.Path.DataProperty,Geometry.Parse("M 1 5 L 4 8 L 10 1"));
        check.SetValue(System.Windows.Shapes.Shape.StrokeProperty,ParityTheme.White(.9));check.SetValue(System.Windows.Shapes.Shape.StrokeThicknessProperty,1.5);
        check.SetValue(System.Windows.Shapes.Shape.StrokeStartLineCapProperty,PenLineCap.Round);check.SetValue(System.Windows.Shapes.Shape.StrokeEndLineCapProperty,PenLineCap.Round);
        check.SetValue(System.Windows.Shapes.Shape.StrokeLineJoinProperty,PenLineJoin.Round);check.SetValue(FrameworkElement.WidthProperty,12.0);check.SetValue(FrameworkElement.HeightProperty,10.0);
        check.SetValue(FrameworkElement.HorizontalAlignmentProperty,HorizontalAlignment.Right);check.SetValue(FrameworkElement.VerticalAlignmentProperty,VerticalAlignment.Center);
        check.SetValue(UIElement.VisibilityProperty,Visibility.Hidden);content.AppendChild(check);surface.AppendChild(content);
        var template=new ControlTemplate(typeof(MenuItem)){VisualTree=surface};
        var selected=new Trigger {Property=MenuItem.IsCheckedProperty,Value=true};selected.Setters.Add(new Setter(UIElement.VisibilityProperty,Visibility.Visible,"Check"));
        selected.Setters.Add(new Setter(Border.BackgroundProperty,ParityTheme.White(.035),"ItemSurface"));template.Triggers.Add(selected);
        var highlighted=new Trigger {Property=MenuItem.IsHighlightedProperty,Value=true};highlighted.Setters.Add(new Setter(Border.BackgroundProperty,ParityTheme.White(.10),"ItemSurface"));template.Triggers.Add(highlighted);
        var disabled=new Trigger {Property=UIElement.IsEnabledProperty,Value=false};disabled.Setters.Add(new Setter(UIElement.OpacityProperty,.4,"ItemSurface"));template.Triggers.Add(disabled);
        item.Setters.Add(new Setter(Control.TemplateProperty,template));return item;
    }

    public static FrameworkElement SectionTitle(string text,string? hint=null)
    {
        var row=new DockPanel();
        if(hint!=null) { var label=Label(hint,10,.18);DockPanel.SetDock(label,Dock.Right);row.Children.Add(label); }
        row.Children.Add(new TrackedLabel { Text=Localizer.Text(text).ToUpper(Localizer.Culture),Size=10,Tracking=1.05,Opacity=.34 });
        row.Margin=new Thickness(10,0,10,6);return row;
    }

    public static FrameworkElement Mark(string id,double size=20)
    {
        string asset=id=="codex"?"openai":id;
        var bitmap=new BitmapImage(new Uri($"pack://application:,,,/Assets/{asset}.png"));
        return new System.Windows.Shapes.Rectangle { Width=size,Height=size,Fill=ParityTheme.Brush(id=="codexisland"?Colors.White:ParityData.Colors[id]),OpacityMask=new ImageBrush(bitmap) {Stretch=Stretch.Uniform} };
    }
}

internal sealed class TrackedLabel : FrameworkElement
{
    public string Text="";public double Size=10,Tracking=1.05;
    protected override Size MeasureOverride(Size constraint) => new(WidthOfText(),Math.Ceiling(Size*1.2));
    private double WidthOfText() {
        double width=0;foreach(char c in Text)width+=Glyph(c).WidthIncludingTrailingWhitespace+Tracking;
        return Math.Max(0,width-Tracking);
    }
    protected override AutomationPeer OnCreateAutomationPeer()=>new TrackedLabelPeer(this);
    private FormattedText Glyph(char c)=>new(c.ToString(),Localizer.Culture,FlowDirection.LeftToRight,
        new Typeface(IslandTypography.TextFace,FontStyles.Normal,FontWeights.SemiBold,FontStretches.Normal),Size,Brushes.White,VisualTreeHelper.GetDpi(this).PixelsPerDip);
    protected override void OnRender(DrawingContext dc) {double x=0;foreach(char c in Text){var glyph=Glyph(c);dc.DrawText(glyph,new Point(x,0));x+=glyph.WidthIncludingTrailingWhitespace+Tracking;}}
}

internal sealed class IslandToggle : ToggleButton
{
    private static readonly DependencyProperty PositionProperty=DependencyProperty.Register("Position",typeof(double),typeof(IslandToggle),new FrameworkPropertyMetadata(0.0,FrameworkPropertyMetadataOptions.AffectsRender));
    public IslandToggle(string name,bool enabled,Action<bool> changed)
    {
        Width=30;Height=17;Cursor=Cursors.Hand;
        Template=new ControlTemplate(typeof(IslandToggle)) {VisualTree=new FrameworkElementFactory(typeof(Grid))};
        IsChecked=enabled;SetValue(PositionProperty,enabled?1.0:0.0);AutomationProperties.SetName(this,Localizer.Text(name));
        void Changed() {
            double target=IsChecked==true?1:0;
            BeginAnimation(PositionProperty,new SpringAnimation {From=(double)GetValue(PositionProperty),To=target,Response=.32,Damping=.72,Duration=TimeSpan.FromSeconds(SettingsControls.MotionOff?0:.55)});
            changed(IsChecked==true);
        }
        Checked+=(_,_)=>Changed();Unchecked+=(_,_)=>Changed();
        MouseEnter+=(_,_)=>InvalidateVisual();MouseLeave+=(_,_)=>InvalidateVisual();SettingsControls.Pressable(this,.94);
    }
    protected override void OnRender(DrawingContext dc)
    {
        double progress=Math.Clamp((double)GetValue(PositionProperty),0,1);
        dc.DrawRoundedRectangle(ParityTheme.White(.07*(1-progress)),new Pen(ParityTheme.White(IsMouseOver?.20:.13),1),new Rect(.5,.5,29,16),8,8);
        dc.DrawRoundedRectangle(ParityTheme.Brush(Color.FromRgb(0,71,171),.32*progress),null,new Rect(1,1,28,15),7.5,7.5);
        var center=new Point(8.5+13*progress,8.5);
        if(progress>.01) {
            for(int i=5;i>0;i--)dc.DrawEllipse(ParityTheme.Brush(Color.FromRgb(0,71,171),.025*progress),null,center,6.5+i,6.5+i);
        }
        byte r=(byte)(255*(1-progress)),g=(byte)(255*(1-progress)+71*progress),b=(byte)(255*(1-progress)+171*progress);
        dc.DrawEllipse(ParityTheme.Brush(Color.FromRgb(r,g,b),.5+.5*progress),null,center,6.5,6.5);
    }
}

internal sealed class TrackedLabelPeer : FrameworkElementAutomationPeer
{
    public TrackedLabelPeer(TrackedLabel owner):base(owner){}
    protected override string GetNameCore()=>((TrackedLabel)Owner).Text;
    protected override string GetClassNameCore()=>"SectionTitle";
    protected override AutomationControlType GetAutomationControlTypeCore()=>AutomationControlType.Text;
}

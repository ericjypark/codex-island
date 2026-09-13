using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using IslandPrototype;

internal static class SettingsPageTests
{
    [DllImport("user32.dll")]private static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")]private static extern bool GetWindowRect(IntPtr window,out NativeRect rect);
    [DllImport("dwmapi.dll")]private static extern int DwmFlush();
    [StructLayout(LayoutKind.Sequential)]private struct NativeRect {public int Left,Top,Right,Bottom;}
    internal static async Task Run(string output,Action<string,bool> check)
    {
        var appMarkup=System.Xml.Linq.XDocument.Load(Path.Combine(AppContext.BaseDirectory,"App-theme.xaml"));
        System.Xml.Linq.XNamespace presentation="http://schemas.microsoft.com/winfx/2006/xaml/presentation";
        var resources=new System.Xml.Linq.XElement(presentation+"ResourceDictionary",
            new System.Xml.Linq.XAttribute(System.Xml.Linq.XNamespace.Xmlns+"x","http://schemas.microsoft.com/winfx/2006/xaml"),
            appMarkup.Root!.Element(presentation+"Application.Resources")!.Elements());
        var appResources=(ResourceDictionary)System.Windows.Markup.XamlReader.Parse(resources.ToString());
        Application.Current.Resources.MergedDictionaries.Add(appResources);
        string root=Path.Combine(Path.GetTempPath(),"CodexIslandSettings-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
        var preferences=new PreferenceStore(Path.Combine(root,"preferences.json"));
        preferences.Update(new IslandPreferences {SettingsTab="providers",LeftProvider="codex",RightProvider="antigravity",Currency="USD"});
        var client=new Client();using var coordinator=new LiveUsageCoordinator(client);using var feed=new UsageFeed(coordinator);
        feed.Preferences=preferences.Value;feed.Select(preferences.Value.SelectedProviders);preferences.Changed+=(_,next)=>{feed.Preferences=next;feed.Select(next.SelectedProviders);};
        using var currency=new CurrencyStore(Path.Combine(root,"currency.json"));await feed.RefreshAsync(true);
        var settings=new PreviewSettings(preferences,currency,()=>{},()=>{},feed:feed) {Topmost=true};
        IEnumerable<Button> Buttons()=>Elements(settings).OfType<Button>();
        Button Button(string name)=>Buttons().First(b=>AutomationProperties.GetName(b)==name);
        string[] AccountIds()=>Elements(settings).OfType<StackPanel>().Select(AutomationProperties.GetAutomationId).Where(id=>id.StartsWith("ProviderAccount_")).ToArray();
        async Task Capture(string name)
        {
            Elements(settings).OfType<ScrollViewer>().First().ScrollToHome();settings.UpdateLayout();
            IntPtr handle=new WindowInteropHelper(settings).Handle;SetForegroundWindow(handle);await Task.Delay(350);Marshal.ThrowExceptionForHR(DwmFlush());
            GetWindowRect(handle,out var bounds);
            using var bitmap=new System.Drawing.Bitmap(bounds.Right-bounds.Left,bounds.Bottom-bounds.Top);
            using(var graphics=System.Drawing.Graphics.FromImage(bitmap))graphics.CopyFromScreen(bounds.Left,bounds.Top,0,0,bitmap.Size);
            bitmap.Save(Path.Combine(output,name+".png"));
            double scale=bitmap.Width/settings.ActualWidth;int titlePixels=0;
            for(int y=(int)(46*scale);y<78*scale;y++)for(int x=(int)(61*scale);x<260*scale;x++)if(bitmap.GetPixel(x,y).R>80)titlePixels++;
            check(name+": first presentation includes the brand text",titlePixels>100);
        }
        try {
            settings.Show();await Task.Delay(200);
            foreach(string name in new[]{"Close","Zoom"}) {
                var circle=(System.Windows.Shapes.Ellipse)Button(name).Content;
                var clip=System.Windows.Controls.Primitives.LayoutInformation.GetLayoutClip(circle);
                var drawn=circle.RenderedGeometry.GetRenderBounds(new Pen(Brushes.Black,circle.StrokeThickness));
                Console.WriteLine($"Caption {name}: drawn={drawn}; layoutClip={clip?.Bounds.ToString()??"none"}");
                check(name+": the complete circle fits without layout clipping",clip==null||clip.Bounds.Contains(drawn));
            }
            foreach(string name in new[]{"Close","Zoom"}) {
                var tip=new ToolTip {Content=Button(name).ToolTip,PlacementTarget=Button(name),Placement=System.Windows.Controls.Primitives.PlacementMode.Bottom,StaysOpen=true};
                try {
                    tip.IsOpen=true;await Task.Delay(650);Marshal.ThrowExceptionForHR(DwmFlush());
                    var point=tip.PointToScreen(new Point());var dpi=VisualTreeHelper.GetDpi(tip);
                    using var bitmap=new System.Drawing.Bitmap((int)Math.Ceiling(tip.ActualWidth*dpi.DpiScaleX),(int)Math.Ceiling(tip.ActualHeight*dpi.DpiScaleY));
                    using(var graphics=System.Drawing.Graphics.FromImage(bitmap))graphics.CopyFromScreen((int)point.X,(int)point.Y,0,0,bitmap.Size);
                    bitmap.Save(Path.Combine(output,"settings-tooltip-"+name.ToLowerInvariant()+".png"));
                    int dark=0,bright=0,total=0;
                    for(int y=3;y<bitmap.Height-3;y++)for(int x=3;x<bitmap.Width-3;x++) {
                        var pixel=bitmap.GetPixel(x,y);if(pixel.R<60&&pixel.G<60&&pixel.B<60)dark++;if(pixel.R>180&&pixel.G>180&&pixel.B>180)bright++;total++;
                    }
                    check(name+": shared app styling renders readable tooltip text on a dark surface",dark>total*.65&&bright>12);
                } finally {tip.IsOpen=false;}
            }
            check("Providers begins with selection and only the selected accounts",AccountIds().SequenceEqual(new[]{"ProviderAccount_codex","ProviderAccount_antigravity"})&&!Elements(settings).OfType<TextBlock>().Any(t=>t.Text is "Accounts" or "Live usage" or "Preview demo"));
            check("A healthy legacy account has no redundant action row",!Buttons().First(b=>AutomationProperties.GetAutomationId(b)=="ConnectAccount_codex").IsVisible&&!Buttons().First(b=>AutomationProperties.GetAutomationId(b)=="RefreshAccount_codex").IsVisible);
            var title=Elements(settings).OfType<TextBlock>().First(t=>t.Text=="On your island");
            var face=new Typeface(title.FontFamily,title.FontStyle,title.FontWeight,title.FontStretch);
            check("Settings resolves the bundled text font",face.TryGetGlyphTypeface(out var glyph)&&glyph.FamilyNames.Values.Any(name=>name=="Island Text"));
            await Capture("settings-providers-windows");
            settings.Width=440;settings.Height=560;await Capture("settings-providers-narrow-windows");
            check("Provider selectors fit the minimum window width",new[]{"Left provider","Right provider"}.All(name=>{var button=Button(name);var point=button.TranslatePoint(new Point(),settings);return point.X>=20&&point.X+button.ActualWidth<=settings.ActualWidth-20;}));
            var currencyPicker=Button("Display currency");var currencyBounds=currencyPicker.TranslatePoint(new Point(),settings);
            check("The currency control stays inside the narrow window",currencyBounds.X>=20&&currencyBounds.X+currencyPicker.ActualWidth<=settings.ActualWidth-20);
            settings.Width=480;settings.Height=720;
            preferences.Update(preferences.Value with {LeftProvider="claude",RightProvider="codex"});client.Status=UsageStatus.NeedsLogin;await feed.RefreshAsync(true);settings.RefreshProviderStatus();await Capture("settings-providers-login-windows");
            check("Selected accounts needing login expose their CLI sign-in buttons",new[]{"claude","codex"}.All(id=>Buttons().Any(b=>AutomationProperties.GetAutomationId(b)=="ConnectAccount_"+id&&b.IsVisible&&b.IsEnabled)));
            client.Status=UsageStatus.Ready;await feed.RefreshAsync(true);settings.RefreshProviderStatus();
            check("A successful account refresh removes the sign-in actions",new[]{"claude","codex"}.All(id=>!Buttons().First(b=>AutomationProperties.GetAutomationId(b)=="ConnectAccount_"+id).IsVisible));
            preferences.Update(preferences.Value with {SettingsTab="general"});await Capture("settings-general-windows");
            preferences.Update(preferences.Value with {SettingsTab="display"});await Capture("settings-display-windows");
        } finally {settings.Close();Directory.Delete(root,true);Application.Current.Resources.MergedDictionaries.Remove(appResources);}
    }
    private static IEnumerable<DependencyObject> Elements(DependencyObject root)
    {
        yield return root;for(int i=0;i<VisualTreeHelper.GetChildrenCount(root);i++)foreach(var child in Elements(VisualTreeHelper.GetChild(root,i)))yield return child;
    }
    private sealed class Client:IUsageClient
    {
        internal UsageStatus Status=UsageStatus.Ready;
        public Task<UsageResult> FetchAsync(string id,CancellationToken cancellation)=>Task.FromResult(new UsageResult(Status,
            Status==UsageStatus.Ready?[new("5h",35,DateTimeOffset.UtcNow.AddHours(2),"session"),new("week",20,DateTimeOffset.UtcNow.AddDays(3),"weekly")]:[],id=="codex"?"pro":id=="claude"?"Max":"AI Pro","settings-"+id));
    }
}

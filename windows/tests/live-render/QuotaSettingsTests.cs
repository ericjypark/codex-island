using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using IslandPrototype;

internal static class QuotaSettingsTests
{
    internal static async Task Run(UsageFeed feed,Action<string,bool> check,string output)
    {
        string root=Path.Combine(Path.GetTempPath(),"CodexIslandQuotaUI-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
        var previous=feed.Preferences;var preferences=new PreferenceStore(Path.Combine(root,"preferences.json"));
        preferences.Update(previous with {SettingsTab="providers",LeftProvider="grok",RightProvider="antigravity",QuotaSelections=new()});
        feed.Preferences=preferences.Value;preferences.Changed+=(_,next)=>feed.Preferences=next;
        using var currency=new CurrencyStore(Path.Combine(root,"currency.json"));
        var settings=new PreviewSettings(preferences,currency,()=>{},()=>{},feed:feed);
        try {
            settings.Show();await Task.Delay(200);
            IEnumerable<Button> Buttons()=>Descendants(settings).OfType<Button>();
            Button Find(string name)=>Buttons().First(b=>AutomationProperties.GetName(b)==name&&b.IsVisible);
            async Task Click(Button button){button.BringIntoView();button.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));await Task.Delay(150);}
            async Task Choose(string name,string value) {
                await Click(Find(name));
                var menu=PresentationSource.CurrentSources.Cast<PresentationSource>().SelectMany(s=>Descendants(s.RootVisual)).OfType<ContextMenu>().First(m=>m.IsOpen);
                var option=menu.Items.OfType<MenuItem>().First(i=>(string?)i.Header==value);
                option.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent));menu.IsOpen=false;await Task.Delay(150);
            }
            string[] Accounts()=>Descendants(settings).OfType<StackPanel>().Select(AutomationProperties.GetAutomationId).Where(id=>id.StartsWith("ProviderAccount_")).ToArray();
            check("Account rows follow the two selected slots and exclude unselected providers",Accounts().SequenceEqual(new[]{"ProviderAccount_grok","ProviderAccount_antigravity"}));
            var selection=Find("Left provider");var firstAccount=Descendants(settings).OfType<StackPanel>().First(p=>AutomationProperties.GetAutomationId(p)=="ProviderAccount_grok");
            check("Provider selection appears above account details",selection.TranslatePoint(new Point(),settings).Y<firstAccount.TranslatePoint(new Point(),settings).Y);
            check("Connected providers use compact account options and no sign-in button",new[]{"grok","antigravity"}.All(id=>!Buttons().First(b=>AutomationProperties.GetAutomationId(b)=="ConnectAccount_"+id).IsVisible));
            var disclosures=Buttons().Where(b=>AutomationProperties.GetName(b)=="Usage display").ToArray();
            check("Both connected providers offer usage display controls",disclosures.Length==2);
            await Click(disclosures.First(b=>AutomationProperties.GetAutomationId(b)=="QuotaDisclosure_antigravity"));
            check("Usage disclosure exposes its expanded state",AutomationProperties.GetHelpText(Find("Usage display"))=="Collapsed"&&AutomationProperties.GetHelpText(Buttons().First(b=>AutomationProperties.GetAutomationId(b)=="QuotaDisclosure_antigravity"))=="Expanded");
            check("Expanded Antigravity controls include group, order, and peek choices",new[]{"Model group","First metric","Second metric","Peek and alerts"}.All(name=>Buttons().Any(b=>b.IsVisible&&AutomationProperties.GetName(b)==name)));
            await Choose("First metric","week");
            string scope=feed.QuotaScope("antigravity");
            check("The first metric menu persists a swap without duplicating quotas",preferences.Value.QuotaSelections[scope].MetricIds!.SequenceEqual(new[]{"weekly","session"}));
            await Choose("Peek and alerts","5h");
            check("The peek menu updates the real usage feed primary",UsageFeed.Primary(feed.Provider("antigravity"))?.Label=="5h");
            await Choose("Second metric","None");
            check("Removing a metric updates the display and its alert primary",feed.Provider("antigravity").Limits.Length==1&&UsageFeed.Primary(feed.Provider("antigravity"))?.Label=="week");
            await Choose("Model group","Claude Models");
            check("Choosing another model group immediately uses its reported quota",feed.Provider("antigravity").Limits is [{Used:75}]);
            var reloaded=new PreferenceStore(Path.Combine(root,"preferences.json"));
            check("Model group choices survive a new preference store",reloaded.Value.QuotaSelections[scope].GroupId=="claude");
            await Click(Find("Use defaults"));
            check("Use defaults restores Gemini and the default two metrics",feed.Provider("antigravity").Limits is [{Label:"5h",Used:15},{Label:"week",Used:20}]);
            settings.UpdateLayout();
            var bitmap=new System.Windows.Media.Imaging.RenderTargetBitmap((int)settings.ActualWidth*2,(int)settings.ActualHeight*2,192,192,PixelFormats.Pbgra32);
            bitmap.Render(settings);var encoder=new System.Windows.Media.Imaging.PngBitmapEncoder();encoder.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(bitmap));
            using(var file=File.Create(Path.Combine(output,"connected-quota-settings-windows.png")))encoder.Save(file);
            await Choose("Left provider","Codex");
            await Choose("Right provider","None - use one provider");
            check("Choosing one provider removes both stale account rows",Accounts().SequenceEqual(new[]{"ProviderAccount_codex"}));
            check("Swap is disabled with one provider",!Find("Swap left and right").IsEnabled);
            check("Selected account keeps its CLI action available to the account menu",Buttons().Any(b=>AutomationProperties.GetAutomationId(b)=="ConnectAccount_codex"));
        } finally {settings.Close();feed.Preferences=previous;Directory.Delete(root,true);}
    }
    private static IEnumerable<DependencyObject> Descendants(DependencyObject? root)
    {
        if(root==null)yield break;
        yield return root;
        for(int i=0;i<VisualTreeHelper.GetChildrenCount(root);i++)foreach(var child in Descendants(VisualTreeHelper.GetChild(root,i)))yield return child;
    }
}

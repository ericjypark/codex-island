using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using IslandPrototype;

internal static class Program
{
    private static bool holdCapture;
    private static string? macQuota;
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr window,out RectNative rect);
    [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr window);
    [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr window,IntPtr dc);
    [DllImport("gdi32.dll",SetLastError=true)] private static extern bool BitBlt(IntPtr destination,int x,int y,int width,int height,IntPtr source,int sourceX,int sourceY,uint operation);
    [DllImport("dwmapi.dll")] private static extern int DwmFlush();
    [StructLayout(LayoutKind.Sequential)] private struct RectNative {public int Left,Top,Right,Bottom;}
    [STAThread] private static int Main(string[] args)
    {
        if(args.Contains("--software"))RenderOptions.ProcessRenderMode=System.Windows.Interop.RenderMode.SoftwareOnly;
        holdCapture=args.Contains("--hold-capture");
        int quotaIndex=Array.IndexOf(args,"--mac-quota");if(quotaIndex>=0&&quotaIndex+1<args.Length)macQuota=args[quotaIndex+1];
        var app=new Application();int code=0;
        app.Startup+=async(_,_)=>{try{await Run(args[0],args.Contains("--footer-only"),args.Contains("--settings-only"));}catch(Exception error){Console.Error.WriteLine(error);code=1;}finally{app.Shutdown();}};
        app.Run();return code;
    }
    private static async Task Run(string output,bool footerOnly=false,bool settingsOnly=false)
    {
        var results=new List<object>();
        void Check(string name,bool pass){results.Add(new {check=name,pass});Console.WriteLine((pass?"PASS: ":"FAIL: ")+name);if(!pass)throw new Exception(name);}
        if(settingsOnly){await SettingsPageTests.Run(output,Check);File.WriteAllText(Path.Combine(output,"settings-page-results.json"),JsonSerializer.Serialize(new {build=typeof(IslandVisual).Assembly.ManifestModule.ModuleVersionId,checks=results},new JsonSerializerOptions {WriteIndented=true}));return;}
        if(footerOnly){await FooterStatusUiTests.Run(output,Check);File.WriteAllText(Path.Combine(output,"footer-render-results.json"),JsonSerializer.Serialize(new {build=typeof(IslandVisual).Assembly.ManifestModule.ModuleVersionId,checks=results},new JsonSerializerOptions {WriteIndented=true}));return;}
        var client=new FixtureClient();var coordinator=new LiveUsageCoordinator(client);
        using var feed=new UsageFeed(coordinator);feed.Select(["claude","codex"]);
        var surface=new IslandVisual {Width=800,Height=226,Expanded=true,Page=0,PagePosition=0,ContentOpacity=1,LogoOpacity=0,PillOpacity=0,CounterProgress=1,SwapOpacity=1,
            Preferences=new IslandPreferences {LeftProvider="claude",RightProvider="codex"},Feed=feed};
        var window=new Window {Width=800,Height=226,Left=100,Top=150,WindowStyle=WindowStyle.None,AllowsTransparency=true,Background=Brushes.Transparent,ShowInTaskbar=false,Topmost=true,Content=surface,Title="CodexIsland live render test"};
        window.Show();
        async Task Capture(string name) {
            surface.InvalidateVisual();await Task.Delay(400);
            Marshal.ThrowExceptionForHR(DwmFlush());
            GetWindowRect(new System.Windows.Interop.WindowInteropHelper(window).Handle,out var rect);
            using var bitmap=new System.Drawing.Bitmap(rect.Right-rect.Left,rect.Bottom-rect.Top);
            using(var graphics=System.Drawing.Graphics.FromImage(bitmap)) {
                IntPtr source=GetDC(IntPtr.Zero),destination=graphics.GetHdc();
                try{if(!BitBlt(destination,0,0,bitmap.Width,bitmap.Height,source,rect.Left,rect.Top,0x40CC0020))throw new System.ComponentModel.Win32Exception();}
                finally{graphics.ReleaseHdc(destination);ReleaseDC(IntPtr.Zero,source);}
            }
            bitmap.Save(Path.Combine(output,name+".png"));
            int Lit(double x,double y,double width,double height) {
                int count=0;double scale=bitmap.Width/800.0;
                for(int row=(int)(y*scale);row<(y+height)*scale;row++)for(int col=(int)(x*scale);col<(x+width)*scale;col++) {
                    var pixel=bitmap.GetPixel(col,row);if(Math.Max(pixel.R,Math.Max(pixel.G,pixel.B))>40)count++;
                }
                return count;
            }
            bool logosVisible=Lit(24,9,20,20)>80&&(surface.Preferences.RightProvider==null||Lit(756,9,20,20)>80);
            if(holdCapture&&!logosVisible){Console.WriteLine("Missing capture pixels; external capture ready: "+name);await Task.Delay(30000);}
            Check(name+": selected provider logos remain visible",logosVisible);
        }
        try {
            await feed.RefreshAsync(true);await Capture("live-connected-windows");
            Check("Connected UI exposes only supplied quota values",surface.AccessibleDescription.Contains("5h 34%")&&surface.AccessibleDescription.Contains("week 0%")&&!surface.AccessibleDescription.Contains("Demo"));
            Check("Live header does not offer sample reset credits",surface.AccessibleTargets.All(t=>!t.Help.Contains("sample",StringComparison.OrdinalIgnoreCase)));
            client.Status=UsageStatus.Offline;await feed.RefreshAsync(true);await Capture("live-offline-windows");
            using(var before=new System.Drawing.Bitmap(Path.Combine(output,"live-connected-windows.png")))
            using(var after=new System.Drawing.Bitmap(Path.Combine(output,"live-offline-windows.png"))) {
                int changed=0;for(int y=0;y<76;y++)for(int x=0;x<before.Width;x++)if(before.GetPixel(x,y)!=after.GetPixel(x,y))changed++;
                Check("A refresh retains all unchanged header pixels",changed==0);
            }
            Check("Transient error keeps supplied values and exposes its status",surface.AccessibleDescription.Contains("34%")&&surface.AccessibleDescription.Contains("Check your connection"));
            client.Status=UsageStatus.NeedsLogin;await feed.RefreshAsync(true);await Capture("live-reauth-windows");
            Check("Re-login UI clears percentages and offers provider settings",!surface.AccessibleDescription.Contains("34%")&&surface.AccessibleDescription.Contains("Sign in again")&&surface.AccessibleTargets.Count(t=>t.Help.EndsWith("provider settings"))==2);
            client.Status=UsageStatus.Ready;client.Missing=true;await feed.RefreshAsync(true);surface.ChartStyle=3;await Capture("live-missing-windows");
            Check("Missing and zero quotas stay distinct in rendered accessibility",surface.AccessibleDescription.Contains("5h no reading")&&surface.AccessibleDescription.Contains("week 0%"));
            client.Status=UsageStatus.RateLimited;await feed.RefreshAsync(true);await Capture("live-ratelimited-windows");
            Check("Rate limit appears beside retained real zero",surface.AccessibleDescription.Contains("Rate limited")&&surface.AccessibleDescription.Contains("week 0%"));
            for(int page=1;page<=2;page++) {
                surface.Page=page;surface.PagePosition=page;surface.Height=page==2?277:226;window.Height=surface.Height;
                await Capture(page==1?"live-cost-windows":"live-overview-windows");
                Check(page==1?"Live cost exposes unavailable history":"Live overview exposes unavailable history",surface.AccessibleDescription.Contains("Usage history unavailable")&&!surface.AccessibleDescription.Contains("Demo"));
                Check(page==1?"Live cost offers no fixture export":"Live overview offers no fixture export",surface.AccessibleTargets.All(t=>!t.Help.Contains("usage card")));
            }
            surface.Preferences=surface.Preferences with {LeftProvider="grok",RightProvider="antigravity"};feed.Select(["grok","antigravity"]);
            surface.Page=0;surface.PagePosition=0;surface.Height=226;window.Height=226;await Capture("live-unavailable-providers-windows");
            Check("Unconnected Grok and Antigravity offer settings without invented usage",surface.AccessibleDescription.Contains("Not connected")&&!surface.AccessibleDescription.Contains('%')&&surface.AccessibleTargets.Count(t=>t.Help.EndsWith("provider settings"))==2);
            client.Connected["grok"]=new(UsageStatus.Ready,[new("week",42.5,DateTimeOffset.UtcNow.AddDays(5),"credits",Kind:1),new("month",25,DateTimeOffset.UtcNow.AddDays(15),"monthly",Kind:2)],"SuperGrok","grok-fixture");
            client.Connected["antigravity"]=new(UsageStatus.Ready,[new("week",20,DateTimeOffset.UtcNow.AddDays(5),"weekly","gemini","Gemini Models",1),new("5h",15,DateTimeOffset.UtcNow.AddHours(3),"session","gemini","Gemini Models",0),new("week",75,DateTimeOffset.UtcNow.AddDays(5),"weekly","claude","Claude Models",1)],"AI Pro","agy-fixture");
            await feed.RefreshAsync(true);await Capture("live-connected-grok-antigravity-windows");
            Check("Connected provider charts show the selected Gemini group",surface.AccessibleDescription.Contains("week 43%")&&surface.AccessibleDescription.Contains("5h 15%")&&!surface.AccessibleDescription.Contains("75%"));
            feed.Preferences=surface.Preferences with {QuotaSelections=new() {[feed.QuotaScope("antigravity")]=new("gemini",["weekly","session"],"weekly")}};
            surface.Preferences=feed.Preferences;await Capture("live-selected-metrics-windows");
            Check("Changing quota order also changes the explicit peek and alert primary",feed.Provider("antigravity").Limits[0].Label=="week"&&UsageFeed.Primary(feed.Provider("antigravity"))?.Used==20);
            await QuotaSettingsTests.Run(feed,Check,output);
            client.Connected["grok"]=new(UsageStatus.Ready,[new("Credits",null,null,"credits")],"Free","grok-fixture");
            feed.Preferences=surface.Preferences with {QuotaSelections=new() {[feed.QuotaScope("antigravity")]=new("missing",["missing"],"missing")}};surface.Preferences=feed.Preferences;
            await feed.RefreshAsync(true);await Capture("live-free-and-missing-metrics-windows");
            Check("Free plans and unavailable selections offer settings instead of zero charts",surface.AccessibleDescription.Contains("No active subscription")&&!surface.AccessibleDescription.Contains('%')&&surface.AccessibleTargets.Count(t=>t.Help.EndsWith("provider settings"))==2);
            string historyRoot=Path.Combine(Path.GetTempPath(),"CodexIslandLiveHistory-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(historyRoot);
            try {
                var stamp=DateTimeOffset.Now;
                string codexRoot=Path.Combine(historyRoot,".codex","sessions"),claudeRoot=Path.Combine(historyRoot,".claude","projects","fixture");Directory.CreateDirectory(codexRoot);Directory.CreateDirectory(claudeRoot);
                string Context(string model)=>JsonSerializer.Serialize(new{type="turn_context",payload=new{model}});
                string Codex(long input,long read,long output)=>JsonSerializer.Serialize(new{timestamp=stamp.ToString("O"),type="event_msg",payload=new{type="token_count",info=new{last_token_usage=new{input_tokens=input,cached_input_tokens=read,output_tokens=output}}}});
                File.WriteAllText(Path.Combine(codexRoot,"rollout-history-test.jsonl"),Context("gpt-5.4")+"\n"+Codex(3_000_000,2_000_000,10_000)+"\n"+Context("unknown-model")+"\n"+Codex(101,0,1)+"\n");
                File.WriteAllText(Path.Combine(claudeRoot,"history-test.jsonl"),JsonSerializer.Serialize(new{timestamp=stamp.ToString("O"),type="assistant",requestId="request-test",message=new{id="message-test",model="claude-sonnet-4-6",usage=new{input_tokens=400_000,output_tokens=20_000,cache_creation_input_tokens=50_000,cache_read_input_tokens=800_000}}})+"\n");
                string ledgerPath=Path.Combine(historyRoot,"history.sqlite3");
                HistoryCoordinator History()=>new(new LocalLogScanner(historyRoot,_=>null),new UsageLedger(ledgerPath),new ModelPricing(Path.Combine(historyRoot,"prices.json"),new OfflineCatalog()));
                using var historyFeed=new UsageFeed(new LiveUsageCoordinator(new FixtureClient()),History());historyFeed.Select(["claude","codex"]);await historyFeed.RefreshAsync(true);
                surface.Feed=historyFeed;surface.Preferences=surface.Preferences with{LeftProvider="claude",RightProvider="codex"};surface.Page=1;surface.PagePosition=1;surface.CostStyle=0;
                await Capture("live-history-cost-windows");
                Check("Live cost renders recorded API value and identifies partial pricing",surface.AccessibleDescription.Contains("plus unpriced usage")&&!surface.AccessibleDescription.Contains("unavailable")&&!surface.AccessibleDescription.Contains("Demo"));
                surface.CostStyle=2;surface.Preferences=surface.Preferences with{TokenMode="billable"};await Capture("live-history-billable-windows");
                Check("Live token view uses actual billable counts",surface.AccessibleDescription.Contains("1,010,102 tokens")&&surface.AccessibleDescription.Contains("420,000 tokens"));
                surface.CostStyle=1;await Capture("live-history-value-windows");
                surface.Preferences=surface.Preferences with{RightProvider=null};surface.CostStyle=0;await Capture("live-history-models-windows");
                Check("Live model rows have independent rolling five-hour and weekly totals",historyFeed.History("claude") is {Models:[[{Tokens:420000}],[{Tokens:420000}]]});
                surface.Preferences=surface.Preferences with{RightProvider="codex"};surface.Page=2;surface.PagePosition=2;surface.Height=277;window.Height=277;
                await Capture("live-history-overview-windows");
                Check("Live overview includes recorded history from every provider",surface.AccessibleDescription.Contains("4,280,102 tokens")&&surface.AccessibleTargets.Any(t=>t.Help=="Create your usage card"));
                surface.AccessibleTargets.First(t=>t.Help.StartsWith(stamp.LocalDateTime.ToString("MMM d")+": ")).Action();surface.DetailProgress=1;surface.Height=330;window.Height=330;
                await Capture("live-history-day-windows");
                Check("A live calendar day remains selectable with exact provider totals",surface.SelectedDay==stamp.LocalDateTime.Date&&surface.AccessibleDescription.Contains("4,280,102 tokens"));
                var snapshot=new UsageCardSnapshot(CardPeriod.LastThirtyDays,new(){"claude","codex"},DateTime.Now,historyFeed.Days,false);
                Check("Live card preserves exact totals and mixed priced/unpriced provenance",snapshot.TotalTokens==4_280_102&&snapshot.Providers.Single(p=>p.Id=="codex").UnpricedTokens==102&&snapshot.PartialPricing&&!snapshot.IsDemo);
                Check("Live card captions remove the demo label and retain the API-estimate qualifier",!snapshot.Caption(CardMetric.ApiValue).Contains("Demo")&&snapshot.Caption(CardMetric.ApiValue).Contains("not a bill")&&snapshot.Caption(CardMetric.ApiValue).Contains("Some tokens have no known price"));
                var bitmap=new UsageCardVisual(snapshot){Metric=CardMetric.ApiValue}.Bitmap();var encoder=new System.Windows.Media.Imaging.PngBitmapEncoder();encoder.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(bitmap));
                using(var stream=File.Create(Path.Combine(output,"live-history-card-windows.png")))encoder.Save(stream);
                Directory.Delete(codexRoot,true);Directory.Delete(claudeRoot,true);
                using var reopenedFeed=new UsageFeed(new LiveUsageCoordinator(new FixtureClient()),History());reopenedFeed.Select(["claude","codex"]);await reopenedFeed.RefreshAsync(true);surface.Feed=reopenedFeed;
                await Capture("live-history-retained-windows");
                Check("Rendered calendar and card totals survive deleted logs and a restarted history service",reopenedFeed.Days.Sum(d=>d.Total)==4_280_102&&surface.AccessibleDescription.Contains("4,280,102 tokens"));
            }finally{Directory.Delete(historyRoot,true);}
            await ResetCreditUiTests.Run(output,Check);
            await QuotaHistoryUiTests.Run(output,Check,macQuota);
            await FooterStatusUiTests.Run(output,Check);
            File.WriteAllText(Path.Combine(output,"live-render-results.json"),JsonSerializer.Serialize(new {build=typeof(IslandVisual).Assembly.ManifestModule.ModuleVersionId,fixtureResponses=true,checks=results},new JsonSerializerOptions {WriteIndented=true}));
        } finally {window.Close();}
    }
    private sealed class FixtureClient : IUsageClient
    {
        internal readonly Dictionary<string,UsageResult> Connected=new();
        internal UsageStatus Status=UsageStatus.Ready;
        internal bool Missing;
        public Task<UsageResult> FetchAsync(string provider,CancellationToken cancellation)=>Task.FromResult(Connected.GetValueOrDefault(provider)??new UsageResult(Status,
            Status==UsageStatus.Ready?[new("5h",Missing?null:34,DateTimeOffset.UtcNow.AddHours(2)),new("week",0,DateTimeOffset.UtcNow.AddDays(5))]:[],provider=="claude"?"max":"pro",provider));
    }
    private sealed class OfflineCatalog : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken cancellation)=>Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable));
    }
}

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using IslandPrototype;

internal static class Program
{
    private static readonly List<object> checks=new();
    private static int failures;
    [STAThread] private static int Main(string[] args)
    {
        CultureInfo.CurrentCulture=CultureInfo.GetCultureInfo("en-US");
        var app=new Application{ShutdownMode=ShutdownMode.OnExplicitShutdown};int exitCode=1;
        app.Startup+=async(_,_)=>{try{await Run(args[0],args[1],args[2]);exitCode=failures==0?0:1;}catch(Exception error){Console.Error.WriteLine(error);exitCode=1;}finally{app.Shutdown();}};
        app.Run();return exitCode;
    }
    private static void Check(string name,bool pass,object? actual=null,object? expected=null)
    {
        checks.Add(new{check=name,pass,actual,expected});
        if(!pass){failures++;Console.WriteLine("FAIL: "+name+" actual="+JsonSerializer.Serialize(actual)+" expected="+JsonSerializer.Serialize(expected));}
    }
    private static void Equal(string name,long actual,long expected)=>Check(name,actual==expected,actual,expected);
    private static void Close(string name,double actual,double expected)=>Check(name,Math.Abs(actual-expected)<1e-7,actual,expected);
    private static void TextEqual(string name,string actual,string expected)=>Check(name,actual==expected.Replace('–','-'),actual,expected.Replace('–','-'));
    private static async Task Run(string input,string profile,string output)
    {
        using var manifest=JsonDocument.Parse(File.ReadAllText(Path.Combine(input,"manifest.json")));
        using var reference=JsonDocument.Parse(File.ReadAllText(Path.Combine(input,"mac-reference.json")));
        var now=DateTimeOffset.UnixEpoch.AddSeconds(manifest.RootElement.GetProperty("nowUnix").GetDouble());
        var zone=TimeZoneInfo.FindSystemTimeZoneById(manifest.RootElement.GetProperty("timezone").GetString()!);
        var localNow=TimeZoneInfo.ConvertTime(now,zone).DateTime;
        string source=Path.Combine(input,"mac-usage-history.sqlite3"),database=Path.Combine(profile,"usage-history.sqlite3");
        foreach(var hash in manifest.RootElement.GetProperty("sha256").EnumerateObject()) {
            using var stream=File.OpenRead(Path.Combine(input,hash.Name));
            TextEqual(hash.Name+" copied without changes",Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant(),hash.Value.GetString()!);
        }
        long expectedRows=manifest.RootElement.GetProperty("eventTotals").EnumerateArray().Sum(row=>row[2].GetInt64());
        long expectedDays=manifest.RootElement.GetProperty("historicalTotals").EnumerateArray().Sum(row=>row[1].GetInt64());
        var ledger=new UsageLedger(database);
        var timer=Stopwatch.StartNew();var import=await Task.Run(()=>ledger.Import(source,now));double importMilliseconds=timer.Elapsed.TotalMilliseconds;
        Equal("All Mac event records imported",import.AddedRecords,expectedRows);
        Equal("All recovered daily totals imported",import.AddedDays,expectedDays);
        TextEqual("Source platform detected",import.SourcePlatform,"Mac");
        Check("New isolated profile needs no existing-data backup",import.BackupPath==null);
        string payload=File.ReadAllText(Path.Combine(input,"model-prices-payload.json"));
        HistoryCoordinator History()=>new(new EmptyScanner(),new UsageLedger(database),new ModelPricing(Path.Combine(profile,"prices.json"),new FrozenCatalog(payload)),()=>now,()=>zone);
        using var history=History();timer.Restart();await history.RefreshAsync(true);double refreshMilliseconds=timer.Elapsed.TotalMilliseconds;
        foreach(var provider in reference.RootElement.GetProperty("providers").EnumerateArray()) {
            string id=provider.GetProperty("id").GetString()!;var actual=history.State(id)!;
            Check(id+" history loaded without storage error",actual.Notice==null||actual.Notice=="Some tokens have no known API price.",actual.Notice);
            Check(id+" unpriced or recovered usage does not imply unreadable files",actual.LocalNotice==null,actual.LocalNotice);
            CompareTotal(id+" today",actual.Today,provider.GetProperty("today"));
            CompareTotal(id+" month",actual.Month,provider.GetProperty("month"));
            var days=provider.GetProperty("days").EnumerateArray().ToArray();
            Equal(id+" active calendar days",actual.Days.Count(d=>d.Tokens>0),days.Length);
            foreach(var expected in days) {
                string date=expected.GetProperty("date").GetString()!;
                var day=actual.Days.SingleOrDefault(d=>d.Date.ToString("yyyy-MM-dd")==date);
                Check(id+" calendar date "+date,day!=null);if(day==null)continue;
                Equal(id+" "+date+" tokens",day.Tokens,expected.GetProperty("tokens").GetInt64());
                Equal(id+" "+date+" billable",day.BillableTokens,expected.GetProperty("billableTokens").GetInt64());
                Equal(id+" "+date+" unpriced",day.UnpricedTokens,expected.GetProperty("unpricedTokens").GetInt64());
                Equal(id+" "+date+" recovered",day.RecoveredTokens,expected.GetProperty("recoveredTokens").GetInt64());
                Close(id+" "+date+" API value",day.Dollars,expected.GetProperty("dollars").GetDouble());
            }
            for(int window=0;window<2;window++) {
                var expected=provider.GetProperty("models")[window].EnumerateArray().ToArray();
                Equal(id+" model rows "+window,actual.Models[window].Length,expected.Length);
                for(int row=0;row<Math.Min(expected.Length,actual.Models[window].Length);row++) {
                    string label=id+" model "+window+"/"+row;var model=actual.Models[window][row];
                    TextEqual(label,model.Model,expected[row].GetProperty("model").GetString()!);
                    Equal(label+" tokens",model.Tokens,expected[row].GetProperty("tokens").GetInt64());
                    Close(label+" dollars",model.Dollars,expected[row].GetProperty("dollars").GetDouble());
                    Close(label+" token share",model.TokenShare,expected[row].GetProperty("tokenShare").GetDouble());
                    Close(label+" dollar share",model.DollarShare,expected[row].GetProperty("dollarShare").GetDouble());
                }
            }
        }
        var all=ParityData.Providers.Select(p=>p.Id).ToHashSet();var cardResults=new List<object>();
        foreach(var expected in reference.RootElement.GetProperty("cards").EnumerateArray()) {
            string name=expected.GetProperty("period").GetString()!;var period=Enum.Parse<CardPeriod>(name,true);
            var card=new UsageCardSnapshot(period,all,localNow,history.Days,false);
            Equal(name+" card tokens",card.TotalTokens,expected.GetProperty("tokens").GetInt64());
            Equal(name+" card recovered tokens",card.RecoveredTokens,expected.GetProperty("recoveredTokens").GetInt64());
            Equal(name+" active days",card.ActiveDays,expected.GetProperty("activeDays").GetInt64());
            Equal(name+" calendar span",card.Days.Length,expected.GetProperty("dayCount").GetInt64());
            Close(name+" API value",card.TotalDollars,expected.GetProperty("dollars").GetDouble());
            TextEqual(name+" dates",card.DateLabel,expected.GetProperty("dateLabel").GetString()!);
            TextEqual(name+" token tier",card.Tier(CardMetric.Tokens).ToString(),expected.GetProperty("tokenTier").GetString()!);
            TextEqual(name+" value tier",card.Tier(CardMetric.ApiValue).ToString(),expected.GetProperty("valueTier").GetString()!);
            TextEqual(name+" token caption",card.Caption(CardMetric.Tokens),expected.GetProperty("captionTokens").GetString()!);
            TextEqual(name+" value caption",card.Caption(CardMetric.ApiValue),expected.GetProperty("captionValue").GetString()!);
            foreach(var expectedProvider in expected.GetProperty("providers").EnumerateArray()) {
                string id=expectedProvider.GetProperty("id").GetString()!;var provider=card.Providers.Single(p=>p.Id==id);
                Equal(name+" "+id+" tokens",provider.Tokens,expectedProvider.GetProperty("tokens").GetInt64());
                Equal(name+" "+id+" unpriced",provider.UnpricedTokens,expectedProvider.GetProperty("unpricedTokens").GetInt64());
                Close(name+" "+id+" API value",provider.Dollars,expectedProvider.GetProperty("dollars").GetDouble());
            }
            foreach(var metric in Enum.GetValues<CardMetric>())SaveCard(output,name,card,CardFormat.Feed,metric);
            cardResults.Add(new{period=name,tokens=card.TotalTokens,dollars=card.TotalDollars,recovered=card.RecoveredTokens});
        }
        var allTime=new UsageCardSnapshot(CardPeriod.AllTime,all,localNow,history.Days,false);
        SaveCard(output,"allTime",allTime,CardFormat.Square,CardMetric.ApiValue);
        SaveCard(output,"allTime",allTime,CardFormat.Story,CardMetric.Tokens);
        var repeat=await Task.Run(()=>ledger.Import(source,now));
        Equal("Repeat import adds no duplicate events",repeat.AddedRecords,0);Equal("Repeat import adds no duplicate recovered days",repeat.AddedDays,0);
        Check("Repeat import preserves a restorable backup",repeat.BackupPath!=null&&File.Exists(repeat.BackupPath));
        if(repeat.BackupPath!=null) {
            var restore=new UsageLedger(Path.Combine(profile,"restored.sqlite3"));var restored=restore.Import(repeat.BackupPath,now);
            Equal("Windows backup restores every record",restored.AddedRecords,expectedRows);Equal("Windows backup restores recovered days",restored.AddedDays,expectedDays);
        }
        string moved=source+".not-needed";File.Move(source,moved);
        try {
            using var reopened=History();await reopened.RefreshAsync(true);
            var resumed=new UsageCardSnapshot(CardPeriod.AllTime,all,localNow,reopened.Days,false);
            Equal("Restart with no original logs or imported source preserves all tokens",resumed.TotalTokens,allTime.TotalTokens);
            Close("Restart preserves API value",resumed.TotalDollars,allTime.TotalDollars);
            Equal("Restart preserves recovered totals",resumed.RecoveredTokens,allTime.RecoveredTokens);
            await CapturePanels(output,History(),history.Days);
        }finally{File.Move(moved,source);}
        await ImportBoundaryTests.Run(profile,(name,pass)=>Check(name,pass));
        Check("Portable database snapshot saved for the interactive preview",ledger.CopyDatabase(Path.Combine(profile,"preview-history.sqlite3")));
        File.WriteAllText(Path.Combine(output,"windows-history-results.json"),JsonSerializer.Serialize(new{build=typeof(UsageLedger).Assembly.ManifestModule.ModuleVersionId,profile,sourceSha256=manifest.RootElement.GetProperty("sha256").Clone(),now,timezone=zone.Id,importMilliseconds,refreshMilliseconds,totalChecks=checks.Count,failures,cards=cardResults,checks},new JsonSerializerOptions{WriteIndented=true}));
        Console.WriteLine($"Mac history verification: {checks.Count-failures}/{checks.Count} checks passed; {expectedRows:N0} events and {expectedDays} recovered days. Profile: {profile}");
    }
    private static void CompareTotal(string label,HistoryTotal actual,JsonElement expected)
    {
        Equal(label+" tokens",actual.Tokens,expected.GetProperty("tokens").GetInt64());
        Equal(label+" billable",actual.BillableTokens,expected.GetProperty("billableTokens").GetInt64());
        Close(label+" value",actual.Dollars,expected.GetProperty("dollars").GetDouble());
        var series=expected.GetProperty("series").EnumerateArray().Select(p=>p.GetDouble()).ToArray();Equal(label+" chart points",actual.Series.Length,series.Length);
        for(int i=0;i<Math.Min(series.Length,actual.Series.Length);i++)Close(label+" chart point "+i,actual.Series[i],series[i]);
    }
    private static void SaveCard(string output,string name,UsageCardSnapshot card,CardFormat format,CardMetric metric)
    {
        var visual=new UsageCardVisual(card){Format=format,Metric=metric};var bitmap=visual.Bitmap();
        var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using(var stream=File.Create(Path.Combine(output,name+"-"+format+"-"+metric+".png")))encoder.Save(stream);
        Check(name+" "+format+" "+metric+" native export dimensions",bitmap.PixelWidth==1080&&bitmap.PixelHeight==(format==CardFormat.Feed?1350:format==CardFormat.Square?1080:1920));
    }
    private static async Task CapturePanels(string output,HistoryCoordinator history,DemoDay[] days)
    {
        using var feed=new UsageFeed(new LiveUsageCoordinator(new NoAccounts()),history);feed.Select(["claude","codex"]);await feed.RefreshAsync(true);
        var surface=new IslandVisual{Width=800,Height=226,Expanded=true,Page=1,PagePosition=1,ContentOpacity=1,LogoOpacity=0,PillOpacity=0,CounterProgress=1,SwapOpacity=1,Preferences=new(){LeftProvider="claude",RightProvider="codex"},Feed=feed};
        var window=new Window{Width=800,Height=226,Left=100,Top=150,WindowStyle=WindowStyle.None,AllowsTransparency=true,Background=Brushes.Transparent,ShowInTaskbar=false,Topmost=true,Content=surface,Title="CodexIsland imported Mac history check"};
        window.Show();
        async Task Capture(string name) {
            surface.InvalidateVisual();await Task.Delay(400);Marshal.ThrowExceptionForHR(DwmFlush());
            if(!GetWindowRect(new System.Windows.Interop.WindowInteropHelper(window).Handle,out var rect))throw new IOException("Window bounds unavailable.");
            using var bitmap=new System.Drawing.Bitmap(rect.Right-rect.Left,rect.Bottom-rect.Top);
            using(var graphics=System.Drawing.Graphics.FromImage(bitmap)) {
                IntPtr desktop=GetDC(IntPtr.Zero),destination=graphics.GetHdc();
                try{if(!BitBlt(destination,0,0,bitmap.Width,bitmap.Height,desktop,rect.Left,rect.Top,0x40CC0020))throw new System.ComponentModel.Win32Exception();}
                finally{graphics.ReleaseHdc(destination);ReleaseDC(IntPtr.Zero,desktop);}
            }
            bitmap.Save(Path.Combine(output,name+".png"));
            Check(name+" uses imported history",!surface.AccessibleDescription.Contains("Demo")&&!surface.AccessibleDescription.Contains("Usage history unavailable"),surface.AccessibleDescription);
        }
        try {
            foreach(int style in new[]{0,1,2,3}){surface.CostStyle=style;await Capture("mac-history-cost-"+style);}
            surface.CostStyle=0;surface.Preferences=surface.Preferences with{RightProvider=null};await Capture("mac-history-claude-models");
            surface.Preferences=surface.Preferences with{LeftProvider="codex"};await Capture("mac-history-codex-models");
            surface.Preferences=surface.Preferences with{LeftProvider="claude",RightProvider="codex"};surface.Page=2;surface.PagePosition=2;surface.Height=277;window.Height=277;await Capture("mac-history-overview");
            var recovered=days.First(d=>d.Date.Year==DateTime.Today.Year&&(d.RecoveredTokens?.Values.Sum()??0)>0);
            surface.AccessibleTargets.First(t=>t.Help.StartsWith(recovered.Date.ToString("MMM d")+": ")).Action();surface.DetailProgress=1;surface.Height=335;window.Height=335;await Capture("mac-history-recovered-day");
            Equal("Recovered original date selected in native calendar",surface.SelectedDay?.Ticks??0,recovered.Date.Ticks);
            Check("Recovered day shows exact recorded tokens",surface.AccessibleDescription.Contains(recovered.Total.ToString("N0")),surface.AccessibleDescription,recovered.Total);
        }finally{window.Close();}
    }
    private sealed class EmptyScanner : ILocalLogScanner {public HistoryScan Scan(string source,DateTimeOffset now,CancellationToken cancellation)=>new([]);}
    private sealed class NoAccounts : IUsageClient {public Task<UsageResult> FetchAsync(string provider,CancellationToken cancellation)=>Task.FromResult(new UsageResult(UsageStatus.NotConnected,[]));}
    private sealed class FrozenCatalog(string payload) : HttpMessageHandler {protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken cancellation)=>Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK){Content=new StringContent(payload)});}
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr window,out RectNative rect);
    [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr window);
    [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr window,IntPtr dc);
    [DllImport("gdi32.dll",SetLastError=true)] private static extern bool BitBlt(IntPtr destination,int x,int y,int width,int height,IntPtr source,int sourceX,int sourceY,uint operation);
    [DllImport("dwmapi.dll")] private static extern int DwmFlush();
    [StructLayout(LayoutKind.Sequential)] private struct RectNative {public int Left,Top,Right,Bottom;}
}

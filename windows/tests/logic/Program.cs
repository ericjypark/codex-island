using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using IslandPrototype;

internal static class Program
{
    private static int checks;
    [STAThread] private static int Main(string[] args)
    {
        _=new Application();Localizer.Language="en";
        try {if(args.Contains("--codex-live"))return CodexAccountTests.ReadLive().GetAwaiter().GetResult();Run().GetAwaiter().GetResult();Console.WriteLine($"PASS: {checks} logic checks");return 0;}
        catch(Exception error){Console.Error.WriteLine(error);return 1;}
    }
    private static void Check(string name,bool pass){if(!pass)throw new Exception(name);checks++;Console.WriteLine("PASS: "+name);}
    private static async Task Run()
    {
        CheckLiveModePreferences();
        await AppUpdateTests.Run(Check);
        await LiveUsageTests.Run(Check);
        await FooterStatusTests.Run(Check);
        await CodexAccountTests.Run(Check);
        await QuotaHistoryTests.Run(Check);
        await WakeRecoveryTests.Run(Check);
        AccountSetupTests.Run(Check);
        await ConnectedProviderTests.Run(Check);
        await HistoryTests.Run(Check);
        var gesture=new PageScrollGesture();
        Check("A complete wheel notch requests one adjacent page",gesture.Push(-120,false,0)==1);
        gesture.Reset();
        Check("Small wheel packets accumulate into one deliberate page change",Enumerable.Range(0,8).Select(i=>gesture.Push(-15,false,i*16)).Sum()==1);
        Check("Momentum packets cannot skip another page in the same gesture",Enumerable.Range(8,24).All(i=>gesture.Push(-15,false,i*16)==0));
        Check("A new gesture after a quiet interval can advance again",gesture.Push(-120,false,1000)==1);
        Check("Reversing direction during a transition remains responsive",gesture.Push(120,false,1016)==-1);
        gesture.Reset();Check("Horizontal Windows scrolling moves through adjacent pages",Enumerable.Range(0,8).Select(i=>gesture.Push(15,true,i*16)).Sum()==1);
        gesture.Reset();Check("Unrelated small movements do not accumulate across separate gestures",Enumerable.Range(0,8).All(i=>gesture.Push(15,true,i*250)==0));
        CheckAlerts();
        var screen=new System.Drawing.Rectangle(0,0,3840,2160);
        Check("A borderless client covering the target display is full screen",FullscreenGeometry.CoversMonitor(screen,screen));
        Check("A maximized window with a caption is not full screen",!FullscreenGeometry.CoversMonitor(new(0,60,3840,2060),screen));
        Check("Full screen on another display does not suppress this display",!FullscreenGeometry.CoversMonitor(new(-2560,0,2560,1440),screen));
        Check("A target display with negative coordinates is supported",FullscreenGeometry.CoversMonitor(new(-2560,-1440,2560,1440),new(-2560,-1440,2560,1440)));
        Check("A spanning full-screen client covers each included display",FullscreenGeometry.CoversMonitor(new(-2560,0,6400,2160),screen));
        Check("An empty client cannot be full screen",!FullscreenGeometry.CoversMonitor(new(0,0,0,0),screen));
        string directory=Path.Combine(Path.GetTempPath(),"CodexIslandTests-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(directory);
        try {
            string path=Path.Combine(directory,"preferences.json");
            var preferences=new PreferenceStore(path);
            Check("Selecting the other occupied provider swaps slots",preferences.Value.SelectProvider("antigravity",0) is {LeftProvider:"antigravity",RightProvider:"codex"});
            Check("Removing the left provider cannot produce an empty island",preferences.Value.SelectProvider(null,0).LeftProvider=="codex");
            Check("Removing the right provider enables single-provider mode",preferences.Value.SelectProvider(null,1).SelectedProviders.Length==1);
            var normalized=(preferences.Value with {WarningPercent=99,CriticalPercent=10,RefreshSeconds=30,LeftProvider="unknown"}).Normalize();
            Check("Thresholds remain ordered and within limits",normalized.WarningPercent==98&&normalized.CriticalPercent==99);
            Check("Refresh never falls below the five-minute provider minimum",normalized.RefreshSeconds==300);
            Check("Unknown provider falls back to a supported provider",normalized.LeftProvider=="claude");
            Check("Settings save successfully",preferences.Update(preferences.Value with {Remaining=true,TokenMode="billable",TargetDisplay="disconnected-monitor"}));
            var reloaded=new PreferenceStore(path);
            Check("Settings survive a new process instance",reloaded.Value.Remaining&&reloaded.Value.TokenMode=="billable"&&reloaded.Value.TargetDisplay=="disconnected-monitor");
            File.WriteAllText(path,"{unreadable");
            var broken=new PreferenceStore(path);
            Check("Malformed settings are preserved on load",broken.Error!=null&&File.ReadAllText(path)=="{unreadable");
            broken.Update(broken.Value with {Remaining=true});
            Check("Malformed settings are backed up before replacement",Directory.GetFiles(directory,"preferences.json.recovery-*").Length==1);
            Check("Countdown retains seconds below one minute",ParityData.Duration(42)=="42s");
            Check("Whole days omit a zero-hour suffix",ParityData.Duration(86400*2)=="2d");
            Check("Week countdown includes its remaining hours",ParityData.Duration(86400*6+3600*23)=="6d 23h");
            var central=TimeZoneInfo.FindSystemTimeZoneById("Central Standard Time");
            Check("Spring DST countdown follows local midnight",ParityData.TodayResetIn(new DateTimeOffset(2026,3,8,0,30,0,TimeSpan.FromHours(-6)),central)=="22h");
            Check("Fall DST countdown follows local midnight",ParityData.TodayResetIn(new DateTimeOffset(2026,11,1,0,30,0,TimeSpan.FromHours(-5)),central)=="1d");
            Check("Month countdown is at least one day at month end",ParityData.MonthResetIn(new DateTime(2026,2,28))=="1d");
            var all=ParityData.Providers.Select(p=>p.Id).ToHashSet();
            var week=new UsageCardSnapshot(CardPeriod.LastSevenDays,all,new DateTime(2027,1,3));
            Check("Last 7 days crosses a year boundary by local date",week.Start==new DateTime(2026,12,28)&&week.End==new DateTime(2027,1,3)&&week.Days.Length==7);
            var month=new UsageCardSnapshot(CardPeriod.LastThirtyDays,all,new DateTime(2027,1,3));
            Check("Last 30 days includes exactly 30 dates",month.Days.Length==30&&month.Start==new DateTime(2026,12,5));
            var quarter=new UsageCardSnapshot(CardPeriod.LastThreeMonths,all,new DateTime(2028,5,30));
            Check("Three months respects leap-year calendar arithmetic",quarter.Start==new DateTime(2028,2,29));
            var empty=new UsageCardSnapshot(CardPeriod.LastSevenDays,new(),ParityData.FixtureDate);
            Check("Removing every provider produces an empty card",empty.TotalTokens==0&&empty.TotalDollars==0&&!empty.HasPricedUsage);
            var demo=new UsageCardSnapshot(CardPeriod.LastSevenDays,all,ParityData.FixtureDate);
            Check("Card totals equal included daily records",demo.TotalTokens==demo.Days.Sum(d=>d.Total)&&Math.Abs(demo.TotalDollars-demo.Days.Sum(d=>d.Dollars.Values.Sum()))<.00001);
            Check("Cumulative boundaries end at provider totals",demo.Providers.All(p=>Math.Abs(demo.Cumulative(p.Id,CardMetric.ApiValue)[^1]-p.Dollars)<.00001));
            Check("Share captions keep demo and billing provenance",demo.Caption(CardMetric.ApiValue).StartsWith("Demo:")&&demo.Caption(CardMetric.ApiValue).Contains("not a bill"));
            Check("Dollar formatting never rounds into an unearned milestone",UsageCardSnapshot.Money(999.999)=="$999.99"&&UsageCardSnapshot.Money(99.999)=="$99.99");
            Check("Sub-cent and invalid amounts stay bounded",UsageCardSnapshot.Money(.0001)=="<$0.01"&&UsageCardSnapshot.Money(double.NaN)=="$0.00");
            var count=UsageCardSnapshot.CompactTokens(99_999_999);
            Check("Token labels never round into an unearned tier",count.Value=="99.9"&&count.Unit=="M");
            string cachePath=Path.Combine(directory,"rates.json");
            var handler=new RatesHandler();using var currency=new CurrencyStore(cachePath,handler) {Selection="KRW"};
            Check("Missing exchange rate retains USD currency and symbol",currency.DisplayCurrency=="USD"&&currency.Symbol=="$");
            await currency.RefreshAsync();
            Check("Valid rates enable selected currency",currency.DisplayCurrency=="KRW"&&currency.WholeUnits&&currency.Rate==1300);
            Check("Currency conversion and whole-unit formatting agree",currency.Convert(2)==2600&&currency.Format(2)=="₩2,600");
            await currency.RefreshAsync();Check("Fresh rates are cached for 24 hours",handler.Calls==1);
            handler.Fail=true;await currency.RefreshAsync(true);
            Check("Offline refresh retains the last valid rates",currency.Error!=null&&currency.DisplayCurrency=="KRW"&&currency.Rate==1300);
            using var cached=new CurrencyStore(cachePath,new RatesHandler {Fail=true}) {Selection="EUR"};
            Check("Rates reload after app restart",cached.DisplayCurrency=="EUR"&&cached.Rate==.9);
            var invalid=new RatesHandler {Invalid=true};using var invalidCurrency=new CurrencyStore(Path.Combine(directory,"invalid-rates.json"),invalid) {Selection="KRW"};await invalidCurrency.RefreshAsync();
            Check("Invalid API rates do not relabel USD amounts",invalidCurrency.DisplayCurrency=="USD"&&invalidCurrency.Error!=null);
            Check("Failed rate responses do not replace the disk cache",!File.Exists(Path.Combine(directory,"invalid-rates.json")));
        } finally {Directory.Delete(directory,true);}
    }
    private static void CheckLiveModePreferences()
    {
        string directory=Path.Combine(Path.GetTempPath(),"CodexIslandDataMode-"+Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        try {
            string path=Path.Combine(directory,"preferences.json");
            var first=new PreferenceStore(path);
            Check("A new profile starts with live accounts",first.Value.LiveMode);
            Check("Opening Settings can save the initial live profile",first.Update(first.Value with {SettingsTab="general",Page=2}));
            var restarted=new PreferenceStore(path);
            Check("Opening Settings and restarting never switches live accounts to demo",restarted.Value.LiveMode&&restarted.Value.Page==2);
            string legacy="{\"SchemaVersion\":1,\"LiveMode\":false,\"Currency\":\"KRW\",\"Remaining\":true,\"Page\":2}";
            File.WriteAllText(path,legacy);
            var migrated=new PreferenceStore(path);
            Check("Legacy implicit demo settings recover to live accounts",migrated.Value.LiveMode&&migrated.Value.SchemaVersion==2);
            Check("Recovering the data mode retains display preferences",migrated.Value.Currency=="KRW"&&migrated.Value.Remaining&&migrated.Value.Page==2);
            Check("Reading legacy preferences preserves the original file",File.ReadAllText(path)==legacy);
            Check("An explicit new demo selection saves successfully",migrated.Update(migrated.Value with {LiveMode=false}));
            Check("An explicit demo selection survives a restart",!new PreferenceStore(path).Value.LiveMode);
            var demo=new PreferenceStore(path);
            Check("Switching back to live accounts persists",demo.Update(demo.Value with {LiveMode=true})&&new PreferenceStore(path).Value.LiveMode);
            File.WriteAllText(path,"{broken");
            var damaged=new PreferenceStore(path);
            Check("Unreadable settings cannot silently enable demo data",damaged.Error!=null&&damaged.Value.LiveMode&&File.ReadAllText(path)=="{broken");
        } finally {Directory.Delete(directory,true);}
    }

    private static void CheckAlerts()
    {
        var reset=new DateTimeOffset(2026,9,12,12,0,0,TimeSpan.Zero);
        var low=new AlertWindow("codex",true,40,reset);
        var warning=low with {UsedPercent=85};
        var critical=low with {UsedPercent=96};
        var engine=new AlertEngine();
        AlertPulse? Send(params AlertWindow[] inputs)=>engine.Update(inputs,true,80,95,true,false);
        Check("Startup severity is immediate but pre-fetch data cannot form crossing memory",engine.Update(new[]{critical},true,80,95,false,false)==null&&engine.Severity==AlertSeverity.Critical&&engine.CrossingCount==0);
        Check("First completed fetch at high usage warms up without a pulse",Send(critical)==null&&engine.CrossingCount==2);
        Check("Identical readings cannot repeat a pulse",Send(critical)==null);
        Send(low);
        Check("Falling below and recrossing in the same reset cycle stays silent",Send(critical)==null);
        Check("A new reset cycle permits a fresh pulse",Send(critical with {ResetAt=reset.AddHours(5)}) is {Severity:AlertSeverity.Critical,Lines.Count:1}&&engine.CrossingCount==2);
        Check("Missing reset keeps severity and prior cycle memory without pulsing",Send(critical with {ResetAt=null})==null&&engine.Severity==AlertSeverity.Critical&&engine.CrossingCount==2);
        Check("Unknown readings are distinct from zero and clear severity",Send(low with {UsedPercent=null})==null&&engine.Severity==AlertSeverity.None);
        Check("Non-finite readings never become a threshold crossing",Send(low with {UsedPercent=double.NaN},low with {Provider="claude",UsedPercent=double.PositiveInfinity})==null&&engine.Severity==AlertSeverity.None);
        engine=new AlertEngine();Send(low);
        Check("Warning crossing produces a provider-specific pulse",Send(warning) is {Severity:AlertSeverity.Warning,Lines.Count:1} w&&w.Lines[0].Provider=="codex"&&w.Lines[0].Percent==85);
        Check("Critical escalation produces a second pulse within the same cycle",Send(critical) is {Severity:AlertSeverity.Critical,Lines.Count:1});
        Check("Hidden providers neither tint nor pulse",Send(critical with {Provider="claude",Visible=false})==null&&engine.Severity==AlertSeverity.None);
        Send(low with {Visible=false,ResetAt=reset.AddHours(5)});
        Check("Reset changes prune even while a provider is hidden",engine.CrossingCount==0);
        Check("Revealing a newly crossed provider can pulse after warmup",Send(warning with {ResetAt=reset.AddHours(5)}) is {Severity:AlertSeverity.Warning});
        Check("Disabling clears tint and crossing memory",engine.Update(new[]{critical},false,80,95,true,false)==null&&engine.Severity==AlertSeverity.None&&engine.CrossingCount==0);
        Check("Re-enabling high usage warms up without retroactive notification",Send(critical)==null&&engine.Severity==AlertSeverity.Critical);
        Check("Invalid threshold order disables severity and resets warmup",engine.Update(new[]{critical},true,95,80,true,false)==null&&engine.Severity==AlertSeverity.None&&engine.CrossingCount==0);
        Send(low);
        Check("Percent rounding matches Swift at the half-percent boundary",Send(low with {UsedPercent=94.5}) is {Severity:AlertSeverity.Critical} rounded&&rounded.Lines[0].Percent==95);
        engine=new AlertEngine();Send(low);
        Check("Simultaneous crossings coalesce into one pulse with maximum severity",Send(warning,critical with {Provider="claude"}) is {Severity:AlertSeverity.Critical,Lines.Count:2});
        engine=new AlertEngine();Send(low);
        Check("Demo updates show severity but suppress notifications",engine.Update(new[]{critical},true,80,95,true,true)==null&&engine.Severity==AlertSeverity.Critical&&engine.CrossingCount==2);
        Check("Suppressed demo crossings do not leak as later notifications",Send(critical)==null);
        engine=new AlertEngine();
        var saved=critical with {Provider="claude",FromHistory=true};
        Check("A saved high reading stays tinted without crossing memory when another provider refreshes",Send(low,saved)==null&&engine.CrossingCount==0&&engine.ProviderSeverities["claude"]==AlertSeverity.Critical);
        Check("An offline saved provider does not suppress another provider's fresh crossing",Send(warning,saved) is {Lines.Count:1} fresh&&fresh.Lines[0].Provider=="codex"&&engine.CrossingCount==1);
        Check("The first live reading of a restored provider baselines its thresholds silently",Send(warning,saved with {FromHistory=false})==null&&engine.CrossingCount==3);
        Check("A restored provider can alert in a later live reset cycle",Send(warning,saved with {FromHistory=false,ResetAt=reset.AddHours(5)}) is {Lines.Count:1} later&&later.Lines[0].Provider=="claude");
        Check("A saved reset boundary cannot erase a live provider's crossing memory",Send(warning,saved with {ResetAt=reset.AddHours(10)})==null&&engine.CrossingCount==3);
        engine=new AlertEngine();engine.Update(new[]{saved},true,80,95,false,false);Send(low,saved);
        Send(low,saved with {FromHistory=false,UsedPercent=40});
        Check("A fresh low reading after restore permits its later threshold crossing",Send(low,saved with {FromHistory=false}) is {Lines.Count:1} recross&&recross.Lines[0].Provider=="claude");
        var codex=ParityData.Provider("codex");
        var five=codex.Limits.First(m=>m.Label=="5h");
        var week=codex.Limits.First(m=>m.Label=="week");
        Check("Codex alerts use the weekly limit when its five-hour reading is missing",UsageFeed.Primary(codex with {Limits=new[]{five with {Used=null},week}})==week);
        Check("A reported zero five-hour limit remains primary",UsageFeed.Primary(codex with {Limits=new[]{five with {Used=0},week}})?.Label=="5h");
        Check("An unknown single five-hour window is not replaced with fabricated usage",UsageFeed.Primary(codex with {Limits=new[]{five with {Used=null}}})?.Used==null);
        var claude=ParityData.Provider("claude");
        Check("Claude keeps its five-hour primary even when only weekly has a reading",UsageFeed.Primary(claude with {Limits=new[]{five with {Used=null},week}})?.Label=="5h");
    }

    private sealed class RatesHandler:HttpMessageHandler
    {
        public int Calls;public bool Fail,Invalid;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken cancellationToken)
        {
            Calls++;if(Fail)throw new HttpRequestException("Fixture offline");
            var rates=new Dictionary<string,double> {{"USD",Invalid?2:1},{"KRW",1300},{"EUR",.9},{"CNY",7},{"GBP",.8},{"JPY",145},{"CAD",1.3},{"AUD",1.5},{"CHF",.85}};
            var data=JsonSerializer.Serialize(new {result="success",base_code="USD",time_last_update_unix=1789160000,rates});
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) {Content=new StringContent(data)});
        }
    }
}

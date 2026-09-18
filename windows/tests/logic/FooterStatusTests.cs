using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using IslandPrototype;

internal static class FooterStatusTests
{
    internal static async Task Run(Action<string,bool> check)
    {
        var now=new DateTimeOffset(2026,9,12,12,0,0,TimeSpan.Zero);
        check("Footer relative age uses elapsed seconds and floors minutes",FooterStatus.Relative(now.AddSeconds(-59),now,false)=="59s ago"&&FooterStatus.Relative(now.AddSeconds(-90),now,false)=="1m ago"&&FooterStatus.Relative(now.AddMinutes(-3),now,false)=="3m ago");
        check("Footer relative age supports abbreviated Chinese units",FooterStatus.Relative(now.AddHours(-2),now,true)=="2小时前"&&FooterStatus.Relative(now.AddDays(-8),now,true)=="1周前");
        check("Footer calendar months do not assume every month has thirty days",FooterStatus.Relative(now.AddDays(-30),now,false)=="4w ago"&&FooterStatus.Relative(now.AddMonths(-1),now,false)=="1mo ago"&&FooterStatus.Relative(now.AddYears(-1),now,false)=="1y ago");
        check("A future clock reading is not shown as a negative age",FooterStatus.Relative(now.AddMinutes(2),now,false)=="in 2m");
        string directory=Path.Combine(Path.GetTempPath(),"CodexIslandFooterTests-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(directory);
        try {
            var client=new Client();var scanner=new Scanner();
            var live=new LiveUsageCoordinator(client,()=>now);
            var history=new HistoryCoordinator(scanner,new UsageLedger(Path.Combine(directory,"history.sqlite3")),new ModelPricing(Path.Combine(directory,"prices.json"),new OfflineCatalog()),()=>now,()=>TimeZoneInfo.Utc);
            using var feed=new UsageFeed(live,history);feed.Select(["codex"]);
            check("An unrefreshed provider has an idle footer",FooterStatus.Read(feed,0,["codex"]) is {Label:"Idle",Active:false});
            await feed.RefreshPageAsync(0);
            check("Usage footer refresh does not scan local records",client.Calls==1&&scanner.Calls==0);
            DateTimeOffset first=now;now=now.AddMinutes(2);feed.Select(["claude"]);await feed.RefreshPageAsync(0);
            check("Footer uses the oldest selected provider update",FooterStatus.Read(feed,0,["claude","codex"]) is {Label:"Synced",Active:true} status&&status.UpdatedAt==first);
            check("One missing selected timestamp cannot claim the group is synced",FooterStatus.Read(feed,0,["codex","grok"]) is {Label:"Check connection",Active:false});
            check("An unselected disconnected provider does not affect a synced footer",FooterStatus.Read(feed,0,["codex"]) is {Label:"Synced",Active:true});
            int calls=client.Calls;await feed.RefreshPageAsync(2);
            check("Overview footer refresh scans history without a quota request",scanner.Calls==5&&client.Calls==calls);
            check("A successful empty scan can sync without inventing usage history",FooterStatus.Read(feed,2,["claude","codex"]) is {Label:"Synced",Active:true}&&!feed.HasHistory);
            scanner.Unreadable="grok";await feed.RefreshPageAsync(1);
            check("Unselected history errors do not replace the overview status",FooterStatus.Read(feed,2,["claude","codex"]) is {Label:"Synced",Active:true});
            check("Selected local-record failures suppress the green indicator",FooterStatus.Read(feed,1,["grok"]) is {Label:"Check local records",Active:false,Notice:not null});
            client.Pending=new(TaskCreationOptions.RunContinuationsAsynchronously);var refresh=feed.RefreshPageAsync(0);
            for(int i=0;i<100&&!feed.Loading;i++)await Task.Delay(5);
            check("A quota refresh displays a disabled syncing status",FooterStatus.Read(feed,0,["claude"]) is {Label:"Syncing…",Loading:true,Active:false});
            check("An unrelated quota request does not mark history as syncing",FooterStatus.Read(feed,2,["claude"]) is {Label:"Synced",Loading:false});
            client.Pending.SetResult(new(UsageStatus.Ready,[new("5h",0,null)]));await refresh;
            check("Demo mode stays explicitly labeled",FooterStatus.Read(null,0,["codex"]) is {Label:"Demo data",Active:false});
        } finally{Directory.Delete(directory,true);}
    }
    private sealed class Client:IUsageClient
    {
        internal int Calls;internal TaskCompletionSource<UsageResult>? Pending;
        public Task<UsageResult> FetchAsync(string provider,CancellationToken token){Calls++;return Pending?.Task??Task.FromResult(new UsageResult(UsageStatus.Ready,[new("5h",0,null)]));}
    }
    private sealed class Scanner:ILocalLogScanner
    {
        internal int Calls;internal string? Unreadable;
        public HistoryScan Scan(string source,DateTimeOffset now,CancellationToken token){Interlocked.Increment(ref Calls);return new([],UnreadableFiles:source==Unreadable?1:0);}
    }
    private sealed class OfflineCatalog:HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken token)=>Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable));
    }
}

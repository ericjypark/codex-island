using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using IslandPrototype;

internal static class QuotaHistoryTests
{
    private static string Key(string account)=>new CliCredential("fixture-token",account).AccountKey;
    internal static async Task Run(Action<string,bool> check)
    {
        string directory=Path.Combine(Path.GetTempPath(),"CodexIslandQuotaTests-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(directory);
        DateTimeOffset now=new(2030,1,1,0,0,0,TimeSpan.Zero);string account=Key("A");
        var first=new UsageResult(UsageStatus.Ready,[new("5h",41,now.AddHours(2),SpanSeconds:18000),new("week",0,now.AddDays(5),SpanSeconds:604800)],"pro",account);
        try {
            string path=Path.Combine(directory,"quota.json");var history=new QuotaHistoryStore(path);
            history.Record("codex",first,now);
            history.Record("codex",first with{Status=UsageStatus.Offline},now.AddMinutes(5));
            check("Only successful quota readings create samples",history.Samples("codex",account,"default","5h",now.AddMinutes(5)) is [{Used:41}]);
            check("A real zero is retained in quota history",history.Samples("codex",account,"default","week",now) is [{Used:0}]);
            history.Record("codex",first with{Windows=[new("5h",null,null),new("week",0,now.AddDays(5))]},now.AddMinutes(10));
            check("A missing quota does not append a fabricated sample",history.Samples("codex",account,"default","5h",now.AddMinutes(10)).Length==1);
            check("A freshly reported missing quota cannot be refilled by older history",history.Latest("codex",account,now.AddMinutes(10))?.Windows is [{Used:null},{Used:0}]);
            history.Record("codex",first,now.AddMinutes(15));
            history.Record("codex",first with{Windows=[new("5h",42,now.AddHours(2)),new("week",0,now.AddDays(5))]},now.AddMinutes(15));
            check("Duplicate observation timestamps cannot inflate sample counts",history.Samples("codex",account,"default","5h",now.AddMinutes(15)) is [{Used:41},{Used:42}]);
            var reopened=new QuotaHistoryStore(path);DateTime write=File.GetLastWriteTimeUtc(path);
            check("Quota samples survive a new store instance",reopened.Latest("codex",account,now.AddMinutes(20))?.Windows is [{Used:42},{Used:0}]&&reopened.Samples("codex",account,"default","5h",now.AddMinutes(20)).Length==2);
            check("Loading quota history is read-only",File.GetLastWriteTimeUtc(path)==write);
            check("Another account cannot inherit saved quota",reopened.Latest("codex",Key("B"),now.AddMinutes(20))==null&&reopened.Samples("codex",Key("B"),"default","5h",now.AddMinutes(20)).Length==0);
            check("An absent identity cannot seed saved quota",reopened.Latest("codex",null,now)==null);
            check("A known reset boundary expires a saved reading",reopened.Latest("codex",account,now.AddHours(2))?.Windows is [{Used:null},{Used:0}]);
            var noReset=new QuotaHistoryStore();noReset.Record("codex",first with{Windows=[new("5h",41,null,SpanSeconds:18000),new("Usage",17,null,"other")]},now);
            var seed=noReset.Latest("codex",account,now.AddHours(4));
            check("A saved sample cannot invent a reset countdown",seed?.Windows is [{Used:41,ResetAt:null},{Used:null}]);
            check("Saved values without reset dates still expire by their window span",noReset.Latest("codex",account,now.AddHours(5))?.Windows.All(w=>w.Used==null)==true);
            check("An already visible seeded reading expires without another poll",new LiveProviderState("codex",UsageStatus.Cached,seed!.Windows).VisibleWindows(now.AddHours(5)).All(w=>w.Used==null));
            noReset.Record("codex",first with{Windows=[new("5h",41,null,SpanSeconds:900)]},now);
            check("Reported window duration takes precedence over the short label",noReset.Latest("codex",account,now.AddMinutes(15))?.Windows is [{Used:null}]);
            check("Future samples are not shown after a clock rollback",history.Latest("codex",account,now.AddMinutes(-1))==null&&history.Samples("codex",account,"default","5h",now.AddMinutes(-1)).Length==0);
            var groups=new QuotaHistoryStore();groups.Record("antigravity",first with{Windows=[new("5h",12,now.AddHours(1),"five","gemini"),new("5h",87,now.AddHours(1),"five","claude")]},now);
            check("Matching metric names stay separated by provider group",groups.Samples("antigravity",account,"gemini","five",now) is [{Used:12}]&&groups.Samples("antigravity",account,"claude","five",now) is [{Used:87}]);
            check("Matching account/metric names stay separated by provider",groups.Samples("codex",account,"gemini","five",now).Length==0);
            var cap=new QuotaHistoryStore();for(int i=0;i<1005;i++)cap.Record("codex",first,now.AddSeconds(i));
            check("Each quota series retains at most 1000 real samples",cap.Samples("codex",account,"default","5h",now.AddSeconds(1005)) is {Length:1000} samples&&samples[0].At==now.AddSeconds(5));
            cap.Record("codex",first,now.AddDays(8));
            check("Quota history older than seven days is pruned",cap.Samples("codex",account,"default","5h",now.AddDays(8)) is [{At:var at}]&&at==now.AddDays(8));
            check("Snapshots older than seven days cannot seed launch values",history.Latest("codex",account,now.AddDays(8))==null);
            var accounts=new QuotaHistoryStore();for(int i=0;i<17;i++)accounts.Record("codex",first with{AccountKey=Key(i.ToString())},now.AddSeconds(i));
            check("Account storage is bounded without mixing retained accounts",accounts.Latest("codex",Key("0"),now.AddMinutes(1))==null&&accounts.Latest("codex",Key("16"),now.AddMinutes(1))!=null);
            string unknown=Path.Combine(directory,"unknown.json");new QuotaHistoryStore(unknown).Record("codex",first with{AccountKey=null},now);
            check("Unidentified quota is never assigned to a persistent account",!File.Exists(unknown));
            string serialized=File.ReadAllText(path);
            check("The quota file contains hashed account scopes and no credential or reset-credit payload",serialized.Contains(account)&&!serialized.Contains("fixture-token")&&!serialized.Contains("AccessToken")&&!serialized.Contains("ResetCredits"));
            string malformed=Path.Combine(directory,"malformed.json");File.WriteAllText(malformed,"{broken");var broken=new QuotaHistoryStore(malformed);
            check("Corrupt quota history is preserved on load",broken.Latest("codex",account,now)==null&&broken.Error!=null&&File.ReadAllText(malformed)=="{broken");
            broken.Record("codex",first,now);
            check("Replacing corrupt history keeps a recoverable original",Directory.GetFiles(directory,"malformed.json.recovery-*") is [var backup]&&File.ReadAllText(backup)=="{broken"&&broken.Error==null);
            string newer=Path.Combine(directory,"newer.json"),newerData="{\"SchemaVersion\":2,\"Accounts\":[]}";File.WriteAllText(newer,newerData);var future=new QuotaHistoryStore(newer);
            future.Record("codex",first,now);
            check("A newer cache schema is never overwritten",future.Error!=null&&File.ReadAllText(newer)==newerData&&future.Samples("codex",account,"default","5h",now).Length==1);
            string parent=Path.Combine(directory,"file-parent");File.WriteAllText(parent,"preserve");var blocked=new QuotaHistoryStore(Path.Combine(parent,"quota.json"));blocked.Record("codex",first,now);
            check("A failed cache write preserves live samples and exposes the failure",blocked.Error!=null&&blocked.Samples("codex",account,"default","5h",now).Length==1&&File.ReadAllText(parent)=="preserve");
            string invalid=Path.Combine(directory,"invalid.json");
            File.WriteAllText(invalid,JsonSerializer.Serialize(new QuotaHistoryFile(1,[new("codex",account,now,null,[],[new("default","5h",[new(now,101)])])])));
            var invalidHistory=new QuotaHistoryStore(invalid);
            check("Out-of-range persisted percentages are rejected",invalidHistory.Latest("codex",account,now)==null&&invalidHistory.Error!=null);
            await Coordinator(check,now,first);
        }finally{Directory.Delete(directory,true);}
    }
    private static async Task Coordinator(Action<string,bool> check,DateTimeOffset now,UsageResult first)
    {
        var history=new QuotaHistoryStore();history.Record("codex",first,now);DateTimeOffset clock=now.AddMinutes(10);
        var client=new Client {Account=first.AccountKey};using var coordinator=new LiveUsageCoordinator(client,()=>clock,history);coordinator.Select(["codex"]);
        var pending=new TaskCompletionSource<UsageResult>(TaskCreationOptions.RunContinuationsAsynchronously);var entered=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        client.Fetch=(_,_)=>{entered.SetResult();return pending.Task;};
        var refresh=coordinator.RefreshAsync();await entered.Task;
        check("A confirmed current account displays saved readings before the network completes",coordinator.State("codex") is {Status:UsageStatus.Cached,FromHistory:true,Loading:true,Windows:[{Used:41},{Used:0}]});
        check("Cached launch values cannot arm fresh-usage alerts",!coordinator.HasUpdated);
        pending.SetResult(new(UsageStatus.Offline,[],AccountKey:first.AccountKey));await refresh;
        check("A failed first poll retains saved values with the network error",coordinator.State("codex") is {Status:UsageStatus.Offline,FromHistory:true,Windows:[{Used:41},{Used:0}]});
        check("A failed first poll does not append retained samples",coordinator.Samples("codex","default","5h").Length==1);
        client.Fetch=(_,_)=>Task.FromResult(first with{Windows=[new("week",2,now.AddDays(5))]});await coordinator.RefreshAsync(true);
        check("A successful poll replaces the cached window set and clears cache provenance",coordinator.HasUpdated&&coordinator.State("codex") is {FromHistory:false,Windows:[{Label:"week",Used:2}]});
        client.Fetch=(_,_)=>Task.FromResult(new UsageResult(UsageStatus.Offline,[],AccountKey:first.AccountKey));await coordinator.RefreshAsync(true);
        check("A later failure cannot resurrect an omitted cached window",coordinator.State("codex").Windows is [{Label:"week",Used:2}]);
        check("An already identified session avoids redundant launch-identity reads",client.IdentityReads==1);
        var switched=new Client{Account=Key("B"),Fetch=(_,_)=>Task.FromResult(new UsageResult(UsageStatus.Offline,[],AccountKey:Key("B")))};
        using var other=new LiveUsageCoordinator(switched,()=>clock,history);other.Select(["codex"]);await other.RefreshAsync();
        check("A different current account cannot seed another account's launch data",other.State("codex").Windows.Length==0&&other.State("codex").Plan==null);
        var anonymous=new Client{Fetch=(_,_)=>Task.FromResult(new UsageResult(UsageStatus.Offline,[]))};using var noIdentity=new LiveUsageCoordinator(anonymous,()=>clock,history);noIdentity.Select(["codex"]);await noIdentity.RefreshAsync();
        check("Unavailable account identity leaves the launch cache hidden",noIdentity.State("codex").Windows.Length==0);
        var authFail=new Client{Account=first.AccountKey,Fetch=(_,_)=>Task.FromResult(new UsageResult(UsageStatus.Expired,[],AccountKey:first.AccountKey))};history.Record("claude",first,now);
        using var claude=new LiveUsageCoordinator(authFail,()=>clock,history);claude.Select(["claude"]);await claude.RefreshAsync();
        check("Claude terminal login failures clear seeded launch values",claude.State("claude") is {Status:UsageStatus.Expired,Windows:[]});
        var rotating=new Client();var identity=new TaskCompletionSource<string?>(TaskCreationOptions.RunContinuationsAsynchronously);var identifyEntered=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        rotating.Identify=(_,_)=>{identifyEntered.SetResult();return identity.Task;};
        using var canceled=new LiveUsageCoordinator(rotating,()=>clock,history);canceled.Select(["codex"]);var old=canceled.RefreshAsync();await identifyEntered.Task;
        canceled.Select(["claude"]);identity.SetResult(first.AccountKey);await old;
        check("Canceled launch identity work cannot seed an obsolete selection",canceled.State("codex").Windows.Length==0&&rotating.Fetches==0);
    }
    private sealed class Client:IUsageClient,IUsageAccountReader
    {
        internal string? Account;internal int IdentityReads,Fetches;
        internal Func<string,CancellationToken,Task<string?>>? Identify;
        internal Func<string,CancellationToken,Task<UsageResult>> Fetch=(_,_)=>Task.FromResult(new UsageResult(UsageStatus.NotConnected,[]));
        public Task<string?> ReadAccountKeyAsync(string provider,CancellationToken cancellation){IdentityReads++;return Identify?.Invoke(provider,cancellation)??Task.FromResult(Account);}
        public Task<UsageResult> FetchAsync(string provider,CancellationToken cancellation){Fetches++;return Fetch(provider,cancellation);}
    }
}

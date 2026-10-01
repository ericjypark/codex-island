using System;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using IslandPrototype;

internal static class ImportBoundaryTests
{
    private static readonly DateTimeOffset Now=new(2026,9,12,12,0,0,TimeSpan.Zero);
    private static TokenRecord Record(string id="test-id")=>new("codex",Now.AddDays(-1),"gpt-5.4",100,20,30,40,id);
    internal static async Task Run(string root,Action<string,bool> check)
    {
        root=Path.Combine(root,"boundaries");Directory.CreateDirectory(root);
        check("Unicode event identities use the Mac UTF-8 length contract",UsageLedger.Key("codex","세션:🙂")=="229c093e48271e96227da13bcfcc1b3e6f87d000f5f041e0f41743faf807c422");
        string source=Path.Combine(root,"source.sqlite3"),destination=Path.Combine(root,"destination.sqlite3");
        var original=new UsageLedger(source);original.Retain("codex",[Record()],Now,Now);
        var target=new UsageLedger(destination);target.Retain("codex",[Record("existing")],Now,Now);
        var result=target.Import(source,Now);
        check("Import merges into existing Windows history without removing it",result.AddedRecords==1&&target.Retain("codex",[],Now,Now).Events.Length==2);
        check("Automatic backup contains the history from before import",result.BackupPath!=null&&new UsageLedger(result.BackupPath).Retain("codex",[],Now,Now).Events.Single().Tokens==190);
        string exported=Path.Combine(root,"exported.sqlite3");File.WriteAllText(exported,"previous export");
        check("User backup atomically replaces a chosen export",target.CopyDatabase(exported)&&new UsageLedger(exported).Retain("codex",[],Now,Now).Events.Length==2);
        bool sameRejected=false;try{target.CopyDatabase(destination);}catch(IOException){sameRejected=true;}
        check("Backup cannot overwrite its active database",sameRejected&&target.Retain("codex",[],Now,Now).Events.Length==2);
        string invalid=Path.Combine(root,"invalid.sqlite3");original.CopyDatabase(invalid);
        using(var db=new NativeSqlite(invalid))db.Execute("UPDATE usage_events SET input_tokens=-1");
        bool rejected=false;try{target.Import(invalid,Now);}catch(IOException){rejected=true;}
        check("Invalid imported counts leave retained history unchanged",rejected&&target.Retain("codex",[],Now,Now).Events.Sum(e=>e.Tokens)==380);
        string future=Path.Combine(root,"future.sqlite3");original.CopyDatabase(future);
        using(var db=new NativeSqlite(future))db.Execute("PRAGMA user_version=2");
        rejected=false;try{target.Import(future,Now);}catch(IOException){rejected=true;}
        check("Newer import schema is preserved and rejected",rejected&&target.Retain("codex",[],Now,Now).Events.Length==2);
        string fractional=Path.Combine(root,"fractional.sqlite3");original.CopyDatabase(fractional);
        using(var db=new NativeSqlite(fractional))db.Execute("UPDATE usage_events SET input_tokens=3.5");
        rejected=false;try{target.Import(fractional,Now);}catch(IOException){rejected=true;}
        check("Noninteger imported counts are rejected instead of silently rounded",rejected&&target.Retain("codex",[],Now,Now).Events.Length==2);
        string precise=Path.Combine(root,"precise.sqlite3");var instant=Now.AddHours(-12).AddMilliseconds(1);
        new UsageLedger(precise).Retain("codex",[Record() with{Timestamp=instant}],Now,Now);
        var preciseTarget=new UsageLedger(Path.Combine(root,"precise-target.sqlite3"));preciseTarget.Import(precise,Now);
        check("Windows backups preserve exact millisecond timestamps near a day boundary",preciseTarget.Retain("codex",[],Now,Now).Events.Single().Timestamp==instant);
        string aliasSource=Path.Combine(root,"alias-source.sqlite3"),aliasTarget=Path.Combine(root,"alias-target.sqlite3");
        new UsageLedger(aliasSource).Retain("codex",[Record("copy") with{Aliases=["shared"]}],Now,Now);
        var existingAlias=new UsageLedger(aliasTarget);existingAlias.Retain("codex",[Record("native") with{Aliases=["shared"],Input=120}],Now,Now);
        var aliasImport=existingAlias.Import(aliasSource,Now);
        check("Imported aliases deduplicate against existing native identities without replacing corrections",aliasImport.AddedRecords==0&&existingAlias.Retain("codex",[],Now,Now).Events.Single().Input==120);
        string recovered=Path.Combine(root,"recovered.sqlite3");new UsageLedger(recovered).Retain("claude",[],Now,Now);
        var day=new HistoricalUsageDay("claude",new(2026,3,8,6,0,0,TimeSpan.Zero),new(2026,3,9,5,0,0,TimeSpan.Zero),"2026-03-08",-21600,1000,200,"daily-fixture");
        using(var db=new NativeSqlite(recovered))db.Execute("INSERT INTO historical_daily_usage VALUES(?,?,?,?,?,?,?,?)",day.Provider,day.IntervalStart.ToUnixTimeMilliseconds(),day.IntervalEnd.ToUnixTimeMilliseconds(),day.SourceDate,day.UtcOffsetSeconds,day.Tokens,day.BillableTokens,day.EvidenceId);
        var spring=new TokenRecord("claude",day.IntervalStart.AddHours(2),"claude-sonnet-4-6",100,20,30,40,"observed");
        var supplements=HistoricalUsageDay.Supplements([day],[spring],Now);
        check("DST recovery keeps the original date and subtracts already observed usage",day.Valid&&supplements.Single() is{Tokens:810,BillableTokens:80,RecoveredTokens:810,Dollars:0}&&supplements[0].Date==new DateTime(2026,3,8));
        using var pricing=new ModelPricing(Path.Combine(root,"prices.json"),new OfflineCatalog(),new(){{"claude-sonnet-4-6",new(3,15,3.75,.3)}});
        var summary=HistorySummary.Build("claude",[spring],pricing,Now,TimeZoneInfo.FindSystemTimeZoneById("Hawaiian Standard Time"),historicalDays:[day]);
        check("Recovered counts keep their original day after a timezone change and carry no invented model or price",summary.Days.Sum(d=>d.Tokens)==1000&&summary.Days.Single(d=>d.RecoveredTokens>0).Date==new DateTime(2026,3,8)&&summary.Days.Single(d=>d.RecoveredTokens==0).Date==new DateTime(2026,3,7)&&summary.Days.Sum(d=>d.UnpricedTokens)==810&&summary.Models.All(m=>m.Length==0)&&summary.LocalNotice==null);
        string overlap=Path.Combine(root,"overlap.sqlite3");new UsageLedger(recovered).CopyDatabase(overlap);
        using(var db=new NativeSqlite(overlap))db.Execute("UPDATE historical_daily_usage SET interval_start_ms=?,interval_end_ms=?,utc_offset=-18000",day.IntervalStart.AddHours(-1).ToUnixTimeMilliseconds(),day.IntervalEnd.ToUnixTimeMilliseconds());
        var dailyTarget=new UsageLedger(Path.Combine(root,"daily-target.sqlite3"));dailyTarget.Import(recovered,Now);
        rejected=false;try{dailyTarget.Import(overlap,Now);}catch(IOException){rejected=true;}
        check("Overlapping recovery intervals are rolled back without changing previous totals",rejected&&dailyTarget.Retain("claude",[],Now,Now).HistoricalDays is[{Tokens:1000}]);
        using var scanner=new BlockingScanner();
        using var history=new HistoryCoordinator(scanner,new UsageLedger(Path.Combine(root,"coordinator.sqlite3")),new ModelPricing(Path.Combine(root,"coordinator-prices.json"),new OfflineCatalog(),new()),()=>Now,()=>TimeZoneInfo.Utc);
        var refresh=history.RefreshAsync(true);await scanner.Entered.Task;
        var imported=history.ImportAsync(recovered);var joined=history.RefreshAsync(true);
        check("A refresh during import joins the pending operation",ReferenceEquals(imported,joined)&&history.Loading);
        scanner.Release.Set();await Task.WhenAll(refresh,imported,joined);
        check("Import waits for an active scan and then publishes recovered history",history.State("claude")?.Days.Sum(d=>d.Tokens)==1000&&!history.Loading);
    }
    private sealed class OfflineCatalog : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken cancellation)=>Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable));
    }
    private sealed class BlockingScanner : ILocalLogScanner,IDisposable
    {
        internal readonly TaskCompletionSource Entered=new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly ManualResetEventSlim Release=new(false);
        public HistoryScan Scan(string source,DateTimeOffset now,CancellationToken cancellation){Entered.TrySetResult();Release.Wait(cancellation);return new([]);}
        public void Dispose()=>Release.Dispose();
    }
}

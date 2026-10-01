using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using IslandPrototype;

internal static class HistoryTests
{
    private static readonly DateTimeOffset Now=new(2026,9,11,18,0,0,TimeSpan.Zero);
    internal static async Task Run(Action<string,bool> check)
    {
        string root=Path.Combine(Path.GetTempPath(),"CodexIslandHistory-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
        try {
            check("Windows provides a usable SQLite engine",Version.TryParse(NativeSqlite.Version,out var version)&&version>=new Version(3,24));
            TestReaders(root,check);TestLedger(root,check);TestDatabases(root,check);await TestPricingAndSummary(root,check);await TestCoordinator(root,check);
        }finally{Directory.Delete(root,true);}
    }
    private static TokenRecord Event(string id="record",long input=10,long output=5,string model="gpt-5.4",DateTimeOffset? date=null,string provider="codex")=>new(provider,date??Now-TimeSpan.FromMinutes(5),model,input,output,0,0,id);
    private static void Write(string file,string text){Directory.CreateDirectory(Path.GetDirectoryName(file)!);File.WriteAllText(file,text);}
    private static string Codex(long input=110,long cached=100,long output=5,string? timestamp=null)=>JsonSerializer.Serialize(new{timestamp=timestamp??Now.AddMinutes(-1).ToString("O"),type="event_msg",payload=new{type="token_count",info=new{last_token_usage=new{input_tokens=input,cached_input_tokens=cached,output_tokens=output},total_token_usage=new{input_tokens=9999999,output_tokens=9999999}}}});
    private static string Claude(long input,long output,string? request="r",string model="claude-sonnet-4-6")=>JsonSerializer.Serialize(new{timestamp=Now.AddMinutes(-1).ToString("O"),type="assistant",requestId=request,message=new{id="msg1",model,usage=new{input_tokens=input,output_tokens=output,cache_creation_input_tokens=3,cache_read_input_tokens=8}}});
    private static void TestReaders(string root,Action<string,bool> check)
    {
        string profile=Path.Combine(root,"profile"),codex=Path.Combine(root,"custom-codex"),claude=Path.Combine(root,"custom-claude"),second=Path.Combine(root,"second-claude");
        var env=new Dictionary<string,string>{{"CODEX_HOME",codex},{"CLAUDE_CONFIG_DIR",claude+", "+second}};
        var scanner=new LocalLogScanner(profile,key=>env.GetValueOrDefault(key));
        check("Custom session roots and comma-separated Claude roots are honored",scanner.Roots("codex").Single()==Path.Combine(codex,"sessions")&&scanner.Roots("claude").Length==2);
        string file=Path.Combine(codex,"sessions","2026","rollout-fixture.jsonl");
        Write(file,"{\"type\":\"turn_context\",\"payload\":{\"model\":\"gpt-5.4\"}}\n"+Codex()+"\n"+Codex(120,100,7)+"\n");
        var stamp=File.GetLastWriteTimeUtc(file);var bytes=File.ReadAllBytes(file);
        var scan=scanner.Scan("codex",Now,CancellationToken.None);
        check("Codex uses disjoint input and cache buckets, never cumulative session totals",scan.Events.Length==2&&scan.Events.Sum(e=>e.Tokens)==242&&scan.Events[0].Input==10&&scan.Events[0].CacheRead==100);
        check("Same-millisecond Codex records have distinct stable identities",scan.Events.Select(e=>e.Id).Distinct().Count()==2&&scanner.Scan("codex",Now,CancellationToken.None).Events.Select(e=>e.Id).SequenceEqual(scan.Events.Select(e=>e.Id)));
        check("Session scanning leaves source bytes and modification time unchanged",bytes.SequenceEqual(File.ReadAllBytes(file))&&stamp==File.GetLastWriteTimeUtc(file));
        File.AppendAllText(file,Codex(30,20,4,Now.AddSeconds(-1).ToString("O"))+"\n");
        var appended=scanner.Scan("codex",Now,CancellationToken.None);
        check("Appending a session adds one record while preserving previous identities",appended.Events.Length==3&&scan.Events.All(e=>appended.Events.Any(a=>a.Id==e.Id)));
        Write(file,Codex(-1,0)+"\n"+Codex(1,2)+"\n"+Codex(timestamp:Now.AddDays(1).ToString("O"))+"\n"+Codex(timestamp:"invalid")+"\n"+Codex(0,0,0)+"\n");
        scan=scanner.Scan("codex",Now,CancellationToken.None);
        check("Negative, inconsistent, future, invalid-date and zero records cannot add usage",scan.Events.Length==0&&scan.SkippedRecords>=3);
        Write(file,new string('x',1_048_577)+"\n"+Codex()+"\n{\"type\":");
        scan=scanner.Scan("codex",Now,CancellationToken.None);
        check("Oversized and unfinished lines do not prevent later complete usage records",scan.Events.Length==1&&scan.SkippedRecords==2);
        string cf=Path.Combine(claude,"projects","project","subagents","agent.jsonl");
        Write(cf,Claude(10,2)+"\n"+Claude(20,4)+"\n"+Claude(30,3)+"\n"+Claude(500,500,"r","<synthetic>")+"\n");
        var cs=scanner.Scan("claude",Now,CancellationToken.None);
        check("Claude streaming keeps a dominating real row without mixing component maxima",cs.Events is [{Input:20,Output:4,CacheWrite:3,CacheRead:8}]);
        Write(Path.Combine(second,"projects","project","no-request.jsonl"),Claude(1,1,null)+"\n"+Claude(1,1,null)+"\n");
        cs=scanner.Scan("claude",Now,CancellationToken.None);
        check("Claude messages without both stable IDs retain occurrence-based identities",cs.Events.Length==3);
        string gf=Path.Combine(profile,".grok","sessions","session","updates.jsonl");
        string Grok(bool incomplete,long output)=>JsonSerializer.Serialize(new{timestamp=Now.ToUnixTimeMilliseconds(),@params=new{update=new{_meta=new{promptId="prompt",usageIsIncomplete=incomplete,usage=new{modelUsage=new Dictionary<string,object>{{"grok-4",new{inputTokens=120,outputTokens=output,cacheReadTokens=40,cacheCreationTokens=30}}}}}}}});
        Write(gf,Grok(false,10)+"\n"+Grok(false,20)+"\n"+Grok(true,500)+"\n");
        var gs=scanner.Scan("grok",Now,CancellationToken.None);
        check("Grok final prompt usage is deduplicated and excludes incomplete updates",gs.Events is [{Input:50,Output:20,CacheRead:40,CacheWrite:30}]);
        File.Delete(file);check("Deleted source files are absent from the next scan",scanner.Scan("codex",Now,CancellationToken.None).Events.Length==0);
    }
    private static void TestLedger(string root,Action<string,bool> check)
    {
        string path=Path.Combine(root,"ledger","usage.sqlite3");var ledger=new UsageLedger(path);var original=Event();
        var retained=ledger.Retain("codex",[original],Now,Now);
        check("Usage records commit to the native SQLite ledger",retained.SaveError==null&&retained.Events.Single().Tokens==15);
        retained=ledger.Retain("codex",[original],Now.AddSeconds(1),Now);
        check("Repeated scans do not duplicate an event",retained.Events.Length==1);
        retained=ledger.Retain("codex",[original with{Input=4,Output=1}],Now.AddSeconds(2),Now);
        check("A current corrected record can lower an earlier count",retained.Events.Single().Tokens==5);
        retained=ledger.Retain("codex",[original with{Input=900},Event("late-new")],Now.AddSeconds(-1),Now);
        check("A late scan only inserts new records and cannot replace a newer correction",retained.Events.Length==2&&retained.Events.Single(e=>e.Id.EndsWith(UsageLedger.Key("codex","record"))).Tokens==5);
        var reopened=new UsageLedger(path).Retain("codex",[],Now.AddMinutes(1),Now);
        check("History survives empty sources and a new ledger instance",reopened.SaveError==null&&reopened.Events.Length==2&&reopened.Events.Sum(e=>e.Tokens)==20);
        var newer=new UsageLedger(path);newer.Retain("codex",[original with{Input=80}],Now.AddMinutes(2),Now);
        retained=ledger.Retain("codex",[original],Now,Now);
        check("Another writer's newer record is not overwritten by stale in-memory history",retained.Events.Single(e=>e.Id.EndsWith(UsageLedger.Key("codex","record"))).Input==80);
        var first=Event("messageA") with {Aliases=["fingerprint:test"]};
        ledger.Retain("opencode",[first],Now,Now);
        retained=new UsageLedger(path).Retain("opencode",[first with{Id="messageB"}],Now.AddMinutes(1),Now);
        check("Persisted aliases deduplicate forked calls across record IDs and restarts",retained.Events.Length==1);
        retained=ledger.Retain("grok",[Event("utf8",model:"모델'; DROP TABLE usage_events; --",provider:"grok")],Now,Now);
        check("Model strings are stored as parameters without SQL interpretation",retained.SaveError==null&&retained.Events.Single().Model.Contains("모델"));
        var invalid=Event("invalid") with{Input=long.MaxValue};
        retained=ledger.Retain("claude",[invalid,Event("future",date:Now.AddSeconds(1)),Event("negative",input:-1)],Now,Now);
        check("The durable boundary rejects overflow, negative and future events",retained.Events.Length==0);
        string corrupt=Path.Combine(root,"corrupt.sqlite3");byte[] corruptBytes=Encoding.UTF8.GetBytes("preserve this damaged source");File.WriteAllBytes(corrupt,corruptBytes);
        retained=new UsageLedger(corrupt).Retain("codex",[original],Now,Now);
        check("A corrupt ledger is preserved while current usage remains visible",retained.SaveError!=null&&retained.Events.Length==1&&File.ReadAllBytes(corrupt).SequenceEqual(corruptBytes));
        string future=Path.Combine(root,"future.sqlite3");using(var db=new NativeSqlite(future))db.Execute("PRAGMA user_version=2");
        byte[] before=File.ReadAllBytes(future);retained=new UsageLedger(future).Retain("codex",[original],Now,Now);
        check("A newer database schema is not overwritten",retained.SaveError!=null&&File.ReadAllBytes(future).SequenceEqual(before));
        string blocked=Path.Combine(root,"blocked");File.WriteAllText(blocked,"file blocking directory");var fallback=new UsageLedger(Path.Combine(blocked,"history.sqlite3"));
        fallback.Retain("codex",[original],Now,Now);retained=fallback.Retain("codex",[],Now.AddSeconds(1),Now);
        check("Failed saves retain previously observed events in memory",retained.SaveError!=null&&retained.Events.Length==1);
        File.Delete(blocked);retained=fallback.Retain("codex",[],Now.AddSeconds(2),Now);
        check("Unsaved history is committed after storage becomes available",retained.SaveError==null&&new UsageLedger(Path.Combine(blocked,"history.sqlite3")).Retain("codex",[],Now.AddSeconds(3),Now).Events.Length==1);
    }
    private static byte[] Varint(ulong value){var bytes=new List<byte>();while(value>=128){bytes.Add((byte)(value|128));value>>=7;}bytes.Add((byte)value);return bytes.ToArray();}
    private static byte[] Field(int number,ulong value)=>Varint((ulong)number<<3).Concat(Varint(value)).ToArray();
    private static byte[] Field(int number,byte[] value)=>Varint(((ulong)number<<3)|2).Concat(Varint((ulong)value.Length)).Concat(value).ToArray();
    private static byte[] Join(params byte[][] fields)=>fields.SelectMany(b=>b).ToArray();
    private static void TestDatabases(string root,Action<string,bool> check)
    {
        string profile=Path.Combine(root,"db-profile"),folder=Path.Combine(profile,".gemini","antigravity-cli","conversations");Directory.CreateDirectory(folder);
        string path=Path.Combine(folder,"conversation.db");
        byte[] date=Field(1,(ulong)Now.AddMinutes(-3).ToUnixTimeSeconds()),usage=Join(Field(2,20UL),Field(3,10UL),Field(4,4UL),Field(5,8UL),Field(12,Encoding.UTF8.GetBytes("message-id")));
        byte[] chat=Join(Field(4,usage),Field(19,Encoding.UTF8.GetBytes("gemini-3.6-flash"))),generation=Join(Field(1,chat),Field(2,Join(Varint(1),Varint(2))));
        using(var db=new NativeSqlite(path)) {
            db.Execute("CREATE TABLE steps(idx INTEGER,metadata BLOB)");db.Execute("CREATE TABLE gen_metadata(idx INTEGER,data BLOB)");
            db.Execute("INSERT INTO steps VALUES(?,?)",1,Field(1,date));db.Execute("INSERT INTO steps VALUES(?,?)",2,Field(1,date));
            db.Execute("INSERT INTO gen_metadata VALUES(?,?)",0,generation);db.Execute("INSERT INTO gen_metadata VALUES(?,?)",1,generation);
        }
        byte[] before=File.ReadAllBytes(path);var scanner=new LocalLogScanner(profile,_=>null);var scan=scanner.Scan("antigravity",Now,CancellationToken.None);
        check("Antigravity counts one generation once across multiple steps and copies",scan.Events is [{Input:20,Output:10,CacheWrite:4,CacheRead:8}]);
        check("Antigravity database reads preserve source bytes",File.ReadAllBytes(path).SequenceEqual(before));
        check("Truncated and overflowing protobuf encodings are rejected",WireFields.Parse([10,100,1])==null&&WireFields.Parse(Join([8],Enumerable.Repeat((byte)255,10).ToArray()))==null);
        var bad=WireFields.Parse(Join(Field(1,Join(Field(4,Join(Field(2,ulong.MaxValue),Field(3,1UL))),Field(19,Encoding.UTF8.GetBytes("model")))),Field(2,1UL)));
        check("Invalid protobuf counters cannot be interpreted as real zero input",DatabaseLogScanner.AntigravityRecord(bad,new(){{1,Now}},"fallback")==null);
        string op=Path.Combine(profile,".local","share","opencode");Directory.CreateDirectory(op);
        string Message(string model="gpt-5.4")=>JsonSerializer.Serialize(new{role="assistant",providerID="openai",modelID=model,time=new{created=Now.AddHours(-1).ToUnixTimeMilliseconds()},tokens=new{input=10,output=5,reasoning=2,cache=new{read=20,write=3}}});
        using(var db=new NativeSqlite(Path.Combine(op,"opencode.db"))){db.Execute("CREATE TABLE message(id TEXT,data TEXT)");db.Execute("INSERT INTO message VALUES(?,?)","db-message",Message());db.Execute("INSERT INTO message VALUES(?,?)","fork-message",Message());}
        Write(Path.Combine(op,"storage","message","session","legacy-message.json"),Message());
        scan=scanner.Scan("opencode",Now,CancellationToken.None);
        check("OpenCode deduplicates database, legacy, and fork copies by call fingerprint",scan.Events is [{Input:10,Output:7,CacheRead:20,CacheWrite:3}]&&scan.Events[0].Aliases?.Length==1);
    }
    private sealed class CatalogHandler : HttpMessageHandler
    {
        internal string Body="";internal HttpStatusCode Status=HttpStatusCode.OK;internal int Calls;internal string? Tag;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken cancellation)
        {
            Calls++;Tag=request.Headers.IfNoneMatch.FirstOrDefault()?.ToString();var response=new HttpResponseMessage(Status){Content=new StringContent(Body)};response.Headers.ETag=new("\"catalog-test\"");return Task.FromResult(response);
        }
    }
    private static string Catalog(double input)=>JsonSerializer.Serialize(new{schemaVersion=1,generatedAt=Now.ToString("O"),models=new Dictionary<string,object>{{"gpt-5.4",new{displayName="GPT Test",inputPerMillion=input,outputPerMillion=15,cacheCreationPerMillion=2.5,cacheReadPerMillion=.25}}}});
    private static async Task TestPricingAndSummary(string root,Action<string,bool> check)
    {
        var handler=new CatalogHandler{Body=Catalog(3)};string path=Path.Combine(root,"prices.json");var seed=new Dictionary<string,ModelRates>{{"gpt-5.4",new(2.5,15,2.5,.25)},{"seed-only",new(1,2,1,.1)}};
        using var pricing=new ModelPricing(path,handler,seed);
        check("Model IDs normalize dated and thinking variants consistently",ModelPricing.Canonical("claude-sonnet-4-6-20260101-thinking")=="claude-sonnet-4-6"&&ModelPricing.Canonical("gpt-5.4")=="gpt-5.4");
        check("A complete catalog replaces matching seed rates",await pricing.RefreshAsync(Now)&&pricing.Rates("gpt-5.4",Now)?.Input==3&&pricing.Pretty("gpt-5.4")=="GPT Test");
        check("Models omitted from the catalog retain their seed rate",pricing.Rates("seed-only",Now)?.Input==1);
        byte[] before=File.ReadAllBytes(path);handler.Body="{\"schemaVersion\":1,\"models\":{\"gpt-5.4\":{\"inputPerMillion\":9}}}";
        check("An incomplete catalog cannot erase saved prices",!await pricing.RefreshAsync(Now.AddDays(1),true)&&pricing.Rates("gpt-5.4",Now)?.Input==3&&before.SequenceEqual(File.ReadAllBytes(path)));
        handler.Status=HttpStatusCode.NotModified;
        await pricing.RefreshAsync(Now.AddDays(2),true);
        check("Conditional catalog requests retain the table and persist verification time",handler.Tag=="\"catalog-test\""&&pricing.UpdatedAt==Now.AddDays(2));
        var restartedHandler=new CatalogHandler();using var restarted=new ModelPricing(path,restartedHandler,seed);await restarted.RefreshAsync(Now.AddDays(2).AddHours(1));
        check("A verified price cache prevents unnecessary fetches after restart",restartedHandler.Calls==0&&restarted.Rates("gpt-5.4",Now)?.Input==3);
        check("Historical Gemini rates use event time across the introductory cutoff",pricing.Rates("gemini-3.6-flash",new(2026,12,31,23,59,0,TimeSpan.Zero))?.Input==.75&&pricing.Rates("gemini-3.6-flash",new(2027,1,1,0,0,0,TimeSpan.Zero))?.Input==1.5);
        var zone=TimeZoneInfo.FindSystemTimeZoneById("Central Standard Time");
        var events=new[]{Event("today",input:1_000_000,output:0),Event("cache",input:0,output:0) with{CacheRead=1_000_000},Event("unknown",input:100,output:0,model:"new-unpriced"),Event("yesterday",date:new(2026,9,11,4,59,0,TimeSpan.Zero)),Event("future",date:Now.AddHours(1))};
        var summary=HistorySummary.Build("codex",events,pricing,Now,zone);
        check("Cost days use local midnight and exclude future events",summary.Today.Tokens==2_000_100&&summary.Days.Length==2&&summary.Month.Tokens==2_000_115);
        check("Unknown model usage remains counted and explicitly unpriced",summary.Today.UnpricedTokens==100&&summary.Notice!=null&&Math.Abs(summary.Today.Dollars-3.25)<1e-9);
        check("Cache-only usage has value but no billable input/output tokens",summary.Today.BillableTokens==1_000_100&&summary.Models[0].Single(m=>m.Model=="gpt-5.4").Dollars==3.25);
        check("Cumulative series end at their corresponding totals",summary.Today.Series[^1]==summary.Today.Dollars&&summary.Month.Series[^1]==summary.Month.Dollars);
        var old=HistorySummary.Build("codex",[Event(date:Now.AddMonths(-2))],pricing,Now,zone);
        var empty=HistorySummary.Build("codex",[],pricing,Now,zone);
        check("A recorded zero today differs from having no history evidence",old.HasEvidence&&old.Today.Tokens==0&&!empty.HasEvidence);
        var fall=HistorySummary.Build("codex",[Event(date:new(2026,11,1,6,30,0,TimeSpan.Zero)),Event("second-hour",date:new(2026,11,1,7,30,0,TimeSpan.Zero))],pricing,new(2026,11,1,8,0,0,TimeSpan.Zero),zone);
        check("Both occurrences of a repeated DST hour belong to the same local day",fall.Today.Tokens==30&&fall.Days.Length==1);
    }
    private sealed class Scanner : ILocalLogScanner
    {
        internal int Calls;internal TokenRecord[] Events=[Event()];internal int Unreadable;
        public HistoryScan Scan(string source,DateTimeOffset now,CancellationToken cancellation){Interlocked.Increment(ref Calls);return new(source=="codex"?Events:[],source=="codex"?1:0,source=="codex"?Unreadable:0);}
    }
    private sealed class EmptyUsage : IUsageClient
    {
        public Task<UsageResult> FetchAsync(string provider,CancellationToken cancellation)=>Task.FromResult(new UsageResult(UsageStatus.NotConnected,[]));
    }
    private static async Task TestCoordinator(string root,Action<string,bool> check)
    {
        var scanner=new Scanner();var handler=new CatalogHandler{Body=Catalog(2.5)};
        using var pricing=new ModelPricing(Path.Combine(root,"coordinator-prices.json"),handler,new());
        using var history=new HistoryCoordinator(scanner,new UsageLedger(Path.Combine(root,"coordinator.sqlite3")),pricing,()=>Now,()=>TimeZoneInfo.Utc);
        using var feed=new UsageFeed(new LiveUsageCoordinator(new EmptyUsage(),()=>Now),history);
        feed.Select(["claude"]);await feed.RefreshAsync();
        check("History scans every source independently of selected quota providers",scanner.Calls==5&&feed.History("codex")?.HasEvidence==true&&feed.Provider("codex").Costs.Length==2);
        check("Live calendar values come from history rather than the demo fixture",feed.Days.Length==1&&feed.Days.Single().Total==15&&!feed.IsDemo&&feed.Provider("claude").Costs.Length==0);
        await feed.RefreshAsync();check("Automatic history scanning respects the configured minimum interval",scanner.Calls==5);
        scanner.Events=[];scanner.Unreadable=1;await feed.RefreshAsync(true);
        check("Unreadable source files retain durable usage with a visible notice",feed.Provider("codex").Costs[0].Tokens==15&&feed.History("codex")?.Notice!=null);
        scanner.Unreadable=0;await feed.RefreshAsync(true);
        check("A healthy scan clears stale local-record warnings",feed.History("codex")?.Notice==null&&!feed.HistoryLoading);
    }
}

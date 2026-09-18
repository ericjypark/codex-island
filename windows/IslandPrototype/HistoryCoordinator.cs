using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace IslandPrototype;

internal sealed class HistoryCoordinator : IDisposable
{
    private static readonly string[] Providers=["claude","codex","grok","antigravity"];
    private static readonly string[] Sources=["claude","codex","grok","antigravity","opencode"];
    private readonly ILocalLogScanner scanner;
    private readonly UsageLedger ledger;
    private readonly ModelPricing pricing;
    private readonly Func<DateTimeOffset> clock;
    private readonly Func<TimeZoneInfo> zone;
    private readonly object gate=new();
    private readonly object aggregationGate=new();
    private readonly CancellationTokenSource lifetime=new();
    private readonly Dictionary<string,RetainedHistory> records=new();
    private readonly Dictionary<string,string?> notices=new();
    private readonly Dictionary<string,ProviderHistory> summaries=new();
    private DemoDay[] days=[];
    private Task? running;
    private Task<HistoryImportResult>? importing;
    private DateTimeOffset? attemptedAt;
    private bool disposed;
    internal event Action? Changed;
    internal HistoryCoordinator(ILocalLogScanner? scanner=null,UsageLedger? ledger=null,ModelPricing? pricing=null,Func<DateTimeOffset>? clock=null,Func<TimeZoneInfo>? zone=null)
    {
        this.scanner=scanner??new LocalLogScanner();this.ledger=ledger??new UsageLedger();this.pricing=pricing??new ModelPricing();this.clock=clock??(()=>DateTimeOffset.UtcNow);this.zone=zone??(()=>TimeZoneInfo.Local);
    }
    internal ProviderHistory? State(string provider){lock(gate)return summaries.GetValueOrDefault(provider);}
    internal DemoDay[] Days{get{lock(gate)return days;}}
    internal bool Loading{get{lock(gate)return running!=null||importing!=null;}}
    internal bool HasEvidence{get{lock(gate)return summaries.Values.Any(s=>s.HasEvidence);}}
    internal Task<HistoryImportResult> ImportAsync(string path)
    {
        lock(gate){ObjectDisposedException.ThrowIf(disposed,this);if(importing!=null)throw new InvalidOperationException("A usage-history import is already running.");return importing=ImportRunAsync(path,running);}
    }
    private async Task<HistoryImportResult> ImportRunAsync(string path,Task? pending)
    {
        await Task.Yield();Changed?.Invoke();
        try {
            if(pending!=null)await pending;
            var result=await Task.Run(()=>ledger.Import(path,clock()),lifetime.Token);
            await RunAsync(clock(),true);return result;
        }finally{lock(gate)importing=null;if(!disposed)Changed?.Invoke();}
    }
    internal Task<bool> BackupAsync(string path)=>Task.Run(()=>ledger.CopyDatabase(path),lifetime.Token);
    internal Task RefreshAsync(bool manual=false,int intervalSeconds=300)
    {
        lock(gate) {
            if(disposed)return Task.CompletedTask;if(importing!=null)return importing;if(running!=null)return running;
            var now=clock();
            if(!manual&&attemptedAt!=null&&now-attemptedAt<TimeSpan.FromSeconds(Math.Max(300,intervalSeconds)))return Task.CompletedTask;
            attemptedAt=now;return running=RunAsync(now,manual);
        }
    }
    private async Task RunAsync(DateTimeOffset observedAt,bool manual)
    {
        await Task.Yield();Changed?.Invoke();
        try {
            var prices=pricing.RefreshAsync(observedAt,manual);
            await Task.WhenAll(Sources.Select(source=>Task.Run(()=>{
                lifetime.Token.ThrowIfCancellationRequested();
                HistoryScan scan;
                try{scan=scanner.Scan(source,observedAt,lifetime.Token);}
                catch(Exception e) when(e is System.IO.IOException or UnauthorizedAccessException or ArgumentException){scan=new([],UnreadableFiles:1);}
                lifetime.Token.ThrowIfCancellationRequested();
                var retained=ledger.Retain(source,scan.Events,observedAt,clock());
                lock(gate) {
                    if(disposed)return;
                    records[source]=retained;notices[source]=retained.SaveError??scan.Notice;
                }
                Rebuild(source=="opencode"?["claude","codex"]:[source]);
                Changed?.Invoke();
            },lifetime.Token)));
            if(await prices) {
                await Task.Run(()=>Rebuild(Providers),lifetime.Token);
                if(!disposed)Changed?.Invoke();
            }
        }catch(OperationCanceledException){}
        finally{lock(gate)running=null;if(!disposed)Changed?.Invoke();}
    }
    private void Rebuild(string[] providers)
    {
        lock(aggregationGate) {
            Dictionary<string,RetainedHistory> saved;Dictionary<string,string?> warnings;Dictionary<string,ProviderHistory> next;
            lock(gate){if(disposed)return;saved=new(records);warnings=new(notices);next=new(summaries);}
            var now=clock();var timeZone=zone();
            foreach(string provider in providers) {
                var native=saved.GetValueOrDefault(provider)?.Events??[];
                var open=provider is "claude" or "codex"?saved.GetValueOrDefault("opencode")?.Events??[]:[];
                string? notice=warnings.GetValueOrDefault(provider)??(provider is "claude" or "codex"?warnings.GetValueOrDefault("opencode"):null);
                next[provider]=HistorySummary.Build(provider,native.Concat(open),pricing,now,timeZone,notice,saved.GetValueOrDefault(provider)?.HistoricalDays);
            }
            var map=new Dictionary<DateTime,DemoDay>();
            foreach(var summary in next.Values)foreach(var day in summary.Days) {
                if(!map.TryGetValue(day.Date,out var item))map[day.Date]=item=new(day.Date,new(),new(),new(),new(),new());
                item.Tokens[summary.Id]=day.Tokens;item.BillableTokens[summary.Id]=day.BillableTokens;item.Dollars[summary.Id]=day.Dollars;item.UnpricedTokens![summary.Id]=day.UnpricedTokens;
                item.RecoveredTokens![summary.Id]=day.RecoveredTokens;
            }
            var updatedDays=map.OrderBy(p=>p.Key).Select(p=>p.Value).ToArray();
            lock(gate){if(disposed)return;foreach(var item in next)summaries[item.Key]=item.Value;days=updatedDays;}
        }
    }
    public void Dispose(){lock(gate){if(disposed)return;disposed=true;lifetime.Cancel();}pricing.Dispose();}
}

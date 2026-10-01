using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace IslandPrototype;

internal enum UsageStatus { NotConnected, Ready, Expired, NeedsLogin, RateLimited, Offline, AccessDenied, InvalidResponse, CredentialUnavailable, Unsupported, Cached }
internal sealed record LiveWindow(string Label,double? Used,DateTimeOffset? ResetAt,string? Id=null,string GroupId="default",string? GroupLabel=null,int Kind=3,double? SpanSeconds=null,DateTimeOffset? RetainUntil=null)
{
    internal string MetricId=>Id??Label;
}
internal sealed record UsageResult(UsageStatus Status,LiveWindow[] Windows,string? Plan=null,string? AccountKey=null,TimeSpan? RetryAfter=null,CodexResetCredits? ResetCredits=null);
internal sealed record LiveProviderState(string Id,UsageStatus Status,LiveWindow[] Windows,string? Plan=null,string? AccountKey=null,
    DateTimeOffset? UpdatedAt=null,DateTimeOffset? AttemptedAt=null,DateTimeOffset? RetryAt=null,bool Loading=false,CodexResetCredits? ResetCredits=null,bool FromHistory=false)
{
    internal string Message=>Loading?"Refreshing usage…":Status switch {
        UsageStatus.Ready=>Windows.Any(w=>w.Used!=null)?"Connected":Id is "grok" or "antigravity"&&string.Equals(Plan?.Trim(),"free",StringComparison.OrdinalIgnoreCase)?"No active subscription":"Usage limits are not available yet.",
        UsageStatus.NotConnected=>"Not connected. Sign in to see your usage.",
        UsageStatus.Expired=>"Your session expired. Sign in again to reconnect.",
        UsageStatus.NeedsLogin=>"Sign in again to restore usage access.",
        UsageStatus.RateLimited=>"Rate limited. Retrying later.",
        UsageStatus.Offline=>"Could not refresh. Check your connection.",
        UsageStatus.AccessDenied=>"Usage access was denied.",
        UsageStatus.InvalidResponse=>"Usage response could not be read.",
        UsageStatus.Cached=>"Showing the last saved reading.",
        UsageStatus.CredentialUnavailable=>"CLI credentials could not be read.",
        _=>"This CLI credential storage is not supported yet."
    };
    internal LiveWindow[] VisibleWindows(DateTimeOffset now)=>Windows.Select(w=>w.ResetAt<=now||w.RetainUntil<=now?w with {Used=null}:w).ToArray();
}

internal interface IUsageClient
{
    Task<UsageResult> FetchAsync(string provider,CancellationToken cancellation);
}
internal interface IUsageAccountReader
{
    Task<string?> ReadAccountKeyAsync(string provider,CancellationToken cancellation);
}

internal sealed class LiveUsageCoordinator : IDisposable
{
    private readonly object gate=new();
    private readonly IUsageClient client;
    private readonly Func<DateTimeOffset> clock;
    private readonly QuotaHistoryStore? quotaHistory;
    private readonly Dictionary<string,LiveProviderState> states=new();
    private string[] selected=[];
    private bool observeAccounts;
    private CancellationTokenSource? cancellation;
    private Task? running;
    private int generation;
    private bool disposed;
    private bool suspended,wakePending;
    private bool? networkAvailable;
    private DateTimeOffset? wakeGraceUntil;
    private readonly HashSet<string> pendingRecovery=new();
    internal event Action? Changed;
    internal LiveUsageCoordinator(IUsageClient client,Func<DateTimeOffset>? clock=null,QuotaHistoryStore? quotaHistory=null)
    {
        this.client=client;this.clock=clock??(()=>DateTimeOffset.UtcNow);this.quotaHistory=quotaHistory;
        foreach(string id in new[]{"claude","codex","grok","antigravity"})
            states[id]=new(id,UsageStatus.NotConnected,[]);
    }
    internal LiveProviderState State(string id){lock(gate)return states[id];}
    internal bool Loading {get {lock(gate)return selected.Any(id=>states[id].Loading);}}
    internal bool HasUpdated {get {lock(gate)return selected.Any(id=>states[id].UpdatedAt!=null&&!states[id].FromHistory);}}
    internal QuotaSample[] Samples(string id,string group,string metric)=>quotaHistory?.Samples(id,State(id).AccountKey,group,metric,clock())??[];
    internal string? QuotaHistoryError=>quotaHistory?.Error;
    internal bool InWakeGrace {get{lock(gate)return wakeGraceUntil>clock();}}
    internal DateTimeOffset? AutomaticRetryAt {
        get {lock(gate) {
            if(disposed||suspended)return null;
            var now=clock();var dates=new List<DateTimeOffset>();
            foreach(string id in ActiveProviders().Concat(pendingRecovery).Distinct())
                if(states[id].RetryAt is DateTimeOffset retry)dates.Add(retry);
            if(wakePending)dates.Add(wakeGraceUntil??now);
            foreach(string id in pendingRecovery)dates.Add(states[id].RetryAt is DateTimeOffset retry&&retry>now?retry:now);
            if(dates.Count==0)return null;
            var first=dates.Min();return wakeGraceUntil is DateTimeOffset grace&&first<grace?grace:first;
        }}
    }
    private string[] ActiveProviders()=>observeAccounts?states.Keys.ToArray():selected;
    internal void ObserveAccounts(bool observe){lock(gate){if(observeAccounts==observe)return;observeAccounts=observe;}Changed?.Invoke();}
    internal Task WaitForRefreshAsync(){lock(gate)return running??Task.CompletedTask;}
    private void CancelActive()
    {
        generation++;cancellation?.Cancel();cancellation=null;running=null;
        foreach(string id in states.Keys.ToArray())states[id]=states[id] with {Loading=false};
    }
    private void PreserveInterruptedRequests()
    {
        foreach(var state in states.Values)if(state.Loading)pendingRecovery.Add(state.Id);
    }
    internal void Suspend()
    {
        lock(gate){if(disposed||suspended)return;suspended=true;wakePending=false;wakeGraceUntil=null;PreserveInterruptedRequests();CancelActive();}
        Changed?.Invoke();
    }
    internal void Resume()
    {
        lock(gate){if(disposed)return;suspended=false;wakePending=true;wakeGraceUntil=clock()+WakeScheduling.GraceDelay;PreserveInterruptedRequests();CancelActive();}
        Changed?.Invoke();
    }
    internal Task NetworkChangedAsync(bool available,int intervalSeconds=300)
    {
        lock(gate) {
            if(disposed)return Task.CompletedTask;
            bool recovered=networkAvailable==false&&available;networkAvailable=available;
            if(!recovered||suspended||wakeGraceUntil>clock())return Task.CompletedTask;
            foreach(string id in ActiveProviders())pendingRecovery.Add(id);
            PreserveInterruptedRequests();CancelActive();
        }
        Changed?.Invoke();return RefreshAsync(false,intervalSeconds);
    }
    internal Task RefreshAfterCredentialsAsync(string provider)
    {
        lock(gate){if(disposed||!states.ContainsKey(provider))return Task.CompletedTask;pendingRecovery.Add(provider);}
        Changed?.Invoke();return RefreshAsync(only:[provider]);
    }
    internal void Select(string[] providers)
    {
        lock(gate) {
            if(disposed)return;
            string[] next=providers.Where(states.ContainsKey).Distinct().ToArray();
            if(selected.SequenceEqual(next))return;
            selected=next;CancelActive();
        }
        Changed?.Invoke();
    }
    internal Task RefreshAsync(bool manual=false,int intervalSeconds=300,string[]? only=null)
    {
        Task task;
        lock(gate) {
            if(disposed||suspended)return Task.CompletedTask;
            var now=clock();
            if(!manual&&wakeGraceUntil>now)return Task.CompletedTask;
            if(running!=null)return running;
            if(!manual)wakePending=false;
            string[] due=(only??ActiveProviders()).Concat(pendingRecovery).Distinct().Where(states.ContainsKey).Where(id=>
                (states[id].RetryAt==null||states[id].RetryAt<=now)&&
                (manual||pendingRecovery.Contains(id)||states[id].RetryAt<=now||states[id].AttemptedAt==null||now-states[id].AttemptedAt>=TimeSpan.FromSeconds(Math.Max(300,intervalSeconds)))).ToArray();
            if(due.Length==0)return Task.CompletedTask;
            foreach(string id in due)pendingRecovery.Remove(id);
            cancellation=new CancellationTokenSource();
            foreach(string id in due)states[id]=states[id] with {Loading=true};
            task=running=RunAsync(due,generation,cancellation);
        }
        Changed?.Invoke();return task;
    }
    private async Task RunAsync(string[] providers,int epoch,CancellationTokenSource source)
    {
        await Task.Yield();
        try {
            if(quotaHistory!=null&&client is IUsageAccountReader accountReader) {
                string[] uninitialized;lock(gate)uninitialized=providers.Where(id=>states[id].UpdatedAt==null).ToArray();
                var saved=await Task.WhenAll(uninitialized.Select(async id=>{
                    string? account=await accountReader.ReadAccountKeyAsync(id,source.Token);
                    var snapshot=account==null?null:await Task.Run(()=>quotaHistory.Latest(id,account,clock()),source.Token);
                    return (Id:id,Snapshot:snapshot);
                }));
                bool seeded=false;
                lock(gate) {
                    if(disposed||epoch!=generation||source.IsCancellationRequested)return;
                    foreach(var item in saved)if(states[item.Id].UpdatedAt==null&&item.Snapshot is QuotaAccount snapshot&&snapshot.Windows.Any(w=>w.Used!=null)) {
                        states[item.Id]=states[item.Id] with {Status=UsageStatus.Cached,Windows=snapshot.Windows,Plan=snapshot.Plan,AccountKey=snapshot.AccountKey,UpdatedAt=snapshot.At,FromHistory=true};seeded=true;
                    }
                }
                if(seeded)Changed?.Invoke();
            }
            var results=await Task.WhenAll(providers.Select(async id=>(Id:id,Result:await client.FetchAsync(id,source.Token))));
            DateTimeOffset now=clock();
            lock(gate) {
                if(disposed||epoch!=generation||source.IsCancellationRequested)return;
                foreach(var item in results)states[item.Id]=Merge(states[item.Id],item.Result,now);
            }
            if(quotaHistory!=null)await Task.Run(()=>{foreach(var item in results)quotaHistory.Record(item.Id,item.Result,now);},source.Token);
        } catch(OperationCanceledException) { }
        finally {
            bool publish;
            lock(gate) {
                publish=!disposed&&epoch==generation;
                if(publish) {
                    foreach(string id in providers)states[id]=states[id] with {Loading=false};
                    running=null;if(cancellation==source)cancellation=null;
                }
            }
            source.Dispose();if(publish)Changed?.Invoke();
        }
    }
    internal static LiveProviderState Merge(LiveProviderState previous,UsageResult next,DateTimeOffset now)
    {
        bool sameAccount=next.AccountKey!=null&&next.AccountKey==previous.AccountKey;
        bool transient=next.Status is UsageStatus.Offline or UsageStatus.RateLimited or UsageStatus.AccessDenied or UsageStatus.InvalidResponse
            ||previous.Id=="codex"&&next.Status==UsageStatus.Expired;
        LiveWindow[] windows=next.Status==UsageStatus.Ready?next.Windows:transient&&sameAccount?previous.VisibleWindows(now):[];
        var retry=next.Status==UsageStatus.RateLimited||next.RetryAfter!=null?now+TimeSpan.FromSeconds(Math.Min((DateTimeOffset.MaxValue-now).TotalSeconds,Math.Max(910,next.RetryAfter?.TotalSeconds??0))):(DateTimeOffset?)null;
        return new(previous.Id,next.Status,windows,next.Plan??(sameAccount?previous.Plan:null),next.AccountKey,
            next.Status==UsageStatus.Ready?now:sameAccount?previous.UpdatedAt:null,now,retry,
            ResetCredits:next.ResetCredits??(sameAccount&&(transient||next.Status==UsageStatus.Ready)?previous.ResetCredits:null),
            FromHistory:next.Status!=UsageStatus.Ready&&sameAccount&&previous.FromHistory);
    }
    public void Dispose()
    {
        lock(gate){if(disposed)return;disposed=true;generation++;cancellation?.Cancel();cancellation=null;running=null;}
        if(client is IDisposable disposable)disposable.Dispose();
    }
}

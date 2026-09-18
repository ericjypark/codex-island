using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.Threading;

namespace IslandPrototype;

internal sealed class UsageFeed : IDisposable
{
    private DemoProvider[] providers=ParityData.Providers;
    private readonly DemoDay[] demoDays=ParityData.Days.ToArray();
    private readonly LiveUsageCoordinator? live;
    private readonly HistoryCoordinator? history;
    private readonly Dictionary<string,string> connectionRefreshes=new();
    internal IslandPreferences Preferences {get;set;}=new();
    internal string QuotaScope(string id)=>id+":"+(State(id)?.AccountKey??"local-session");
    internal ProviderQuotaSelection QuotaSelection(string id)=>Preferences.QuotaSelections.GetValueOrDefault(QuotaScope(id))??new();
    internal LiveWindow[] DisplayedWindows(string id)
    {
        var windows=State(id)?.VisibleWindows(DateTimeOffset.UtcNow)??[];
        return id is "grok" or "antigravity"?ProviderQuotaSelection.Resolve(windows,QuotaSelection(id)):windows;
    }
    internal UsageFeed(LiveUsageCoordinator? live=null,HistoryCoordinator? history=null){this.live=live;this.history=history;if(live!=null)live.Changed+=OnLiveChanged;if(history!=null)history.Changed+=OnLiveChanged;}
    private long revision;
    internal long Revision=>Interlocked.Read(ref revision);
    private void OnLiveChanged(){Interlocked.Increment(ref revision);Changed?.Invoke();}
    internal event Action? Changed;
    internal IEnumerable<DemoProvider> Providers=>providers.Select(p=>Provider(p.Id));
    internal DemoProvider Provider(string id)
    {
        var provider=providers.First(p=>p.Id==id);
        if(live==null)return provider;
        var state=live.State(id);var now=DateTimeOffset.UtcNow;
        var costs=history?.State(id);
        CostMetric[] values=costs?.HasEvidence==true?new[]{costs.Today,costs.Month}.Select((c,i)=>new CostMetric(i==0?"Today":DateTime.Now.ToString("MMM",Localizer.Culture),c.Dollars,c.Tokens,c.Series,c.BillableTokens,c.UnpricedTokens)).ToArray():[];
        var windows=DisplayedWindows(id);string? primary=QuotaSelection(id).PrimaryId??windows.FirstOrDefault()?.MetricId;
        return provider with {Plan=state.Plan??"",Costs=values,Limits=windows.Select((w,i)=>
            new UsageMetric(w.Label,w.Used,w.ResetAt is DateTimeOffset reset?ParityData.Duration((reset-now).TotalSeconds):"--",i,w.ResetAt,w.MetricId==primary,state.AccountKey==null?null:live.Samples(id,w.GroupId,w.MetricId).Select(p=>p.Used).ToArray())).ToArray()};
    }
    internal LiveProviderState? State(string id)=>live?.State(id);
    internal bool HasUpdated=>live?.HasUpdated??true;
    internal bool IsDemo=>live==null;
    internal bool Loading=>live?.Loading??false;
    internal string? QuotaHistoryError=>live?.QuotaHistoryError;
    internal bool InWakeGrace=>live?.InWakeGrace??false;
    internal DateTimeOffset? AutomaticRetryAt=>live?.AutomaticRetryAt;
    internal void Suspend()=>live?.Suspend();
    internal void Resume()=>live?.Resume();
    internal Task NetworkChangedAsync(bool available,int intervalSeconds)=>live?.NetworkChangedAsync(available,intervalSeconds)??Task.CompletedTask;
    internal ProviderHistory? History(string id)=>history?.State(id);
    internal DemoDay[] Days=>IsDemo?demoDays:history?.Days??[];
    internal bool HasHistory=>IsDemo||history?.HasEvidence==true;
    internal bool HistoryLoading=>history?.Loading??false;
    internal bool CanManageHistory=>!IsDemo&&history!=null;
    internal Task<HistoryImportResult> ImportHistoryAsync(string path)=>history?.ImportAsync(path)??throw new InvalidOperationException("Switch to live data to import usage history.");
    internal Task<bool> BackupHistoryAsync(string path)=>history?.BackupAsync(path)??Task.FromResult(false);
    internal void Select(string[] ids)=>live?.Select(ids);
    internal void ObserveAccounts(bool observe)=>live?.ObserveAccounts(observe);
    internal async Task RefreshAfterSignInAsync(string? provider=null)
    {
        if(live==null)return;
        await live.WaitForRefreshAsync();
        if(provider==null)await RefreshAsync(true);
        else {
            string stamp=new FileCliCredentials().ChangeStamp(provider);
            if(connectionRefreshes.GetValueOrDefault(provider)==stamp)return;
            connectionRefreshes[provider]=stamp;
            await Task.WhenAll(live.RefreshAfterCredentialsAsync(provider),history?.RefreshAsync(true)??Task.CompletedTask);
        }
    }
    internal Task RefreshAsync(bool manual=false,int intervalSeconds=300)
    {
        if(live!=null)return Task.WhenAll(live.RefreshAsync(manual,intervalSeconds),history?.RefreshAsync(manual,intervalSeconds)??Task.CompletedTask);
        Reset();return Task.CompletedTask;
    }
    internal Task RefreshPageAsync(int page,int intervalSeconds=300)
    {
        if(IsDemo){Reset();return Task.CompletedTask;}
        return page==0?live!.RefreshAsync(true,intervalSeconds):history?.RefreshAsync(true,intervalSeconds)??Task.CompletedTask;
    }
    internal static UsageMetric? Primary(DemoProvider provider)
    {
        if(provider.Id=="claude")return provider.Limits.FirstOrDefault(m=>m.Label=="5h");
        if(provider.Id=="codex") {
            var five=provider.Limits.FirstOrDefault(m=>m.Label=="5h");
            if(five?.Used!=null||provider.Limits.Length==1&&five!=null)return five;
            return provider.Limits.FirstOrDefault(m=>m.Label=="week")??five;
        }
        return provider.Limits.FirstOrDefault(w=>w.IsPrimary==true)??(provider.Limits.Any(w=>w.IsPrimary.HasValue)?null:provider.Limits.FirstOrDefault());
    }
    internal void Reset(){if(live!=null)return;providers=ParityData.Providers;OnLiveChanged();}
    internal void Preview(string[] selected,string mode)
    {
        if(live!=null)return;
        var values=mode switch {"Warn"=>new[]{85.0,55.0},"Crit"=>new[]{96.0,55.0},_=>new[]{86.0,97.0}};
        DateTimeOffset reset=DateTimeOffset.Now.AddHours(5);
        providers=providers.Select(provider=>{
            int index=Array.IndexOf(selected,provider.Id);
            if(index<0)return provider;
            var primary=Primary(provider);
            return provider with {Limits=provider.Limits.Select(metric=>metric==primary
                ?metric with {Used=values[Math.Min(index,1)],Reset="4h",ResetAt=reset}:metric).ToArray()};
        }).ToArray();
        OnLiveChanged();
    }
    public void Dispose(){if(live!=null){live.Changed-=OnLiveChanged;live.Dispose();}if(history!=null){history.Changed-=OnLiveChanged;history.Dispose();}}
}

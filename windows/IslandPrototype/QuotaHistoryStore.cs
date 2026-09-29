using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace IslandPrototype;

internal sealed record QuotaSample(DateTimeOffset At,double Used);
internal sealed record QuotaSeries(string GroupId,string MetricId,QuotaSample[] Samples);
internal sealed record QuotaAccount(string Provider,string AccountKey,DateTimeOffset At,string? Plan,LiveWindow[] Windows,QuotaSeries[] Series);
internal sealed record QuotaHistoryFile(int SchemaVersion,QuotaAccount[] Accounts);

internal sealed class QuotaHistoryStore(string? path=null)
{
    private const int MaxAccounts=16,MaxSeries=128,MaxSamples=1000,MaxBytes=16*1024*1024;
    private readonly object gate=new();
    private volatile QuotaAccount[] accounts=[];
    private volatile bool loaded;
    private bool preserveUnreadable,readOnly;
    internal string? Error {get;private set;}
    internal QuotaAccount? Latest(string provider,string? account,DateTimeOffset now)
    {
        lock(gate) {
            Load();
            var saved=accounts.FirstOrDefault(a=>a.Provider==provider&&a.AccountKey==account);
            if(saved==null||saved.At>now||now-saved.At>TimeSpan.FromDays(7))return null;
            var windows=saved.Windows.Select(window=>{
                double? span=window.SpanSeconds??(window.Label=="5h"?18000:window.Label=="week"?604800:window.Label=="month"?2678400:(double?)null);
                DateTimeOffset? until=span is >0?saved.At.AddSeconds(span.Value):null;
                if(window.ResetAt is DateTimeOffset reset)until=until==null||reset<until?reset:until;
                bool usable=window.Used!=null&&until>now;
                return window with {Used=usable?window.Used:null,RetainUntil=until};
            }).ToArray();
            return saved with {Windows=windows,Series=[]};
        }
    }
    internal QuotaSample[] Samples(string provider,string? account,string group,string metric,DateTimeOffset now)
    {
        if(!loaded)return [];
        return accounts.FirstOrDefault(a=>a.Provider==provider&&a.AccountKey==account)?.Series
            .FirstOrDefault(s=>s.GroupId==group&&s.MetricId==metric)?.Samples.Where(s=>s.At>=now.AddDays(-7)&&s.At<=now).ToArray()??[];
    }
    internal void Record(string provider,UsageResult result,DateTimeOffset at)
    {
        if(result.Status!=UsageStatus.Ready||!ValidProvider(provider)||!ValidAccount(result.AccountKey))return;
        lock(gate) {
            Load();
            string account=result.AccountKey!;
            var old=accounts.FirstOrDefault(a=>a.Provider==provider&&a.AccountKey==account);
            var series=(old?.Series??[]).ToDictionary(s=>(s.GroupId,s.MetricId));
            var windows=result.Windows.Where(ValidWindow).DistinctBy(w=>(w.GroupId,w.MetricId)).Take(512).Select(w=>w with {RetainUntil=null}).ToArray();
            foreach(var window in windows) {
                if(window.Used is not double used||!double.IsFinite(used)||used<0||used>100)continue;
                var key=(window.GroupId,window.MetricId);
                var samples=(series.GetValueOrDefault(key)?.Samples??[]).Where(s=>s.At!=at&&s.At>=at.AddDays(-7))
                    .Append(new QuotaSample(at,used)).OrderBy(s=>s.At).TakeLast(MaxSamples).ToArray();
                series[key]=new(window.GroupId,window.MetricId,samples);
            }
            var next=new QuotaAccount(provider,account,at,result.Plan?.Length<=256?result.Plan:null,windows,
                series.Values.Select(s=>s with {Samples=s.Samples.Where(p=>p.At>=at.AddDays(-7)).ToArray()}).Where(s=>s.Samples.Length>0).ToArray());
            accounts=accounts.Where(a=>(a.Provider!=provider||a.AccountKey!=account)&&a.At>=at.AddDays(-7)).Append(next)
                .OrderByDescending(a=>a.At).Take(MaxAccounts).ToArray();
            int left=MaxSeries;
            accounts=accounts.Select(a=>{
                var kept=a.Series.OrderByDescending(s=>s.Samples.LastOrDefault()?.At).Take(left).ToArray();left-=kept.Length;
                return a with {Series=kept};
            }).ToArray();
            Save();
        }
    }
    private void Load()
    {
        if(loaded)return;loaded=true;
        if(path==null||!File.Exists(path))return;
        try {
            using var file=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete);
            if(file.Length>MaxBytes)throw new InvalidDataException();
            using var bytes=new MemoryStream();var buffer=new byte[8192];int count;
            while((count=file.Read(buffer))>0){if(bytes.Length+count>MaxBytes)throw new InvalidDataException();bytes.Write(buffer,0,count);}
            var saved=JsonSerializer.Deserialize<QuotaHistoryFile>(bytes.ToArray())??throw new InvalidDataException();
            if(saved.SchemaVersion>1){readOnly=true;Error="Recent quota history uses a newer format. The saved file has been preserved.";return;}
            if(saved.SchemaVersion!=1||saved.Accounts==null||saved.Accounts.Length>MaxAccounts||saved.Accounts.Sum(a=>a?.Series?.Length??0)>MaxSeries)throw new InvalidDataException();
            if(saved.Accounts.Any(a=>a==null||!ValidProvider(a.Provider)||!ValidAccount(a.AccountKey)||a.Plan?.Length>256||a.Windows==null||a.Windows.Length>512||a.Windows.Any(w=>w==null||!ValidWindow(w))
                ||a.Windows.Select(w=>(w.GroupId,w.MetricId)).Distinct().Count()!=a.Windows.Length
                ||a.Series==null||a.Series.Any(s=>s==null||!ValidText(s.GroupId)||!ValidText(s.MetricId)||s.Samples==null||s.Samples.Length>MaxSamples
                    ||s.Samples.Any(p=>p==null||!double.IsFinite(p.Used)||p.Used<0||p.Used>100)||s.Samples.Zip(s.Samples.Skip(1)).Any(p=>p.First.At>=p.Second.At))
                ||a.Series.Select(s=>(s.GroupId,s.MetricId)).Distinct().Count()!=a.Series.Length)
                ||saved.Accounts.Select(a=>(a.Provider,a.AccountKey)).Distinct().Count()!=saved.Accounts.Length)throw new InvalidDataException();
            accounts=saved.Accounts;
        }catch(Exception error)when(error is IOException or InvalidDataException or UnauthorizedAccessException or JsonException or ArgumentException) {
            preserveUnreadable=true;Error="Recent quota history could not be read. The original file has been preserved.";
        }
    }
    private void Save()
    {
        if(path==null||readOnly)return;
        string temporary=path+"."+Guid.NewGuid().ToString("N")+".tmp";
        try {
            byte[] bytes=JsonSerializer.SerializeToUtf8Bytes(new QuotaHistoryFile(1,accounts));
            if(bytes.Length>MaxBytes)throw new InvalidDataException();
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
            if(preserveUnreadable&&File.Exists(path))File.Copy(path,path+".recovery-"+Guid.NewGuid().ToString("N"),false);
            File.WriteAllBytes(temporary,bytes);File.Move(temporary,path,true);preserveUnreadable=false;Error=null;
        }catch(Exception error)when(error is IOException or InvalidDataException or UnauthorizedAccessException or JsonException or ArgumentException) {
            Error="Recent quota history could not be saved. Current readings are still available.";
        }finally {
            try{File.Delete(temporary);}catch(Exception error)when(error is IOException or UnauthorizedAccessException){}
        }
    }
    private static bool ValidProvider(string provider)=>provider is "codex" or "claude" or "grok" or "antigravity";
    private static bool ValidAccount(string? account)=>account?.Length==64&&account.All(Uri.IsHexDigit);
    private static bool ValidText(string? value)=>!string.IsNullOrWhiteSpace(value)&&value.Length<=512;
    private static bool ValidWindow(LiveWindow w)=>ValidText(w.Label)&&ValidText(w.GroupId)&&ValidText(w.MetricId)&&(w.GroupLabel==null||w.GroupLabel.Length<=512)
        &&(w.Used==null||double.IsFinite(w.Used.Value)&&w.Used>=0&&w.Used<=100)&&(w.SpanSeconds==null||double.IsFinite(w.SpanSeconds.Value)&&w.SpanSeconds>0&&w.SpanSeconds<=2678400);
}

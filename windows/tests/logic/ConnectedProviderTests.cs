using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using IslandPrototype;

internal static class ConnectedProviderTests
{
    private const string Weekly="""{"config":{"creditUsagePercent":42.5,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2099-01-08T00:00:00Z"},"onDemandUsed":{"val":25},"onDemandCap":{"val":100}}}""";
    private const string Monthly="""{"config":{"monthlyLimit":{"val":"2000"},"used":{"val":"500"},"billingPeriodEnd":"2099-02-01T00:00:00Z"}}""";
    private const string Groups="""{"groups":[{"displayName":"Gemini Models","buckets":[{"bucketId":"weekly","displayName":"Weekly Limit Remaining","remainingFraction":1},{"bucketId":"session","displayName":"Five Hour Limit Remaining","remainingFraction":0.75}]}]}""";
    private static UsageResult Parse(string provider,string json){using var doc=JsonDocument.Parse(json);return provider=="grok"?ConnectedProviderUsage.ParseGrok(doc.RootElement):ConnectedProviderUsage.ParseAntigravity(doc.RootElement);}
    internal static async Task Run(Action<string,bool> check)
    {
        var now=DateTimeOffset.UtcNow;
        var weekly=Parse("grok",Weekly);var monthly=Parse("grok",Monthly);
        check("Grok weekly subscription excludes extra spending",weekly.Windows is [{Label:"week",Used:42.5,Kind:1}]);
        check("Grok monthly allowance accepts decimal strings",monthly.Windows is [{Label:"month",Used:25}]&&monthly.Windows[0].ResetAt?.Year==2099);
        check("Extra spending and zero-cap plans do not invent quota",new[]{"{\"config\":{\"onDemandUsed\":{\"val\":25},\"onDemandCap\":{\"val\":100}}}","{\"config\":{\"monthlyLimit\":{\"val\":0},\"used\":{\"val\":0}}}"}.All(json=>Parse("grok",json).Windows.All(w=>w.Used==null)));
        check("A real zero Grok reading remains available",Parse("grok","{\"config\":{\"creditUsagePercent\":0}}").Windows is [{Used:0}]);
        var group=Parse("antigravity",Groups);
        check("Antigravity remaining fractions become used percentages",group.Windows is [{Label:"week",Used:0},{Label:"5h",Used:25}]);
        var alternate=Parse("antigravity","""{"response":{"groups":[{"groupId":"g","displayName":"Gemini","buckets":[{"bucketId":"session","remaining":{"case":"remainingFraction","value":0.2}},{"bucketId":"hidden","disabled":true,"remainingFraction":1},{"bucketId":"missing"}]}]}}""");
        check("Nested Antigravity quotas preserve missing readings and skip disabled buckets",alternate.Windows.Length==2&&Math.Abs(alternate.Windows[0].Used!.Value-80)<.001&&alternate.Windows[1].Used==null);
        check("Invalid Antigravity fractions stay unknown",Parse("antigravity","""{"groups":[{"buckets":[{"remainingFraction":2}]}]}""").Windows is [{Used:null}]);
        check("Malformed Antigravity groups fail safely",Parse("antigravity","{\"groups\":{}}").Status==UsageStatus.InvalidResponse&&Parse("antigravity","{}").Status==UsageStatus.InvalidResponse);
        string grok="""{"https://accounts.x.ai/sign-in":{"key":"legacy"},"https://auth.x.ai::a":{"key":"expired","expires_at":"2000-01-01T00:00:00Z"},"https://auth.x.ai::b":{"key":"fresh","user_id":"fixture-user","expires_at":"2099-01-01T00:00:00Z"}}""";
        var credential=ProviderCredentialParser.Grok(grok,[],now);
        check("Grok prefers fresh current-issuer credentials over old and legacy entries",credential.Credential?.AccessToken=="fresh"&&credential.Credential.UserId=="fixture-user");
        check("Grok can fall back after a rejected current token",ProviderCredentialParser.Grok(grok,["fresh"],now).Credential?.AccessToken=="legacy");
        check("Expired Grok credentials cannot make a usage request",ProviderCredentialParser.Grok(grok,["fresh","legacy"],now).Status==UsageStatus.Expired);
        byte[] anti=Encoding.UTF8.GetBytes("{\"token\":{\"access_token\":\"fixture-only\",\"expiry\":\"2099-01-01T00:00:00Z\"}}");
        check("Native Antigravity JSON and the CLI base64 wrapper decode",ProviderCredentialParser.Antigravity(anti,[],now).Credential?.AccessToken=="fixture-only"&&ProviderCredentialParser.Antigravity(Encoding.UTF8.GetBytes("go-keyring-base64:"+Convert.ToBase64String(anti)),[],now).Credential?.AccessToken=="fixture-only");
        check("Antigravity excludes rejected tokens and malformed credential bytes",ProviderCredentialParser.Antigravity(anti,["fixture-only"],now).Credential==null&&ProviderCredentialParser.Antigravity([255],[],now).Status==UsageStatus.CredentialUnavailable);
        string root=Path.Combine(Path.GetTempPath(),"CodexIsland-WatchTests-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
        try {
            var fileSource=new FileCliCredentials(root,key=>key=="GROK_HOME"?root:null,()=>anti.ToArray());
            string before=fileSource.ChangeStamp("grok");File.WriteAllText(Path.Combine(root,"auth.json"),grok);
            check("Credential metadata detects a newly signed-in Grok account",fileSource.ChangeStamp("grok")!=before&&(await fileSource.ReadAsync("grok",[],default)).Credential?.AccessToken=="fresh");
            var stamps=new Dictionary<string,string>();var watch=new CliCredentialWatch(id=>stamps.GetValueOrDefault(id)??"missing");
            check("Unchanged credential metadata does not request polling",watch.ChangedProviders().Length==0);
            stamps["grok"]="new";check("Credential watch reports only the changed provider once",watch.ChangedProviders().SequenceEqual(new[]{"grok"})&&watch.ChangedProviders().Length==0);
        } finally {Directory.Delete(root,true);}
        CheckSelections(check,group.Windows);
        CheckNativeStore(check,anti);
        await CheckRequests(check);
        await CheckRenewal(check);
    }
    private static void CheckSelections(Action<string,bool> check,LiveWindow[] windows)
    {
        var all=windows.Concat(new[]{new LiveWindow("week",99,null,"other-week","aaa","Claude Models",1)}).ToArray();
        var defaults=ProviderQuotaSelection.Resolve(all,new());
        check("Default Antigravity selection prefers Gemini and orders session before week",defaults is [{Label:"5h",Used:25},{Label:"week",Used:0}]);
        var chosen=new ProviderQuotaSelection("Gemini Models",["weekly","session"],"weekly");
        check("Explicit metric order and primary are preserved",ProviderQuotaSelection.Resolve(all,chosen).Select(w=>w.MetricId).SequenceEqual(new[]{"weekly","session"}));
        var swapped=chosen.SelectMetric(ProviderQuotaSelection.Resolve(all,chosen),0,"session");
        check("Choosing an already displayed metric swaps slots",swapped.MetricIds!.SequenceEqual(new[]{"session","weekly"})&&swapped.PrimaryId=="weekly");
        check("Removing the primary metric resets the peek selection",swapped.SelectMetric(ProviderQuotaSelection.Resolve(all,swapped),1,"").PrimaryId==null);
        check("Missing selected metrics stay unavailable instead of showing another quota",ProviderQuotaSelection.Resolve(all,new("Gemini Models",["gone"])).Single().Used==null&&ProviderQuotaSelection.Resolve(all,new("gone")).Length==0);
        check("A missing explicit peek metric cannot silently choose another quota",UsageFeed.Primary(ParityData.Provider("antigravity") with {Limits=[new("week",95,"1d",0,IsPrimary:false)]})==null);
        var free=new LiveProviderState("grok",UsageStatus.Ready,[new("Credits",null,null)],"Free");
        check("Free missing quota is a subscription state while a real zero is connected",free.Message=="No active subscription"&&(free with {Windows=[new("Credits",0,null)]}).Message=="Connected");
    }
    private static async Task CheckRequests(Action<string,bool> check)
    {
        var credentials=new Credentials(()=>new(new CliCredential("fixture-token","fixture-account",userId:"fixture-user")));
        var paths=new List<string>();bool headers=true;
        using var handler=new Handler(async (request,_)=>{
            paths.Add(request.RequestUri!.PathAndQuery);
            headers&=request.Method==HttpMethod.Get&&request.RequestUri.Host=="cli-chat-proxy.grok.com"&&request.Headers.Authorization?.Parameter=="fixture-token"
                &&request.Headers.GetValues("x-userid").Single()=="fixture-user"&&request.Headers.GetValues("x-xai-token-auth").Single()=="xai-grok-cli"&&request.Headers.GetValues("x-grok-client-mode").Single()=="cli";
            await Task.CompletedTask;
            return Reply(200,request.RequestUri.Query.Length>0?"{\"config\":{\"isUnifiedBillingUser\":true}}":request.RequestUri.AbsolutePath.EndsWith("/billing")?Monthly:"{\"subscription_tier_display\":\"SuperGrok\"}");
        });
        using var http=new HttpClient(handler);using var client=new ProviderUsageClient(credentials,http,(_,_)=>Task.FromResult(false));
        var grok=await client.FetchAsync("grok",default);
        check("Grok monthly fallback sends exact CLI identity headers and routes",headers&&paths.SequenceEqual(new[]{"/v1/billing?format=credits","/v1/billing","/v1/settings"})&&grok.Windows is [{Used:25}]&&grok.Plan=="SuperGrok");
        handler.Next=(request,_)=>Task.FromResult(request.RequestUri!.Query.Length>0?Reply(200,Weekly.Replace("42.5,","42.5,\"isUnifiedBillingUser\":true,")):Reply(503));
        check("Grok retains a valid weekly quota when optional endpoints fail",(await client.FetchAsync("grok",default)).Windows is [{Used:42.5}]);
        handler.Next=(request,_)=>Task.FromResult(request.RequestUri!.Query.Length>0?Reply(200,"{\"config\":{}}"):Reply(503));
        check("Failed fallback without any quota reports the failure",(await client.FetchAsync("grok",default)).Status==UsageStatus.Offline);
        int calls=0;handler.Next=(request,_)=>{calls++;return Task.FromResult(request.RequestUri!.Query.Length>0?Reply(200,Weekly):Reply(429));};
        var limited=await client.FetchAsync("grok",default);
        check("An optional Grok rate limit retains usage with a cooldown",limited.Status==UsageStatus.Ready&&limited.RetryAfter?.TotalSeconds==910&&calls==2);
        var merged=LiveUsageCoordinator.Merge(new("grok",UsageStatus.Ready,[]),limited,DateTimeOffset.UtcNow);
        check("Successful partial responses still schedule the rate-limit delay",merged.RetryAt>merged.AttemptedAt?.AddMinutes(15));
        bool exact=true;calls=0;
        handler.Next=async (request,_)=>{
            calls++;string body=await request.Content!.ReadAsStringAsync();
            exact&=request.Method==HttpMethod.Post&&request.RequestUri!.Host=="daily-cloudcode-pa.googleapis.com"&&request.Headers.Authorization?.Parameter=="fixture-token"&&request.Headers.UserAgent.ToString()=="antigravity/1.1.25";
            if(request.RequestUri!.AbsolutePath.EndsWith("loadCodeAssist")){exact&=body=="{\"metadata\":{\"ideType\":\"ANTIGRAVITY\"}}";return Reply(200,"{\"cloudaicompanionProject\":\"fixture-project\",\"paidTier\":{\"name\":\"AI Pro\"}}");}
            exact&=body=="{\"project\":\"fixture-project\"}";return Reply(200,Groups);
        };
        var anti=await client.FetchAsync("antigravity",default);
        check("Antigravity resolves the project before requesting its exact quota backend",exact&&calls==2&&anti.Plan=="AI Pro"&&anti.AccountKey==new CliCredential("fixture-token","fixture-project").AccountKey);
        handler.Next=(_,_)=>Task.FromResult(Reply(503));
        check("Antigravity transient failures retain the known account identity",(await client.FetchAsync("antigravity",default)).AccountKey==anti.AccountKey);
        calls=0;handler.Next=(_,_)=>{calls++;return Task.FromResult(Reply(200,"{\"currentTier\":{\"name\":\"Free\"}}"));};
        check("A missing Antigravity project cannot issue an unscoped quota request",(await client.FetchAsync("antigravity",default)).Status==UsageStatus.InvalidResponse&&calls==1);
        foreach(int status in new[]{401,403,429}) {
            calls=0;handler.Next=(_,_)=>{calls++;return Task.FromResult(Reply(status));};
            UsageStatus expected=status==401?UsageStatus.Expired:status==403?UsageStatus.AccessDenied:UsageStatus.RateLimited;
            check("Antigravity HTTP "+status+" preserves its distinct provider state",(await client.FetchAsync("antigravity",default)).Status==expected&&calls==1);
        }
        handler.Next=(_,_)=>Task.FromResult(Reply(200,new string('x',2*1024*1024+1)));
        check("Connected provider responses have a bounded size",(await client.FetchAsync("grok",default)).Status==UsageStatus.InvalidResponse);
        using var cancellation=new CancellationTokenSource();cancellation.Cancel();bool canceled=false;
        try {await client.FetchAsync("grok",cancellation.Token);}catch(OperationCanceledException){canceled=true;}
        check("Provider requests propagate caller cancellation",canceled);
    }
    private static async Task CheckRenewal(Action<string,bool> check)
    {
        bool renewed=false;int renewals=0,calls=0;
        var credentials=new Credentials(()=>new(new CliCredential(renewed?"new":"old","same"),renewed?UsageStatus.NotConnected:UsageStatus.Expired));
        using var handler=new Handler((_,_)=>{calls++;return Task.FromResult(Reply(200,Weekly));});using var http=new HttpClient(handler);
        using var client=new ProviderUsageClient(credentials,http,(_,_)=>{renewals++;renewed=true;return Task.FromResult(true);});
        var result=await client.FetchAsync("grok",default);
        check("An expired Grok credential asks its CLI to renew then rereads the store",renewals==1&&result.Status==UsageStatus.Ready&&calls==2);
        handler.Next=(_,_)=>Task.FromResult(Reply(401));renewals=0;
        check("CLI renewal retries at most once when authentication is still rejected",(await client.FetchAsync("antigravity",default)).Status==UsageStatus.Expired&&renewals==1);
        handler.Next=(_,_)=>Task.FromResult(Reply(403));renewals=0;
        check("Access denial does not run CLI renewal",(await client.FetchAsync("grok",default)).Status==UsageStatus.AccessDenied&&renewals==0);
    }
    private static void CheckNativeStore(Action<string,bool> check,byte[] data)
    {
        string target="CodexIsland.Tests."+Guid.NewGuid().ToString("N");IntPtr bytes=Marshal.AllocHGlobal(data.Length);Marshal.Copy(data,0,bytes,data.Length);
        try {
            var record=new Credential {Type=1,Target=target,Size=(uint)data.Length,Blob=bytes,Persist=1,UserName="fixture"};
            if(!CredWrite(ref record,0))throw new InvalidOperationException("Test credential could not be created.");
            check("Windows native credential reader returns the fixture's exact UTF-8 bytes",WindowsCliCredential.Read(target)!.SequenceEqual(data));
            check("Repeated native credential reads preserve its payload",WindowsCliCredential.Read(target)!.SequenceEqual(data));
        } finally {CredDelete(target,1,0);Marshal.FreeHGlobal(bytes);}
        check("A missing Windows credential returns no session",WindowsCliCredential.Read(target)==null);
    }
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]
    private struct Credential {internal uint Flags,Type;internal string Target;internal string? Comment;internal long Written;internal uint Size;internal IntPtr Blob;internal uint Persist,AttributeCount;internal IntPtr Attributes;internal string? Alias,UserName;}
    [DllImport("advapi32.dll",EntryPoint="CredWriteW",CharSet=CharSet.Unicode,SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] private static extern bool CredWrite(ref Credential credential,uint flags);
    [DllImport("advapi32.dll",EntryPoint="CredDeleteW",CharSet=CharSet.Unicode)] [return:MarshalAs(UnmanagedType.Bool)] private static extern bool CredDelete(string target,uint type,uint flags);
    private static HttpResponseMessage Reply(int status,string body="")=>new((HttpStatusCode)status){Content=new StringContent(body)};
    private sealed class Credentials(Func<CredentialRead> value) : ICliCredentials
    {
        public Task<CredentialRead> ReadAsync(string provider,string[] excluded,CancellationToken cancellation){cancellation.ThrowIfCancellationRequested();var read=value();return Task.FromResult(read.Credential!=null&&excluded.Contains(read.Credential.AccessToken)?new CredentialRead(null):read);}
    }
    private sealed class Handler(Func<HttpRequestMessage,CancellationToken,Task<HttpResponseMessage>> next) : HttpMessageHandler
    {
        internal Func<HttpRequestMessage,CancellationToken,Task<HttpResponseMessage>> Next=next;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken cancellation)=>Next(request,cancellation);
    }
}

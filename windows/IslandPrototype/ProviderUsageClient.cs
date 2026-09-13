using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace IslandPrototype;

internal sealed class ProviderUsageClient : IUsageClient,IUsageAccountReader,IDisposable
{
    private readonly ICliCredentials credentials;
    private readonly HttpClient http;
    private readonly bool ownsClient;
    private readonly Func<string,CancellationToken,Task<bool>> renew;
    private readonly Func<CancellationToken,Task<UsageResult>>? codexAccountReader;
    private readonly Dictionary<string,string> antigravityAccounts=new();
    internal ProviderUsageClient(ICliCredentials credentials,HttpClient? http=null,Func<string,CancellationToken,Task<bool>>? renew=null,Func<CancellationToken,Task<UsageResult>>? codexAccountReader=null)
    {
        this.credentials=credentials;ownsClient=http==null;
        this.renew=renew??CliSessionRecovery.RenewAsync;
        this.codexAccountReader=codexAccountReader??(credentials is FileCliCredentials?CodexAccountReader.ReadAsync:null);
        this.http=http??new HttpClient(new HttpClientHandler {AllowAutoRedirect=false}) {Timeout=TimeSpan.FromSeconds(20)};
    }
    public async Task<UsageResult> FetchAsync(string provider,CancellationToken cancellation)
    {
        var result=await FetchStoredAsync(provider,cancellation);
        if(provider is "grok" or "antigravity"&&result.Status==UsageStatus.Expired) {
            cancellation.ThrowIfCancellationRequested();
            if(await renew(provider,cancellation))result=await FetchStoredAsync(provider,cancellation);
        }
        return result;
    }
    public async Task<string?> ReadAccountKeyAsync(string provider,CancellationToken cancellation)
    {
        if(provider=="antigravity")return null;
        var read=await credentials.ReadAsync(provider,[],cancellation);
        return read.Status==UsageStatus.Expired&&provider!="codex"?null:read.Credential?.AccountKey;
    }
    private async Task<UsageResult> FetchStoredAsync(string provider,CancellationToken cancellation)
    {
        if(provider is not ("codex" or "claude" or "grok" or "antigravity"))return new(UsageStatus.Unsupported,[]);
        var excluded=new List<string>();
        UsageResult? failed=null;
        for(int attempt=0;attempt<3;attempt++) {
            var read=await credentials.ReadAsync(provider,excluded.ToArray(),cancellation);
            if(provider=="codex"&&read.Status==UsageStatus.Unsupported&&codexAccountReader!=null)return await codexAccountReader(cancellation);
            if(read.Credential is not CliCredential credential)return failed??new UsageResult(read.Status,[]);
            if(read.Status==UsageStatus.Expired)return new(UsageStatus.Expired,[],credential.Plan,credential.AccountKey);
            var result=await RequestAsync(provider,credential,cancellation);
            if(result.Status is not (UsageStatus.Expired or UsageStatus.NeedsLogin))return result;
            if(failed?.Status!=UsageStatus.NeedsLogin)failed=result;
            excluded.Add(credential.AccessToken);
        }
        return failed??new UsageResult(UsageStatus.NotConnected,[]);
    }
    private async Task<UsageResult> RequestAsync(string provider,CliCredential credential,CancellationToken cancellation)
    {
        if(provider is "grok" or "antigravity") {
            var connected=await ConnectedProviderUsage.FetchAsync(http,provider,credential,cancellation);
            if(provider=="antigravity")lock(antigravityAccounts) {
                if(connected.Status==UsageStatus.Ready&&connected.AccountKey!=null) {
                    if(antigravityAccounts.Count>=32)antigravityAccounts.Clear();
                    antigravityAccounts[credential.AccountKey]=connected.AccountKey;
                } else if(antigravityAccounts.TryGetValue(credential.AccountKey,out string? account))connected=connected with {AccountKey=account};
            }
            return connected;
        }
        UsageResult Failure(UsageStatus status,TimeSpan? retry=null)=>new(status,[],credential.Plan,credential.AccountKey,retry);
        using var timeout=CancellationTokenSource.CreateLinkedTokenSource(cancellation);timeout.CancelAfter(TimeSpan.FromSeconds(20));
        try {
            using var request=new HttpRequestMessage(HttpMethod.Get,provider=="codex"?"https://chatgpt.com/backend-api/wham/usage":"https://api.anthropic.com/api/oauth/usage");
            request.Headers.Authorization=new AuthenticationHeaderValue("Bearer",credential.AccessToken);
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            if(provider=="claude") {
                request.Headers.Add("anthropic-beta","oauth-2025-04-20");
                request.Headers.UserAgent.ParseAdd("claude-code/2.1.121");
                request.Content=new ByteArrayContent([]);request.Content.Headers.ContentType=new MediaTypeHeaderValue("application/json");
            }
            using var response=await http.SendAsync(request,HttpCompletionOption.ResponseHeadersRead,timeout.Token);
            if(response.StatusCode==HttpStatusCode.Unauthorized)return Failure(UsageStatus.Expired);
            if(response.StatusCode==HttpStatusCode.Forbidden)return Failure(provider=="claude"?UsageStatus.NeedsLogin:UsageStatus.AccessDenied);
            if((int)response.StatusCode==429)return Failure(UsageStatus.RateLimited,RetryAfter(response));
            if(!response.IsSuccessStatusCode)return Failure(UsageStatus.Offline);
            if(response.Content.Headers.ContentLength>1024*1024)return Failure(UsageStatus.InvalidResponse);
            await using var body=await response.Content.ReadAsStreamAsync(timeout.Token);
            using var bytes=new MemoryStream();byte[] buffer=new byte[8192];
            int count;while((count=await body.ReadAsync(buffer,timeout.Token))>0) {
                if(bytes.Length+count>1024*1024)return Failure(UsageStatus.InvalidResponse);
                bytes.Write(buffer,0,count);
            }
            using var document=JsonDocument.Parse(bytes.ToArray());
            var parsed=Parse(provider,document.RootElement);
            parsed=parsed with {AccountKey=credential.AccountKey,Plan=parsed.Plan??credential.Plan,RetryAfter=parsed.Status==UsageStatus.RateLimited?RetryAfter(response):null};
            if(provider=="codex"&&parsed.Status==UsageStatus.Ready) {
                var credits=await ReadResetCreditsAsync(credential,timeout.Token,cancellation);
                parsed=parsed with {ResetCredits=credits.Credits,RetryAfter=credits.RetryAfter};
            }
            return parsed;
        } catch(OperationCanceledException) when(!cancellation.IsCancellationRequested){return Failure(UsageStatus.Offline);}
        catch(HttpRequestException){return Failure(UsageStatus.Offline);}
        catch(IOException){return Failure(UsageStatus.Offline);}
        catch(JsonException){return Failure(UsageStatus.InvalidResponse);}
    }
    private async Task<(CodexResetCredits? Credits,TimeSpan? RetryAfter)> ReadResetCreditsAsync(CliCredential credential,CancellationToken timeout,CancellationToken cancellation)
    {
        try {
            using var request=new HttpRequestMessage(HttpMethod.Get,"https://chatgpt.com/backend-api/wham/rate-limit-reset-credits");
            request.Headers.Authorization=new AuthenticationHeaderValue("Bearer",credential.AccessToken);
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            using var response=await http.SendAsync(request,HttpCompletionOption.ResponseHeadersRead,timeout);
            if((int)response.StatusCode==429)return (null,RetryAfter(response)??TimeSpan.FromSeconds(910));
            if(response.StatusCode!=HttpStatusCode.OK||response.Content.Headers.ContentLength>1024*1024)return (null,null);
            await using var body=await response.Content.ReadAsStreamAsync(timeout);
            using var bytes=new MemoryStream();byte[] buffer=new byte[8192];
            int count;while((count=await body.ReadAsync(buffer,timeout))>0) {
                if(bytes.Length+count>1024*1024)return (null,null);
                bytes.Write(buffer,0,count);
            }
            using var document=JsonDocument.Parse(bytes.ToArray());
            return (CodexResetCredits.Parse(document.RootElement),null);
        } catch(OperationCanceledException) when(!cancellation.IsCancellationRequested){return (null,null);}
        catch(Exception error) when(error is HttpRequestException or IOException or JsonException){return (null,null);}
    }
    private static TimeSpan? RetryAfter(HttpResponseMessage response)=>response.Headers.RetryAfter?.Delta
        ??(response.Headers.RetryAfter?.Date is DateTimeOffset date?date-DateTimeOffset.UtcNow:null);
    internal static UsageResult Parse(string provider,JsonElement root)
    {
        if(root.ValueKind!=JsonValueKind.Object)return new(UsageStatus.InvalidResponse,[]);
        if(root.TryGetProperty("error",out var error))return new(FileCliCredentials.String(error,"type")=="rate_limit_error"?UsageStatus.RateLimited:UsageStatus.InvalidResponse,[]);
        var windows=new List<LiveWindow>();
        if(provider=="codex") {
            if(!root.TryGetProperty("rate_limit",out var limits)||limits.ValueKind!=JsonValueKind.Object)return new(UsageStatus.InvalidResponse,[]);
            foreach(string slot in new[]{"primary_window","secondary_window"}) {
                if(!limits.TryGetProperty(slot,out var window)||window.ValueKind==JsonValueKind.Null)continue;
                if(window.ValueKind!=JsonValueKind.Object)return new(UsageStatus.InvalidResponse,[]);
                double? seconds=Number(window,"limit_window_seconds");
                string label=seconds.HasValue?(seconds.Value>=86400?"week":"5h"):slot=="primary_window"?"5h":"week";
                if(windows.All(w=>w.Label!=label))windows.Add(new(label,Percentage(window,"used_percent"),Reset(window,"reset_at"),SpanSeconds:seconds is >0 and <=2678400?seconds:null));
            }
            windows=windows.OrderBy(w=>w.Label=="5h"?0:1).ToList();
        } else {
            bool recognized=false;
            foreach(var slot in new[]{("five_hour","5h"),("seven_day","week")}) {
                if(!root.TryGetProperty(slot.Item1,out var window))continue;
                recognized=true;if(window.ValueKind==JsonValueKind.Null)continue;
                if(window.ValueKind!=JsonValueKind.Object)return new(UsageStatus.InvalidResponse,[]);
                windows.Add(new(slot.Item2,Percentage(window,"utilization")??Percentage(window,"used_percent"),Reset(window,"resets_at"),SpanSeconds:slot.Item2=="5h"?18000:604800));
            }
            if(!recognized)return new(UsageStatus.InvalidResponse,[]);
        }
        return new(UsageStatus.Ready,windows.ToArray(),FileCliCredentials.String(root,"plan_type"));
    }
    private static double? Number(JsonElement obj,string key)=>obj.TryGetProperty(key,out var value)&&value.ValueKind==JsonValueKind.Number&&value.TryGetDouble(out double number)&&double.IsFinite(number)?number:null;
    private static double? Percentage(JsonElement obj,string key)=>Number(obj,key) is double value&&value>=0?Math.Min(100,value):null;
    private static DateTimeOffset? Reset(JsonElement obj,string key)
    {
        if(!obj.TryGetProperty(key,out var value))return null;
        if(value.ValueKind==JsonValueKind.String&&DateTimeOffset.TryParse(value.GetString(),CultureInfo.InvariantCulture,DateTimeStyles.AssumeUniversal,out var date))return date;
        if(value.ValueKind==JsonValueKind.Number&&value.TryGetInt64(out long seconds)) {
            try{return DateTimeOffset.FromUnixTimeSeconds(seconds);}catch(ArgumentOutOfRangeException){return null;}
        }
        return null;
    }
    public void Dispose(){if(ownsClient)http.Dispose();}
}

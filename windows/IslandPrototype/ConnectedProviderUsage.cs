using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace IslandPrototype;

internal static class ConnectedProviderUsage
{
    private sealed record Response(UsageStatus Status,JsonElement Data=default,TimeSpan? RetryAfter=null);
    internal static async Task<UsageResult> FetchAsync(HttpClient http,string provider,CliCredential credential,CancellationToken cancellation)
    {
        UsageResult Failure(Response response)=>new(response.Status,[],credential.Plan,credential.AccountKey,response.RetryAfter);
        if(provider=="grok") {
            var credits=await SendAsync(http,provider,"billing?format=credits",credential,null,12,cancellation);
            if(credits.Status!=UsageStatus.Ready)return Failure(credits);
            var usage=ParseGrok(credits.Data);
            if(usage.Status!=UsageStatus.Ready)return usage with {AccountKey=credential.AccountKey};
            TimeSpan? retry=null;
            if(!usage.Windows.Any(w=>w.Used!=null)||Boolean(Property(credits.Data,"config"),"isUnifiedBillingUser")) {
                var monthly=await SendAsync(http,provider,"billing",credential,null,12,cancellation);
                var extra=monthly.Status==UsageStatus.Ready?ParseGrok(monthly.Data):Failure(monthly);
                if(extra.Status==UsageStatus.Ready) {
                    var windows=usage.Windows.ToList();
                    foreach(var item in extra.Windows.Where(w=>w.Used!=null)) {
                        int index=windows.FindIndex(w=>w.MetricId==item.MetricId);
                        if(index<0)windows.Add(item);else if(windows[index].Used==null)windows[index]=item;
                    }
                    if(windows.Any(w=>w.Used!=null))windows.RemoveAll(w=>w.Used==null);
                    usage=usage with {Windows=windows.ToArray(),Plan=usage.Plan??extra.Plan};
                } else if(!usage.Windows.Any(w=>w.Used!=null))return extra with {AccountKey=credential.AccountKey};
                if(monthly.Status==UsageStatus.RateLimited)retry=monthly.RetryAfter??TimeSpan.FromSeconds(910);
            }
            if(retry==null) {
                var settings=await SendAsync(http,provider,"settings",credential,null,2,cancellation);
                if(settings.Status==UsageStatus.Ready)usage=usage with {Plan=Text(settings.Data,"subscription_tier_display")??Text(settings.Data,"subscription_tier")??usage.Plan};
                if(settings.Status==UsageStatus.RateLimited)retry=settings.RetryAfter??TimeSpan.FromSeconds(910);
            }
            return usage with {AccountKey=credential.AccountKey,RetryAfter=retry};
        }
        if(provider=="antigravity") {
            var load=await SendAsync(http,provider,"loadCodeAssist",credential,"{\"metadata\":{\"ideType\":\"ANTIGRAVITY\"}}",12,cancellation);
            if(load.Status!=UsageStatus.Ready)return Failure(load);
            string? project=Text(load.Data,"cloudaicompanionProject");
            if(string.IsNullOrWhiteSpace(project))return new(UsageStatus.InvalidResponse,[],AccountKey:credential.AccountKey);
            var quota=await SendAsync(http,provider,"retrieveUserQuotaSummary",credential,JsonSerializer.Serialize(new {project}),12,cancellation);
            if(quota.Status!=UsageStatus.Ready)return Failure(quota);
            var usage=ParseAntigravity(quota.Data);
            return usage with {AccountKey=new CliCredential(credential.AccessToken,project).AccountKey,
                Plan=Text(Property(load.Data,"paidTier"),"name")??Text(Property(load.Data,"currentTier"),"name")??usage.Plan};
        }
        return new(UsageStatus.Unsupported,[]);
    }
    private static async Task<Response> SendAsync(HttpClient http,string provider,string method,CliCredential credential,string? body,int seconds,CancellationToken cancellation)
    {
        using var timeout=CancellationTokenSource.CreateLinkedTokenSource(cancellation);timeout.CancelAfter(TimeSpan.FromSeconds(seconds));
        try {
            string url=provider=="grok"?"https://cli-chat-proxy.grok.com/v1/"+method:"https://daily-cloudcode-pa.googleapis.com/v1internal:"+method;
            using var request=new HttpRequestMessage(provider=="grok"?HttpMethod.Get:HttpMethod.Post,url);
            request.Headers.Authorization=new AuthenticationHeaderValue("Bearer",credential.AccessToken);
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            if(provider=="grok") {
                request.Headers.Add("x-xai-token-auth","xai-grok-cli");request.Headers.Add("x-grok-client-mode","cli");
                if(credential.UserId!=null)request.Headers.Add("x-userid",credential.UserId);
            } else {
                request.Headers.UserAgent.ParseAdd("antigravity/1.1.25");
                request.Content=new StringContent(body!,Encoding.UTF8,"application/json");
            }
            using var response=await http.SendAsync(request,HttpCompletionOption.ResponseHeadersRead,timeout.Token);
            if(response.StatusCode==HttpStatusCode.Unauthorized)return new(UsageStatus.Expired);
            if(response.StatusCode==HttpStatusCode.Forbidden)return new(UsageStatus.AccessDenied);
            if((int)response.StatusCode==429)return new(UsageStatus.RateLimited,RetryAfter:response.Headers.RetryAfter?.Delta??(response.Headers.RetryAfter?.Date is DateTimeOffset date?date-DateTimeOffset.UtcNow:null));
            if(!response.IsSuccessStatusCode)return new(UsageStatus.Offline);
            if(response.Content.Headers.ContentLength>2*1024*1024)return new(UsageStatus.InvalidResponse);
            await using var stream=await response.Content.ReadAsStreamAsync(timeout.Token);
            using var bytes=new MemoryStream();byte[] buffer=new byte[8192];int count;
            while((count=await stream.ReadAsync(buffer,timeout.Token))>0) {
                if(bytes.Length+count>2*1024*1024)return new(UsageStatus.InvalidResponse);
                bytes.Write(buffer,0,count);
            }
            using var document=JsonDocument.Parse(bytes.ToArray());
            if(document.RootElement.ValueKind!=JsonValueKind.Object)return new(UsageStatus.InvalidResponse);
            return new(UsageStatus.Ready,document.RootElement.Clone());
        } catch(OperationCanceledException) when(!cancellation.IsCancellationRequested){return new(UsageStatus.Offline);}
        catch(Exception error) when(error is HttpRequestException or IOException){return new(UsageStatus.Offline);}
        catch(JsonException){return new(UsageStatus.InvalidResponse);}
    }
    internal static UsageResult ParseGrok(JsonElement root)
    {
        var config=Property(root,"config");
        if(config.ValueKind!=JsonValueKind.Object)return new(UsageStatus.InvalidResponse,[]);
        var period=Property(config,"currentPeriod");
        var reset=ProviderCredentialParser.Date(Text(period,"end")??Text(config,"billingPeriodEnd"));
        string? type=Text(period,"type");
        var windows=new List<LiveWindow>();
        if(Number(config,"creditUsagePercent") is double percent&&percent is >=0 and <=100) {
            bool month=type=="USAGE_PERIOD_TYPE_MONTHLY",week=type=="USAGE_PERIOD_TYPE_WEEKLY";
            windows.Add(new(month?"month":week?"week":"Credits",percent,reset,month?"monthly":"credits",Kind:week?1:2));
        }
        if(windows.All(w=>w.MetricId!="monthly")&&Number(Property(config,"monthlyLimit"),"val",true) is double cap&&cap>0
            &&Number(Property(config,"used"),"val",true) is double used&&used>=0)
            windows.Add(new("month",Math.Min(100,used/cap*100),ProviderCredentialParser.Date(Text(config,"billingPeriodEnd")),"monthly",Kind:2));
        if(windows.Count==0)windows.Add(new("Credits",null,reset,"credits",Kind:2));
        return new(UsageStatus.Ready,windows.ToArray(),Text(config,"subscriptionTier")??Text(root,"subscriptionTier"));
    }
    internal static UsageResult ParseAntigravity(JsonElement root)
    {
        if(root.ValueKind!=JsonValueKind.Object)return new(UsageStatus.InvalidResponse,[]);
        var groups=Property(Property(root,"response"),"groups");
        if(groups.ValueKind is JsonValueKind.Undefined or JsonValueKind.Null)groups=Property(Property(root,"summary"),"groups");
        if(groups.ValueKind is JsonValueKind.Undefined or JsonValueKind.Null)groups=Property(root,"groups");
        var windows=new List<LiveWindow>();
        if(groups.ValueKind==JsonValueKind.Array)foreach(var group in groups.EnumerateArray()) {
            var buckets=Property(group,"buckets");
            string? groupLabel=Text(group,"displayName");string groupId=Text(group,"groupId")??groupLabel??"default";
            if(buckets.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined)continue;
            if(buckets.ValueKind!=JsonValueKind.Array)return new(UsageStatus.InvalidResponse,[]);
            foreach(var bucket in buckets.EnumerateArray()) {
                if(Boolean(bucket,"disabled"))continue;
                var remaining=Property(bucket,"remaining");
                double? fraction=Number(bucket,"remainingFraction")??Number(remaining,"remainingFraction")
                    ??(Text(remaining,"case")=="remainingFraction"?Number(remaining,"value"):null);
                string label=Text(bucket,"displayName")??Text(bucket,"bucketId")??"Usage";
                string lower=label.ToLowerInvariant();int kind=lower.Contains("week")||lower.Contains("7d")?1:lower.Contains("five")||lower.Contains("5h")||lower.Contains("5 hour")?0:3;
                windows.Add(new(kind==0?"5h":kind==1?"week":label,Used(fraction),ProviderCredentialParser.Date(Text(bucket,"resetTime")),Text(bucket,"bucketId")??label,groupId,groupLabel,kind));
            }
        } else if(groups.ValueKind is not (JsonValueKind.Undefined or JsonValueKind.Null))return new(UsageStatus.InvalidResponse,[]);
        var status=Property(root,"userStatus");
        if(windows.Count==0) {
            var models=Property(Property(status,"cascadeModelConfigData"),"clientModelConfigs");
            if(models.ValueKind==JsonValueKind.Array)foreach(var model in models.EnumerateArray()) {
                var quota=Property(model,"quotaInfo");if(quota.ValueKind!=JsonValueKind.Object)continue;
                string identity=Text(Property(model,"modelOrAlias"),"model")??Text(model,"label")??"model";
                windows.Add(new("Usage",Used(Number(quota,"remainingFraction")),ProviderCredentialParser.Date(Text(quota,"resetTime")),identity,identity,Text(model,"label")??identity));
            }
        }
        windows=windows.DistinctBy(w=>(w.GroupId,w.MetricId)).ToList();
        if(windows.Count is 0 or >512)return new(UsageStatus.InvalidResponse,[]);
        return new(UsageStatus.Ready,windows.ToArray(),Text(Property(status,"userTier"),"name")??Text(Property(Property(status,"planStatus"),"planInfo"),"planName"));
    }
    private static double? Used(double? fraction)=>fraction is >=0 and <=1?(1-fraction)*100:null;
    private static JsonElement Property(JsonElement root,string key)=>root.ValueKind==JsonValueKind.Object&&root.TryGetProperty(key,out var value)?value:default;
    private static string? Text(JsonElement root,string key)=>FileCliCredentials.String(root,key);
    private static bool Boolean(JsonElement root,string key)=>Property(root,key).ValueKind==JsonValueKind.True;
    private static double? Number(JsonElement root,string key,bool allowString=false)
    {
        var value=Property(root,key);double number;
        if(value.ValueKind==JsonValueKind.Number&&value.TryGetDouble(out number)&&double.IsFinite(number))return number;
        if(allowString&&value.ValueKind==JsonValueKind.String&&double.TryParse(value.GetString(),NumberStyles.Float,CultureInfo.InvariantCulture,out number)&&double.IsFinite(number))return number;
        return null;
    }
}

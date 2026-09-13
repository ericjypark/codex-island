using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using IslandPrototype;

internal static class CodexAccountTests
{
    private const string Quota="""{"accountId":"fixture-account","rateLimits":{"primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"planType":"pro","primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":2000000000},"secondary":{"usedPercent":0,"windowDurationMins":10080}},"other":{"primary":{"usedPercent":77}}},"rateLimitResetCredits":{"availableCount":5,"credits":[{"id":"later","status":"available","expiresAt":2000000000},{"id":"earlier","status":"available","expiresAt":1900000000},{"id":"spent","status":"redeemed","expiresAt":2000000000}]}}""";
    private static JsonElement Json(string text){using var doc=JsonDocument.Parse(text);return doc.RootElement.Clone();}
    internal static async Task Run(Action<string,bool> check)
    {
        DateTimeOffset now=DateTimeOffset.FromUnixTimeSeconds(1800000000);
        var parsed=CodexAccountReader.Parse(Json(Quota));
        check("CLI multi-bucket Codex quota wins over legacy and other models",parsed is {Status:UsageStatus.Ready,Plan:"pro",Windows:[{Label:"5h",Used:25},{Label:"week",Used:0}]});
        check("CLI account identity is hashed before entering shared state",parsed.AccountKey==new CliCredential("fixture-token","fixture-account").AccountKey&&!parsed.AccountKey.Contains("fixture"));
        check("Credit count remains authoritative when detail rows are capped",parsed.ResetCredits is {AvailableCount:5}&&parsed.ResetCredits.Available(now).Select(c=>c.Id).SequenceEqual(new[]{"earlier","later"}));
        check("Expired and redeemed credits cannot produce a badge",!parsed.ResetCredits!.ShowBadge(DateTimeOffset.FromUnixTimeSeconds(2000000000)));
        check("A missing credit summary stays unknown",CodexResetCredits.Parse(Json("{}"))==null);
        check("Count-only and known-empty credit details remain distinct",CodexResetCredits.Parse(Json("""{"available_count":2}"""))?.Credits==null&&CodexResetCredits.Parse(Json("""{"available_count":0,"credits":[]}""")) is {Credits:[]});
        check("Malformed credit counts cannot imply zero",new[]{"-1","1.5","\"2\"","null"}.All(value=>CodexResetCredits.Parse(Json("{\"available_count\":"+value+"}"))==null));
        var direct=CodexResetCredits.Parse(Json("""{"available_count":3,"credits":[null,4,{}, {"id":"A","status":"available","expires_at":"2033-05-18T03:33:20.000Z"},{"id":"A","status":"available","expires_at":"2033-05-18T03:33:20Z"},{"id":"B","status":"available","expires_at":null}]}"""));
        check("Malformed and duplicate details are filtered without inventing expirations",direct?.Credits?.Length==2&&direct.Available(now) is [{Id:"A",ExpiresAt:not null}]);
        var old=new LiveProviderState("codex",UsageStatus.Ready,[],AccountKey:"A",ResetCredits:parsed.ResetCredits);
        check("Same-account credit lookup failure retains known details",LiveUsageCoordinator.Merge(old,new(UsageStatus.Ready,[],AccountKey:"A"),now).ResetCredits==old.ResetCredits);
        check("A known zero clears previously available credits",LiveUsageCoordinator.Merge(old,new(UsageStatus.Ready,[],AccountKey:"A",ResetCredits:new(0,[])),now).ResetCredits is {AvailableCount:0,Credits:[]});
        check("An account switch or absent identity cannot inherit reset credits",new string?[]{"B",null}.All(key=>LiveUsageCoordinator.Merge(old,new(UsageStatus.Ready,[],AccountKey:key),now).ResetCredits==null));
        check("Signing out clears credit status",LiveUsageCoordinator.Merge(old,new(UsageStatus.NotConnected,[],AccountKey:"A"),now).ResetCredits==null);
        check("CLI legacy response and missing percentages stay valid",CodexAccountReader.Parse(Json("""{"rateLimits":{"primary":{"windowDurationMins":10080},"secondary":null}}""")) is {Status:UsageStatus.Ready,Windows:[{Label:"week",Used:null}],AccountKey:null});
        check("Invalid protocol error shapes do not throw",new[]{"null","[]","{\"code\":\"bad\"}","{\"code\":1.5}"}.All(json=>CodexAccountReader.ErrorStatus(Json(json))==UsageStatus.InvalidResponse));
        check("Unsupported CLI versions produce an actionable status",CodexAccountReader.ErrorStatus(Json("""{"code":-32601,"message":"Method not found"}"""))==UsageStatus.Unsupported);
        foreach(var pair in new[]{(401,UsageStatus.Expired),(403,UsageStatus.AccessDenied),(429,UsageStatus.RateLimited)})check("CLI HTTP "+pair.Item1+" is classified without echoing response text",CodexAccountReader.ErrorStatus(Json("{\"message\":\"HTTP "+pair.Item1+" fixture-secret\"}"))==pair.Item2);
        string response="{\"method\":\"account/updated\",\"params\":{}}\n{\"id\":90,\"result\":{}}\n{\"id\":1,\"result\":{}}\n{\"id\":2,\"result\":{\"account\":{\"type\":\"chatgpt\",\"planType\":\"plus\"}}}\n{\"id\":3,\"result\":"+Quota+"}\n";
        using var writer=new StringWriter();var result=await CodexAccountReader.ReadProtocolAsync(new StringReader(response),writer,default);
        var requests=writer.ToString().Split('\n',StringSplitOptions.RemoveEmptyEntries).Select(Json).ToArray();
        check("CLI protocol tolerates notifications and unrelated response IDs",result.Windows.First().Used==25);
        check("The account reader only initializes and reads account/quota state",requests.Select(r=>r.GetProperty("method").GetString()).SequenceEqual(new[]{"initialize","initialized","account/read","account/rateLimits/read"}));
        check("Account reads do not force token refresh or enable reserve capacity",requests[2].GetProperty("params").GetProperty("refreshToken").GetBoolean()==false&&requests[3].GetProperty("params").GetProperty("supportsLunaReserve").GetBoolean()==false&&requests[3].GetProperty("params").GetProperty("excludeResetCreditDetails").GetBoolean()==false);
        foreach(string account in new[]{"null","{\"type\":\"apiKey\"}","{\"type\":\"amazonBedrock\"}"}) {
            using var noQuota=new StringWriter();var inactive=await CodexAccountReader.ReadProtocolAsync(new StringReader("{\"id\":1,\"result\":{}}\n{\"id\":2,\"result\":{\"account\":"+account+"}}\n"),noQuota,default);
            check("Non-ChatGPT account "+account+" does not query subscription quota",inactive.Status==UsageStatus.NotConnected&&!noQuota.ToString().Contains("rateLimits/read"));
        }
        async Task<bool> Reject(string input) {try{await CodexAccountReader.ReadProtocolAsync(new StringReader(input),new StringWriter(),default);return false;}catch(Exception error)when(error is IOException or JsonException){return !error.Message.Contains("fixture-secret");}}
        check("A truncated protocol stream fails safely",await Reject("{\"id\":1,\"result\":{}}\n"));
        check("Malformed JSON never exposes the response body",await Reject("fixture-secret\n"));
        check("Unexpected server requests cannot trigger credential or user actions",await Reject("{\"id\":1,\"method\":\"account/chatgptAuthTokens/refresh\"}\n"));
        check("Oversized protocol lines are bounded",await Reject(new string('x',2*1024*1024+1)+"\n"));
        check("Notification floods are bounded",await Reject(string.Concat(Enumerable.Repeat("{\"method\":\"notice\"}\n",256))));
        using(var cancellation=new CancellationTokenSource()) {
            cancellation.Cancel();bool canceled=false;try{await CodexAccountReader.ReadProtocolAsync(new StringReader(response),new StringWriter(),cancellation.Token);}catch(OperationCanceledException){canceled=true;}
            check("Protocol cancellation is preserved",canceled);
        }
        await Requests(check);
        await Launchers(check);
    }
    private static async Task Requests(Action<string,bool> check)
    {
        using var handler=new Handler();using var http=new HttpClient(handler);using var client=new ProviderUsageClient(new Credentials(),http);
        foreach(int status in new[]{200,401,403,429,500}) {
            handler.Status=status;handler.Body="""{"available_count":2,"credits":[{"id":"A","status":"available","expires_at":2000000000}]}""";
            var result=await client.FetchAsync("codex",default);
            check("Optional credit HTTP "+status+" preserves successful quota",result is {Status:UsageStatus.Ready,Windows:[{Used:17}]}&&(status==200?result.ResetCredits?.AvailableCount==2:result.ResetCredits==null));
            if(status==429)check("Optional credit rate limiting honors Retry-After",result.RetryAfter==TimeSpan.FromSeconds(1800));
        }
        handler.Status=200;
        foreach(string body in new[]{"{broken",new string(' ',1024*1024+1)}) {
            handler.Body=body;check("Invalid optional credit body preserves quota",(await client.FetchAsync("codex",default)) is {Status:UsageStatus.Ready,ResetCredits:null});
        }
        handler.Throw=true;check("Optional credit network failure preserves quota",(await client.FetchAsync("codex",default)) is {Status:UsageStatus.Ready,ResetCredits:null});
        handler.Throw=false;handler.Cancel=true;using var cancellation=new CancellationTokenSource();handler.Cancellation=cancellation;
        bool canceled=false;try{await client.FetchAsync("codex",cancellation.Token);}catch(OperationCanceledException){canceled=true;}
        check("Cancellation during optional credits cancels the whole refresh",canceled);
        int bridges=0;using var bridged=new ProviderUsageClient(new Credentials(UsageStatus.Unsupported),http,codexAccountReader:_=>{bridges++;return Task.FromResult(CodexAccountReader.Parse(Json(Quota)));});
        check("Unsupported credential storage delegates account reads to the CLI",(await bridged.FetchAsync("codex",default)).ResetCredits?.AvailableCount==5&&bridges==1);
        using var signedOut=new ProviderUsageClient(new Credentials(UsageStatus.NotConnected),http,codexAccountReader:_=>{bridges++;return Task.FromResult(new UsageResult(UsageStatus.Ready,[]));});
        check("A missing account does not start the CLI reader",(await signedOut.FetchAsync("codex",default)).Status==UsageStatus.NotConnected&&bridges==1);
    }
    private static async Task Launchers(Action<string,bool> check)
    {
        string directory=Path.Combine(Path.GetTempPath(),"CodexIsland reader ' "+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(directory);
        try {
            string script=Path.Combine(directory,"codex.ps1");
            File.WriteAllText(script,"""
                if(($args -join ' ') -ne 'app-server --listen stdio://'){exit 3}
                while($line=[Console]::ReadLine()) {
                    $request=$line|ConvertFrom-Json
                    if($request.method -eq 'initialize'){[Console]::WriteLine('{"id":1,"result":{}}')}
                    elseif($request.method -eq 'account/read'){[Console]::WriteLine('{"id":2,"result":{"account":{"type":"chatgpt","planType":"pro"}}}')}
                    elseif($request.method -eq 'account/rateLimits/read'){[Console]::WriteLine('{"id":3,"result":{"rateLimits":{"primary":{"usedPercent":12,"windowDurationMins":300}}}}')}
                }
                """,new UTF8Encoding(false));
            string command=Path.Combine(directory,"codex.cmd");File.WriteAllText(command,"@echo off\r\npowershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"%~dp0codex.ps1\" %*\r\n");
            foreach(string executable in new[]{script,command}) {
                var watch=System.Diagnostics.Stopwatch.StartNew();var result=await CodexAccountReader.ReadAsync(executable,default);
                check("CLI "+Path.GetExtension(executable)+" launcher forwards protocol input through quoted paths",result is {Status:UsageStatus.Ready,Windows:[{Used:12}]}&&watch.Elapsed<TimeSpan.FromSeconds(15));
            }
        }finally{Directory.Delete(directory,true);}
    }
    internal static async Task<int> ReadLive()
    {
        var watch=System.Diagnostics.Stopwatch.StartNew();var result=await CodexAccountReader.ReadAsync(default);
        Console.WriteLine(JsonSerializer.Serialize(new {status=result.Status.ToString(),result.Plan,hasAccountIdentity=result.AccountKey!=null,windows=result.Windows.Select(w=>new{w.Label,w.Used,w.ResetAt}),creditCount=result.ResetCredits?.AvailableCount,detailCount=result.ResetCredits?.Credits?.Length,visibleCredits=result.ResetCredits?.Available(DateTimeOffset.Now).Select(c=>new{c.Status,c.ExpiresAt}),elapsedSeconds=watch.Elapsed.TotalSeconds}));
        return result.Status==UsageStatus.Ready?0:1;
    }
    private sealed class Credentials(UsageStatus status=UsageStatus.Ready):ICliCredentials
    {
        public Task<CredentialRead> ReadAsync(string provider,string[] excluded,CancellationToken cancellation)=>Task.FromResult(status==UsageStatus.Ready?new CredentialRead(new CliCredential("fixture-token","fixture-account")):new CredentialRead(null,status));
    }
    private sealed class Handler:HttpMessageHandler
    {
        internal int Status=200;internal string Body="";internal bool Throw,Cancel;internal CancellationTokenSource? Cancellation;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken cancellation)
        {
            if(request.RequestUri?.AbsolutePath.EndsWith("/usage")==true)return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK){Content=new StringContent("""{"rate_limit":{"primary_window":{"used_percent":17}}}""")});
            if(Throw)throw new HttpRequestException("fixture-secret");
            if(Cancel){Cancellation!.Cancel();cancellation.ThrowIfCancellationRequested();}
            var response=new HttpResponseMessage((HttpStatusCode)Status){Content=new StringContent(Body)};
            if(Status==429)response.Headers.RetryAfter=new(System.TimeSpan.FromSeconds(1800));
            return Task.FromResult(response);
        }
    }
}

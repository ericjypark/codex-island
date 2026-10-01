using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using IslandPrototype;

internal static class LiveUsageTests
{
    internal static async Task Run(Action<string,bool> check)
    {
        UsageResult Parse(string id,string json){using var doc=JsonDocument.Parse(json);return ProviderUsageClient.Parse(id,doc.RootElement);}
        var week=Parse("codex","""{"plan_type":"pro","rate_limit":{"primary_window":{"limit_window_seconds":604800,"used_percent":23,"reset_at":2000000000}}}""");
        check("Codex routes a weekly primary window by duration",week.Windows is [{Label:"week",Used:23}]&&week.Plan=="pro");
        var missing=Parse("codex","""{"rate_limit":{"primary_window":{},"secondary_window":{"used_percent":0}}}""");
        check("Missing quota and a real zero remain distinct",missing.Windows is [{Label:"5h",Used:null},{Label:"week",Used:0}]);
        check("Claude fractional utilization remains a percentage",Parse("claude","""{"five_hour":{"utilization":0.5},"seven_day":null}""").Windows is [{Used:.5}]);
        var resets=Parse("claude","""{"five_hour":{"used_percent":12,"resets_at":"2033-05-18T03:33:20.000Z"},"seven_day":{"utilization":0,"resets_at":2000000000}}""");
        check("Claude reset times accept ISO and Unix seconds",resets.Windows.Length==2&&resets.Windows[0].ResetAt==resets.Windows[1].ResetAt);
        check("Invalid JSON shapes are errors rather than empty success",Parse("codex","{}").Status==UsageStatus.InvalidResponse&&Parse("claude","[]").Status==UsageStatus.InvalidResponse);
        check("Explicitly unavailable Claude windows are a valid response",Parse("claude","""{"five_hour":null,"seven_day":null}""").Status==UsageStatus.Ready);
        check("An embedded rate limit is recognized",Parse("claude","""{"error":{"type":"rate_limit_error"}}""").Status==UsageStatus.RateLimited);
        var duplicates=Parse("codex","""{"rate_limit":{"primary_window":{"used_percent":11,"limit_window_seconds":604800},"secondary_window":{"used_percent":22,"limit_window_seconds":604800}}}""");
        check("Colliding Codex windows retain the first reported window",duplicates.Windows is [{Label:"week",Used:11}]);
        check("Malformed quota values cannot invent usage",Parse("claude","""{"five_hour":{"utilization":-1},"seven_day":{"utilization":"bad"}}""").Windows.All(w=>w.Used==null));
        await CheckFiles(check);
        await CheckRequests(check);
        await CheckCoordinator(check);
    }
    private static async Task CheckFiles(Action<string,bool> check)
    {
        string root=Path.Combine(Path.GetTempPath(),"CodexIslandCredentialTests-"+Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        var environment=new Dictionary<string,string>{{"CODEX_HOME",root},{"CLAUDE_CONFIG_DIR",root}};
        var source=new FileCliCredentials(root,key=>environment.GetValueOrDefault(key));
        try {
            check("Missing CLI credential files stay disconnected",(await source.ReadAsync("codex",[],default)).Status==UsageStatus.NotConnected);
            string file=Path.Combine(root,"auth.json"),claude=Path.Combine(root,".credentials.json");
            const string data="""{"tokens":{"access_token":"fixture-codex","account_id":"fixture-account"}}""";
            File.WriteAllText(file,data);DateTime written=File.GetLastWriteTimeUtc(file);
            var read=await source.ReadAsync("codex",[],default);
            check("Codex honors custom CLI home and reads its account token",read.Credential?.AccessToken=="fixture-codex");
            check("Credential reads do not modify the CLI store",File.ReadAllText(file)==data&&File.GetLastWriteTimeUtc(file)==written);
            check("Credential objects cannot serialize or print their token",JsonSerializer.Serialize(read.Credential)=="{}"&&read.Credential!.ToString()=="[credential redacted]");
            File.WriteAllText(Path.Combine(root,"config.toml"),"cli_auth_credentials_store = 'keyring'\n");
            check("Keyring configuration cannot fall back to a stale file",(await source.ReadAsync("codex",[],default)).Status==UsageStatus.Unsupported);
            File.WriteAllText(Path.Combine(root,"config.toml"),"cli_auth_credentials_store = \"file\"\n");
            File.WriteAllText(file,"{broken");
            check("Malformed credentials yield a safe status",(await source.ReadAsync("codex",[],default)).Status==UsageStatus.CredentialUnavailable);
            File.WriteAllText(file,"""{"OPENAI_API_KEY":"fixture-api-key"}""");
            check("An API key is never used as a subscription access token",(await source.ReadAsync("codex",[],default)).Credential==null);
            File.WriteAllText(claude,"""{"claudeAiOauth":{"accessToken":"fixture-file","subscriptionType":"max"}}""");
            environment["CLAUDE_CODE_OAUTH_TOKEN"]="fixture-env";
            check("Claude environment token has first priority",(await source.ReadAsync("claude",[],default)).Credential?.AccessToken=="fixture-env");
            var fallback=await source.ReadAsync("claude",["fixture-env"],default);
            check("Claude can re-read its file after a rejected environment token",fallback.Credential?.AccessToken=="fixture-file"&&fallback.Credential.Plan=="max");
            check("Rejected tokens are not retried from the same file",(await source.ReadAsync("claude",["fixture-env","fixture-file"],default)).Credential==null);
            check("Invalid bearer characters are rejected before a request",!FileCliCredentials.ValidToken("fixture\r\nInjected: x"));
            check("Empty account identifiers cannot merge unrelated credentials",new CliCredential("first","").AccountKey!=new CliCredential("second","").AccountKey);
        } finally {Directory.Delete(root,true);}
    }
    private static async Task CheckRequests(Action<string,bool> check)
    {
        var credentials=new FakeCredentials([new("fixture-old","same"),new("fixture-new","same")]);
        bool exact=true;
        using var handler=new Handler((request,cancellation)=>{
            exact&=request.Method==HttpMethod.Get&&request.RequestUri!.AbsoluteUri=="https://api.anthropic.com/api/oauth/usage"
                &&request.Headers.UserAgent.ToString()=="claude-code/2.1.121"
                &&request.Headers.GetValues("anthropic-beta").Single()=="oauth-2025-04-20"
                &&request.Headers.Accept.Single().MediaType=="application/json"&&request.Content?.Headers.ContentType?.MediaType=="application/json";
            return Task.FromResult(request.Headers.Authorization!.Parameter=="fixture-old"?Response(401):Response(200,"""{"five_hour":{"utilization":34},"seven_day":null}"""));
        });
        using var http=new HttpClient(handler);using var client=new ProviderUsageClient(credentials,http);
        var rotated=await client.FetchAsync("claude",default);
        check("Claude sends the required usage headers and exact route",exact&&handler.Calls==2);
        check("A rejected credential is re-read without an OAuth refresh",rotated.Status==UsageStatus.Ready&&rotated.Windows[0].Used==34&&credentials.Reads==2);
        credentials.Reset();handler.Next=(request,_)=>Task.FromResult(Response(403));
        check("Scope errors produce a re-login state",(await client.FetchAsync("claude",default)).Status==UsageStatus.NeedsLogin);
        credentials.Reset();
        check("Codex permission errors do not trigger credential re-probing",(await client.FetchAsync("codex",default)).Status==UsageStatus.AccessDenied&&credentials.Reads==1);
        credentials.Reset();handler.Next=(request,_)=>Task.FromResult(Response(429));int before=handler.Calls;
        var limited=await client.FetchAsync("claude",default);
        check("A 429 stops all further credential probing",limited.Status==UsageStatus.RateLimited&&credentials.Reads==1&&handler.Calls==before+1);
        credentials.Reset();handler.Next=(request,_)=>Task.FromResult(Response(200,"""{"error":{"type":"rate_limit_error"}}"""));
        check("A rate limit in a 200 response also stops credential probing",(await client.FetchAsync("claude",default)).Status==UsageStatus.RateLimited&&credentials.Reads==1);
        handler.Next=(request,_)=>Task.FromResult(Response(200,"{broken"));
        check("Malformed response bodies become safe errors",(await client.FetchAsync("claude",default)).Status==UsageStatus.InvalidResponse);
        handler.Next=(request,_)=>Task.FromResult(Response(200,new string(' ',1024*1024+1)));
        check("Oversized responses are rejected",(await client.FetchAsync("claude",default)).Status==UsageStatus.InvalidResponse);
        var codexRoutes=new List<string>();bool codexHeaders=true;
        handler.Next=(request,_)=>{codexRoutes.Add(request.RequestUri!.AbsoluteUri);codexHeaders&=request.Method==HttpMethod.Get&&request.Headers.Authorization?.Scheme=="Bearer"&&!request.Headers.Contains("anthropic-beta");return Task.FromResult(Response(200,request.RequestUri.AbsolutePath.EndsWith("/usage")?"""{"rate_limit":{"primary_window":{"used_percent":0}}}""":"""{"available_count":0,"credits":[]}"""));};
        check("Codex uses authenticated GETs for quota and reset-credit status",(await client.FetchAsync("codex",default)) is {Status:UsageStatus.Ready,ResetCredits.AvailableCount:0}&&codexHeaders&&codexRoutes.SequenceEqual(new[]{"https://chatgpt.com/backend-api/wham/usage","https://chatgpt.com/backend-api/wham/rate-limit-reset-credits"}));
        handler.Next=(_,_)=>throw new HttpRequestException("sensitive response text must not escape");
        check("Network exception text does not escape into provider state",(await client.FetchAsync("codex",default)).Status==UsageStatus.Offline);
        int callsBeforeUnsupported=handler.Calls;
        check("The HTTP boundary rejects unsupported provider identifiers",(await client.FetchAsync("unknown",default)).Status==UsageStatus.Unsupported&&handler.Calls==callsBeforeUnsupported);
        handler.Next=async(_,cancellation)=>{await Task.Delay(10000,cancellation);return Response(200);};
        using var cancel=new CancellationTokenSource();cancel.Cancel();bool canceled=false;
        try{await client.FetchAsync("claude",cancel.Token);}catch(OperationCanceledException){canceled=true;}
        check("Caller cancellation is preserved",canceled);
    }
    private static async Task CheckCoordinator(Action<string,bool> check)
    {
        DateTimeOffset now=new(2030,1,1,0,0,0,TimeSpan.Zero);
        var client=new FakeClient();using var coordinator=new LiveUsageCoordinator(client,()=>now);
        var first=new UsageResult(UsageStatus.Ready,[new("5h",42,now.AddHours(1)),new("week",15,now.AddDays(5))],"pro","A");
        client.Next=(_,_)=>Task.FromResult(first);coordinator.Select(["codex"]);
        await coordinator.RefreshAsync();
        check("Only selected providers are requested",client.Calls.SequenceEqual(new[]{"codex"})&&coordinator.State("claude").AttemptedAt==null);
        await coordinator.RefreshAsync(false,30);
        check("Automatic refresh cannot run within five minutes",client.Calls.Count==1);
        client.Next=(_,_)=>Task.FromResult(new UsageResult(UsageStatus.Offline,[],AccountKey:"A"));
        await coordinator.RefreshAsync(true);
        check("Transient failures retain same-account readings with an error",coordinator.State("codex") is {Status:UsageStatus.Offline,Windows:[{Used:42},{Used:15}]});
        now=now.AddHours(2);await coordinator.RefreshAsync();
        check("An expired window cannot retain an old quota",coordinator.State("codex").Windows is [{Used:null},{Used:15}]);
        client.Next=(_,_)=>Task.FromResult(new UsageResult(UsageStatus.RateLimited,[],AccountKey:"A"));await coordinator.RefreshAsync(true);int calls=client.Calls.Count;
        await coordinator.RefreshAsync(true);now=now.AddSeconds(909);await coordinator.RefreshAsync(true);
        check("Manual refresh cannot bypass the provider cooldown",client.Calls.Count==calls&&coordinator.State("codex").RetryAt==now.AddSeconds(1));
        now=now.AddSeconds(1);client.Next=(_,_)=>Task.FromResult(first with {Windows=[new("week",16,now.AddDays(5))]});await coordinator.RefreshAsync(false,1800);
        check("Refresh resumes after cooldown and drops unreported windows",client.Calls.Count==calls+1&&coordinator.State("codex").Windows is [{Label:"week",Used:16}]);
        client.Next=(_,_)=>Task.FromResult(new UsageResult(UsageStatus.Offline,[],AccountKey:"B"));await coordinator.RefreshAsync(true);
        check("Account changes never inherit another account's quota or plan",coordinator.State("codex") is {Windows:[],Plan:null,UpdatedAt:null});
        client.Next=(_,_)=>Task.FromResult(first);await coordinator.RefreshAsync(true);
        client.Next=(_,_)=>Task.FromResult(new UsageResult(UsageStatus.Expired,[],AccountKey:"A"));await coordinator.RefreshAsync(true);
        check("Codex auth errors retain unexpired readings with an error",coordinator.State("codex").Windows.Any(w=>w.Label=="week"&&w.Used==15)&&coordinator.State("codex").Status==UsageStatus.Expired);
        var claudeBefore=new LiveProviderState("claude",UsageStatus.Ready,[new("5h",42,now.AddHours(1))],AccountKey:"C");
        check("Claude terminal authentication failures clear obsolete readings",LiveUsageCoordinator.Merge(claudeBefore,new(UsageStatus.Expired,[],AccountKey:"C"),now).Windows.Length==0);
        var longRetry=LiveUsageCoordinator.Merge(claudeBefore,new(UsageStatus.RateLimited,[],AccountKey:"C",RetryAfter:TimeSpan.FromDays(2)),now);
        check("A provider Retry-After longer than the minimum is honored",longRetry.RetryAt==now.AddDays(2));
        var pending=new TaskCompletionSource<UsageResult>(TaskCreationOptions.RunContinuationsAsynchronously);
        var entered=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        client.Next=(_,_)=>{entered.TrySetResult();return pending.Task;};
        var flight=coordinator.RefreshAsync(true);await entered.Task;
        var duplicate=coordinator.RefreshAsync(true);
        check("Concurrent refresh requests join one active fetch",ReferenceEquals(flight,duplicate)&&coordinator.Loading);
        coordinator.Select(["claude"]);client.Next=(_,_)=>Task.FromResult(first with {AccountKey="C"});await coordinator.RefreshAsync();
        pending.SetResult(first);await flight;
        check("A late canceled result cannot publish into the new selection",coordinator.State("codex").Status==UsageStatus.Expired&&coordinator.State("claude").Status==UsageStatus.Ready&&!coordinator.Loading);
        coordinator.Select(["grok","antigravity"]);calls=client.Calls.Count;await coordinator.RefreshAsync(true);
        check("Grok and Antigravity refresh their own selected provider states",client.Calls.Count==calls+2&&client.Calls.Skip(calls).OrderBy(id=>id).SequenceEqual(new[]{"antigravity","grok"}));
        coordinator.ObserveAccounts(true);calls=client.Calls.Count;await coordinator.RefreshAsync(true);
        check("Accounts can connect all four providers independently of island selection",client.Calls.Count==calls+4&&coordinator.State("codex").Status==UsageStatus.Ready&&coordinator.State("claude").Status==UsageStatus.Ready);
        calls=client.Calls.Count;await coordinator.RefreshAsync(false,300);
        check("Observing accounts preserves the five-minute automatic poll minimum",client.Calls.Count==calls);
        coordinator.ObserveAccounts(false);await coordinator.RefreshAsync(true);
        check("Closing account settings returns polling to the island selection",client.Calls.Count==calls+2&&client.Calls.Skip(calls).OrderBy(id=>id).SequenceEqual(new[]{"antigravity","grok"}));
        using var feed=new UsageFeed(new LiveUsageCoordinator(new FakeClient()));
        check("Live feed removes all fixture plans, costs and quotas",!feed.IsDemo&&!feed.HasUpdated&&feed.Providers.All(p=>p.Costs.Length==0&&p.Limits.Length==0&&p.Plan.Length==0));
        var detachedClient=new FakeClient();var late=new TaskCompletionSource<UsageResult>(TaskCreationOptions.RunContinuationsAsynchronously);
        var detachedEntered=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        detachedClient.Next=(_,_)=>{detachedEntered.SetResult();return late.Task;};
        using var detached=new LiveUsageCoordinator(detachedClient);detached.Select(["codex"]);
        var detachedFlight=detached.RefreshAsync();await detachedEntered.Task;detached.Select(["grok"]);late.SetResult(first);await detachedFlight;
        detached.Dispose();detached.Dispose();
        check("Canceling into another selection leaves no disposed cancellation handle",detached.State("codex").UpdatedAt==null);
    }
    private static HttpResponseMessage Response(int status,string body="")=>new((HttpStatusCode)status){Content=new StringContent(body)};
    private sealed class FakeCredentials(CliCredential[] values) : ICliCredentials
    {
        internal int Reads;
        internal void Reset()=>Reads=0;
        public Task<CredentialRead> ReadAsync(string provider,string[] excludedTokens,CancellationToken cancellation)
        {cancellation.ThrowIfCancellationRequested();Reads++;return Task.FromResult(new CredentialRead(values.FirstOrDefault(v=>!excludedTokens.Contains(v.AccessToken))));}
    }
    private sealed class Handler(Func<HttpRequestMessage,CancellationToken,Task<HttpResponseMessage>> next) : HttpMessageHandler
    {
        internal Func<HttpRequestMessage,CancellationToken,Task<HttpResponseMessage>> Next=next;
        internal int Calls;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken cancellation){Calls++;return Next(request,cancellation);}
    }
    private sealed class FakeClient : IUsageClient
    {
        internal readonly List<string> Calls=new();
        internal Func<string,CancellationToken,Task<UsageResult>> Next=(_,_)=>Task.FromResult(new UsageResult(UsageStatus.NotConnected,[]));
        public Task<UsageResult> FetchAsync(string provider,CancellationToken cancellation){lock(Calls)Calls.Add(provider);return Next(provider,cancellation);}
    }
}

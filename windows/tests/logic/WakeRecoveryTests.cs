using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using IslandPrototype;

internal static class WakeRecoveryTests
{
    internal static async Task Run(Action<string,bool> check)
    {
        DateTimeOffset start=new(2030,1,1,0,0,0,TimeSpan.Zero),now=start;
        check("Wake recovery retains the Mac's one-minute grace and two-minute overdue tolerance",WakeScheduling.GraceDelay==TimeSpan.FromSeconds(60)&&WakeScheduling.OverdueSlack==TimeSpan.FromSeconds(120));
        check("An ordinary timer fire is not mistaken for wake",!WakeScheduling.IsOverdueFire(start,start)&&!WakeScheduling.IsOverdueFire(start.AddSeconds(30),start));
        check("The exact overdue tolerance does not defer a timer",!WakeScheduling.IsOverdueFire(start.AddSeconds(120),start));
        check("A late timer and a long sleep both enter wake recovery",WakeScheduling.IsOverdueFire(start.AddSeconds(121),start)&&WakeScheduling.IsOverdueFire(start.AddHours(6),start));
        check("An unarmed timer cannot imply a wake",!WakeScheduling.IsOverdueFire(start,null));
        var ready=new UsageResult(UsageStatus.Ready,[new("week",41,start.AddDays(7))],"pro","A");
        var client=new Client{Next=(_,_)=>Task.FromResult(ready)};
        using var live=new LiveUsageCoordinator(client,()=>now);live.Select(["codex"]);
        await live.RefreshAsync();live.Suspend();now=start.AddSeconds(200);live.Resume();
        check("Every wake arms a grace period even after a short nap",live.InWakeGrace&&live.AutomaticRetryAt==now.AddSeconds(60));
        now=now.AddSeconds(59);await live.RefreshAsync();
        check("Automatic polling cannot enter the post-wake burst",client.Calls.Count==1);
        now=now.AddSeconds(1);await live.RefreshAsync();
        check("A short nap does not cause an extra quota request",client.Calls.Count==1&&!live.InWakeGrace&&live.AutomaticRetryAt==null);
        now=start.AddSeconds(300);await live.RefreshAsync();
        check("The next regular poll remains eligible after a short nap",client.Calls.Count==2);
        live.Suspend();now=now.AddHours(1);live.Resume();var firstGrace=live.AutomaticRetryAt;
        now=now.AddSeconds(10);live.Resume();now=firstGrace!.Value;await live.RefreshAsync();
        check("Overlapping resume and catch-up events extend one shared grace",client.Calls.Count==2&&live.InWakeGrace);
        now=now.AddSeconds(10);await live.RefreshAsync();await live.RefreshAsync();
        check("Long-sleep recovery produces one fresh request after grace",client.Calls.Count==3&&live.State("codex").AttemptedAt==now&&live.AutomaticRetryAt==null);
        live.Suspend();now=now.AddHours(1);live.Resume();await live.RefreshAsync(true);
        check("An explicit manual refresh remains available during wake grace",client.Calls.Count==4&&live.InWakeGrace);
        now=now.AddSeconds(60);await live.RefreshAsync();
        check("A manual refresh during grace prevents a redundant wake request",client.Calls.Count==4);
        var targetedClient=new Client{Next=(_,_)=>Task.FromResult(ready)};
        using var targeted=new LiveUsageCoordinator(targetedClient,()=>now);targeted.Select(["codex"]);await targeted.RefreshAsync();
        now=now.AddMinutes(10);await targeted.RefreshAfterCredentialsAsync("claude");
        check("A credential change refreshes only its provider instead of other providers on a longer preset",targetedClient.Calls.SequenceEqual(new[]{"codex","claude"}));

        var limitedClient=new Client{Next=(_,_)=>Task.FromResult(new UsageResult(UsageStatus.RateLimited,[],AccountKey:"A",RetryAfter:TimeSpan.FromDays(2)))};
        using var limited=new LiveUsageCoordinator(limitedClient,()=>now);limited.Select(["codex"]);await limited.RefreshAsync();var retry=limited.State("codex").RetryAt;
        limited.Suspend();now=now.AddHours(1);limited.Resume();now=now.AddSeconds(60);await limited.RefreshAsync();
        check("Wake recovery never shortens the provider's Retry-After",limitedClient.Calls.Count==1&&limited.AutomaticRetryAt==retry);
        await limited.RefreshAfterCredentialsAsync("codex");await limited.NetworkChangedAsync(false);await limited.NetworkChangedAsync(true);
        check("Credential and network recovery cannot bypass a rate-limit cooldown",limitedClient.Calls.Count==1&&limited.AutomaticRetryAt==retry);
        now=retry!.Value;limited.Resume();await limited.RefreshAsync();
        check("A cooldown ending at wake also waits through the grace period",limitedClient.Calls.Count==1&&limited.AutomaticRetryAt==now.AddSeconds(60));
        now=now.AddSeconds(60);limitedClient.Next=(_,_)=>Task.FromResult(ready);await limited.RefreshAsync(false,1800);
        check("Cooldown recovery runs at the grace boundary even with the thirty-minute preset",limitedClient.Calls.Count==2&&limited.State("codex").Status==UsageStatus.Ready&&limited.AutomaticRetryAt==null);

        var reconnectClient=new Client{Next=(_,_)=>Task.FromResult(new UsageResult(UsageStatus.Offline,[],AccountKey:"A"))};
        using var reconnect=new LiveUsageCoordinator(reconnectClient,()=>now);reconnect.Select(["codex"]);
        await reconnect.NetworkChangedAsync(false);await reconnect.RefreshAsync();await reconnect.NetworkChangedAsync(false);
        check("Initial network state and repeated unavailable events do not duplicate startup requests",reconnectClient.Calls.Count==1);
        reconnectClient.Next=(_,_)=>Task.FromResult(ready);await reconnect.NetworkChangedAsync(true,1800);await reconnect.NetworkChangedAsync(true,1800);
        check("A failed startup refresh recovers once when the network returns",reconnectClient.Calls.Count==2&&reconnect.State("codex").Status==UsageStatus.Ready);
        reconnect.Suspend();now=now.AddSeconds(10);reconnect.Resume();await reconnect.NetworkChangedAsync(false);await reconnect.NetworkChangedAsync(true);
        now=now.AddSeconds(60);await reconnect.RefreshAsync();
        check("Network reassociation after a short sleep does not undercut the poll interval",reconnectClient.Calls.Count==2);
        reconnect.Suspend();reconnect.Resume();await reconnect.RefreshAfterCredentialsAsync("claude");
        check("Credential changes during wake grace remain queued without starting a request",reconnectClient.Calls.Count==2&&reconnect.AutomaticRetryAt==now.AddSeconds(60));
        now=now.AddSeconds(60);await reconnect.RefreshAsync();
        check("Deferred credential recovery refreshes only the changed provider when other data is fresh",reconnectClient.Calls.Count==3&&reconnectClient.Calls.Last()=="claude"&&reconnect.State("claude").Status==UsageStatus.Ready);

        var pending=new TaskCompletionSource<UsageResult>(TaskCreationOptions.RunContinuationsAsynchronously);
        var entered=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);CancellationToken requestToken=default;
        client.Next=(_,token)=>{requestToken=token;entered.SetResult();return pending.Task;};
        var inFlight=live.RefreshAsync(true);await entered.Task;live.Suspend();await live.RefreshAsync(true);
        check("Suspend cancels in-flight work and blocks new requests without discarding valid readings",requestToken.IsCancellationRequested&&!live.Loading&&client.Calls.Count==5&&live.State("codex").Windows is [{Used:41}]);
        pending.SetResult(new(UsageStatus.Offline,[],AccountKey:"A"));await inFlight;
        check("A request abandoned by sleep cannot publish a dead-socket error after cancellation",live.State("codex").Status==UsageStatus.Ready&&live.AutomaticRetryAt==null);

        await reconnect.NetworkChangedAsync(false);pending=new(TaskCreationOptions.RunContinuationsAsynchronously);entered=new(TaskCreationOptions.RunContinuationsAsynchronously);
        reconnectClient.Next=(_,token)=>{requestToken=token;entered.SetResult();return pending.Task;};
        inFlight=reconnect.RefreshAsync(true);await entered.Task;
        reconnectClient.Next=(_,_)=>Task.FromResult(ready with{Windows=[new("week",12,now.AddDays(5))]});await reconnect.NetworkChangedAsync(true);
        check("Network recovery replaces the request started on the dead connection",requestToken.IsCancellationRequested&&reconnect.State("codex").Windows is [{Used:12}]);
        pending.SetResult(new(UsageStatus.Offline,[],AccountKey:"A"));await inFlight;
        check("An obsolete network result cannot overwrite the recovered reading",reconnect.State("codex").Status==UsageStatus.Ready&&reconnect.State("codex").Windows is [{Used:12}]);
        pending=new(TaskCreationOptions.RunContinuationsAsynchronously);entered=new(TaskCreationOptions.RunContinuationsAsynchronously);
        reconnectClient.Next=(_,_)=>{entered.SetResult();return pending.Task;};
        inFlight=reconnect.RefreshAfterCredentialsAsync("codex");await entered.Task;reconnect.Suspend();reconnect.Resume();
        pending.SetResult(new(UsageStatus.Offline,[],AccountKey:"A"));await inFlight;
        int beforeRecovery=reconnectClient.Calls.Count;now=now.AddSeconds(60);reconnectClient.Next=(_,_)=>Task.FromResult(ready);await reconnect.RefreshAsync();
        check("A credential refresh interrupted by a short sleep is retried after grace even when older data is fresh",reconnectClient.Calls.Count==beforeRecovery+1&&reconnect.State("codex").Windows is [{Used:41}]);
        reconnect.Dispose();int calls=reconnectClient.Calls.Count;await reconnect.NetworkChangedAsync(false);await reconnect.NetworkChangedAsync(true);reconnect.Resume();await reconnect.RefreshAfterCredentialsAsync("codex");
        check("Late recovery signals do no work after the coordinator closes",reconnectClient.Calls.Count==calls&&reconnect.AutomaticRetryAt==null);
    }
    private sealed class Client:IUsageClient
    {
        internal readonly List<string> Calls=new();
        internal Func<string,CancellationToken,Task<UsageResult>> Next=(_,_)=>Task.FromResult(new UsageResult(UsageStatus.NotConnected,[]));
        public Task<UsageResult> FetchAsync(string provider,CancellationToken cancellation){Calls.Add(provider);return Next(provider,cancellation);}
    }
}

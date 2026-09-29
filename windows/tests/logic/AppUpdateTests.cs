using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using IslandPrototype;

internal static class AppUpdateTests
{
    internal static async Task Run(Action<string,bool> check)
    {
        string root=Path.Combine(Path.GetTempPath(),"IslandUpdateTests-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
        DateTimeOffset now=DateTimeOffset.Parse("2026-09-12T12:00:00Z");
        string journal=Path.Combine(root,"updates.json");var backend=new Backend();
        try {
            using(var updates=new AppUpdates(backend,journal,()=>now)) {
                await updates.CheckAsync(false);check("Automatic updates off performs no request",backend.Checks==0);
                await updates.CheckAsync(true);check("Manual check works with automatic updates off",backend.Checks==1&&updates.State.Phase==AppUpdatePhase.Available);
                check("Finding an update never downloads or installs it",backend.Downloads==0&&backend.Installs==0);
                check("Installing before download is rejected",!updates.PrepareInstall([])&&backend.Installs==0);
                updates.AutomaticChecks=true;await updates.CheckAsync(false);check("A successful check defers the next automatic request for one day",backend.Checks==1&&updates.NextAutomaticCheck==now.AddDays(1));
                now=now.AddDays(1);int notifications=0;updates.UpdateAvailable+=_=>notifications++;
                await updates.CheckAsync(false);now=now.AddDays(1);await updates.CheckAsync(false);
                check("Background checks notify once per available version",notifications==1);
                backend.CheckError=new IOException();await updates.CheckAsync(true);backend.CheckError=null;
                check("A failed recheck keeps the known update available",updates.State.Phase==AppUpdatePhase.Available&&updates.State.Error!=null);
                backend.DownloadError=new InvalidDataException();await updates.DownloadAsync();
                check("Failed verification keeps the current version and allows retry",updates.State.Phase==AppUpdatePhase.Available&&updates.State.Error?.Contains("verified")==true&&backend.Installs==0);
                backend.DownloadError=null;await updates.DownloadAsync();
                check("Successful download waits for an explicit restart",updates.State.Phase==AppUpdatePhase.Ready&&backend.Installs==0);
                backend.Progress?.Invoke(3);check("A late progress callback cannot overwrite ready state",updates.State.Phase==AppUpdatePhase.Ready&&updates.State.Progress==100);
                int requests=backend.Checks;now=now.AddDays(1);await updates.CheckAsync(false);
                check("Ready updates do not trigger more background requests",backend.Checks==requests);
                backend.CheckError=new IOException();await updates.CheckAsync(true);
                check("An offline manual check retains a downloaded update",updates.State.Phase==AppUpdatePhase.Ready&&updates.State.AvailableVersion=="0.0.2");
                backend.InstallError=new IOException();check("A failed restart keeps the update ready",!updates.PrepareInstall([])&&updates.State.Phase==AppUpdatePhase.Ready);
                backend.InstallError=null;
                check("Explicit restart queues the update with its data profile",updates.PrepareInstall(["--demo","--data-dir",root])&&backend.Arguments?[2]==root&&updates.State.Phase==AppUpdatePhase.Installing);
                check("Repeated restart requests cannot queue multiple installs",!updates.PrepareInstall([])&&backend.Installs==1);
            }
            using(var resumed=new AppUpdates(backend,journal,()=>now)) {
                check("Downloaded updates survive a process restart",resumed.State.Phase==AppUpdatePhase.Ready);
                check("Check timing survives a process restart",resumed.NextAutomaticCheck==now.AddHours(1));
            }
            backend=new Backend {CheckGate=new(TaskCreationOptions.RunContinuationsAsynchronously)};
            using(var updates=new AppUpdates(backend,Path.Combine(root,"coalescing.json"),()=>now)) {
                var first=updates.CheckAsync(true);await updates.CheckAsync(true);
                check("Concurrent checks share a single request",backend.Checks==1&&updates.State.Phase==AppUpdatePhase.Checking);
                backend.CheckGate.SetResult(null);await first;
                check("An empty successful check shows the installed version is current",updates.State.Phase==AppUpdatePhase.Current);
                backend.CheckGate=null;backend.CheckError=new IOException();now=now.AddMinutes(1);await updates.CheckAsync(true);
                check("A failed check reports an error and delays retry",updates.State.Phase==AppUpdatePhase.Error&&updates.NextAutomaticCheck==now.AddHours(1));
                backend.CheckError=new WindowsUpdateFeedUnavailableException();await updates.CheckAsync(true);
                check("An unpublished Windows feed is distinct from a connection failure",updates.State.Error?.Contains("not been published")==true);
            }
            backend=new Backend {CheckGate=new(TaskCreationOptions.RunContinuationsAsynchronously)};
            var disposed=new AppUpdates(backend,Path.Combine(root,"cancel.json"),()=>now);var checking=disposed.CheckAsync(true);disposed.Dispose();await checking;
            check("Closing the app cancels the active request",backend.Cancellation.IsCancellationRequested);
            backend=new Backend {IsInstalled=false};using(var portable=new AppUpdates(backend,Path.Combine(root,"portable.json"))) {
                await portable.CheckAsync(true);check("A portable preview cannot download an installer update",portable.State.Phase==AppUpdatePhase.Unavailable&&backend.Checks==0);
            }
        } finally {Directory.Delete(root,true);}
    }
    private sealed record Release(string Version):IAppUpdateRelease;
    private sealed class Backend:IAppUpdateBackend
    {
        public bool IsInstalled {get;set;}=true;
        public string CurrentVersion=>"0.0.1";
        public IAppUpdateRelease? PendingUpdate {get;private set;}
        internal int Checks,Downloads,Installs;
        internal Exception? CheckError,DownloadError,InstallError;
        internal Action<int>? Progress;
        internal string[]? Arguments;
        internal TaskCompletionSource<IAppUpdateRelease?>? CheckGate;
        internal CancellationToken Cancellation;
        public async Task<IAppUpdateRelease?> CheckAsync(CancellationToken cancellation)
        {
            Checks++;Cancellation=cancellation;if(CheckError!=null)throw CheckError;
            return CheckGate==null?new Release("0.0.2"):await CheckGate.Task.WaitAsync(cancellation);
        }
        public Task DownloadAsync(IAppUpdateRelease release,Action<int> progress,CancellationToken cancellation)
        {
            Downloads++;Progress=progress;progress(40);if(DownloadError!=null)throw DownloadError;
            PendingUpdate=release;return Task.CompletedTask;
        }
        public void InstallAfterExit(IAppUpdateRelease release,string[] arguments)
        {
            if(InstallError!=null)throw InstallError;Installs++;Arguments=arguments;
        }
    }
}

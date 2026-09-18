using System;
using System.IO;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace IslandPrototype;

internal enum AppUpdatePhase { Unavailable, Idle, Checking, Current, Available, Downloading, Ready, Installing, Error }
internal sealed class WindowsUpdateFeedUnavailableException : Exception;

internal interface IAppUpdateRelease
{
    string Version {get;}
}

internal interface IAppUpdateBackend
{
    bool IsInstalled {get;}
    string CurrentVersion {get;}
    IAppUpdateRelease? PendingUpdate {get;}
    Task<IAppUpdateRelease?> CheckAsync(CancellationToken cancellation);
    Task DownloadAsync(IAppUpdateRelease release,Action<int> progress,CancellationToken cancellation);
    void InstallAfterExit(IAppUpdateRelease release,string[] restartArguments);
}

internal sealed record AppUpdateState(AppUpdatePhase Phase,string CurrentVersion,string? AvailableVersion=null,int Progress=0,string? Error=null,DateTimeOffset? LastChecked=null)
{
    internal bool Busy=>Phase is AppUpdatePhase.Checking or AppUpdatePhase.Downloading or AppUpdatePhase.Installing;
}

internal sealed class AppUpdates : IDisposable
{
    internal static readonly TimeSpan CheckInterval=TimeSpan.FromDays(1);
    internal static readonly TimeSpan RetryInterval=TimeSpan.FromHours(1);
    private readonly IAppUpdateBackend backend;
    private readonly string journalPath;
    private readonly Func<DateTimeOffset> now;
    private readonly CancellationTokenSource lifetime=new();
    private readonly object stateLock=new();
    private AppUpdateState state;
    private IAppUpdateRelease? release;
    private CheckJournal journal;
    private int operation;
    private bool automatic,disposed;
    internal event Action? Changed;
    internal event Action<string>? UpdateAvailable;
    internal AppUpdateState State {get {lock(stateLock)return state;}}
    internal bool AutomaticChecks {
        get=>automatic;
        set {if(automatic==value)return;automatic=value;Changed?.Invoke();}
    }
    internal DateTimeOffset NextAutomaticCheck {
        get {
            if(journal.LastAttempt is not DateTimeOffset attempt)return now();
            if(attempt>now())return now();
            return attempt+(journal.LastChecked==attempt?CheckInterval:RetryInterval);
        }
    }

    internal AppUpdates(IAppUpdateBackend backend,string journalPath,Func<DateTimeOffset>? now=null)
    {
        this.backend=backend;this.journalPath=journalPath;this.now=now??(()=>DateTimeOffset.UtcNow);
        try {journal=JsonSerializer.Deserialize<CheckJournal>(File.ReadAllText(journalPath))??new();}
        catch(Exception error) when(error is IOException or UnauthorizedAccessException or JsonException){journal=new();}
        release=backend.PendingUpdate;
        state=new(!backend.IsInstalled?AppUpdatePhase.Unavailable:release==null?AppUpdatePhase.Idle:AppUpdatePhase.Ready,
            backend.CurrentVersion,release?.Version,LastChecked:journal.LastChecked);
    }

    internal async Task CheckAsync(bool manual)
    {
        if(disposed||!backend.IsInstalled||!manual&&(!automatic||now()<NextAutomaticCheck||State.Phase==AppUpdatePhase.Ready))return;
        if(Interlocked.CompareExchange(ref operation,1,0)!=0)return;
        var previous=State;
        try {
            Set(previous with {Phase=AppUpdatePhase.Checking,Error=null});
            var candidate=await backend.CheckAsync(lifetime.Token);
            if(disposed)return;
            var checkedAt=now();
            journal=journal with {LastAttempt=checkedAt,LastChecked=checkedAt};
            if(candidate==null) {
                release=backend.PendingUpdate;
                Set(new(release==null?AppUpdatePhase.Current:AppUpdatePhase.Ready,backend.CurrentVersion,release?.Version,LastChecked:checkedAt));
            } else {
                release=candidate;
                bool downloaded=backend.PendingUpdate?.Version==candidate.Version;
                Set(new(downloaded?AppUpdatePhase.Ready:AppUpdatePhase.Available,backend.CurrentVersion,candidate.Version,LastChecked:checkedAt));
                if(!manual&&automatic&&journal.NotifiedVersion!=candidate.Version) {
                    journal=journal with {NotifiedVersion=candidate.Version};
                    UpdateAvailable?.Invoke(candidate.Version);
                }
            }
            SaveJournal();
        } catch(OperationCanceledException) when(lifetime.IsCancellationRequested) {
        } catch(Exception error) {
            if(disposed)return;
            journal=journal with {LastAttempt=now()};SaveJournal();
            Set(previous with {Phase=previous.Phase is AppUpdatePhase.Ready or AppUpdatePhase.Available?previous.Phase:AppUpdatePhase.Error,
                Error=FailureMessage(error,false)});
        } finally {Interlocked.Exchange(ref operation,0);if(!disposed)Changed?.Invoke();}
    }

    internal async Task DownloadAsync()
    {
        if(disposed||release==null||State.Phase is not (AppUpdatePhase.Available or AppUpdatePhase.Error))return;
        if(Interlocked.CompareExchange(ref operation,1,0)!=0)return;
        var selected=release;
        try {
            Set(State with {Phase=AppUpdatePhase.Downloading,Progress=0,Error=null});
            await backend.DownloadAsync(selected,value=>{
                lock(stateLock) {
                    if(disposed||state.Phase!=AppUpdatePhase.Downloading)return;
                    state=state with {Progress=Math.Clamp(value,0,100)};
                }
                Changed?.Invoke();
            },lifetime.Token);
            if(!disposed)Set(State with {Phase=AppUpdatePhase.Ready,Progress=100});
        } catch(OperationCanceledException) when(lifetime.IsCancellationRequested) {
        } catch(Exception error) {
            if(!disposed)Set(State with {Phase=AppUpdatePhase.Available,Progress=0,Error=FailureMessage(error,true)});
        } finally {Interlocked.Exchange(ref operation,0);if(!disposed)Changed?.Invoke();}
    }

    internal bool PrepareInstall(string[] restartArguments)
    {
        if(disposed||release==null||State.Phase!=AppUpdatePhase.Ready||Interlocked.CompareExchange(ref operation,1,0)!=0)return false;
        try {
            backend.InstallAfterExit(release,restartArguments);
            Set(State with {Phase=AppUpdatePhase.Installing,Error=null});
            return true;
        } catch(Exception) {
            Set(State with {Error="The update could not start. Try again."});
            Interlocked.Exchange(ref operation,0);
            return false;
        }
    }

    private void Set(AppUpdateState next)
    {
        lock(stateLock){if(disposed)return;state=next;}
        Changed?.Invoke();
    }
    private static string FailureMessage(Exception error,bool downloading)=>error is WindowsUpdateFeedUnavailableException
        ?"Windows updates have not been published yet. Try again later."
        :error is InvalidDataException
        ?"The update could not be verified. Your current version has been kept."
        :downloading?"The update could not be downloaded. Check your connection and try again."
        :"Updates could not be checked. Check your connection and try again.";
    private void SaveJournal()
    {
        string temporary=journalPath+"."+Guid.NewGuid().ToString("N")+".tmp";
        try {Directory.CreateDirectory(Path.GetDirectoryName(journalPath)!);File.WriteAllText(temporary,JsonSerializer.Serialize(journal));File.Move(temporary,journalPath,true);}
        catch(Exception error) when(error is IOException or UnauthorizedAccessException){}
        finally {try{File.Delete(temporary);}catch(Exception error) when(error is IOException or UnauthorizedAccessException){}}
    }
    public void Dispose()
    {
        lock(stateLock){if(disposed)return;disposed=true;}
        lifetime.Cancel();
    }
    private sealed record CheckJournal(DateTimeOffset? LastAttempt=null,DateTimeOffset? LastChecked=null,string? NotifiedVersion=null);
}

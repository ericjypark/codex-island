using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Collections.Generic;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Velopack;
using Velopack.Locators;
using Velopack.Logging;
using Velopack.Sources;

namespace IslandPrototype;

internal sealed class WindowsUpdateBackend : IAppUpdateBackend
{
    internal const string Repository="https://github.com/ericjypark/codex-island";
    private readonly UpdateManager manager;
    private readonly UpdateDownloader downloader=new();
    public bool IsInstalled=>manager.IsInstalled&&!manager.IsPortable;
    public string CurrentVersion=>manager.CurrentVersion?.ToString()??typeof(App).Assembly.GetName().Version?.ToString(3)??"0.0.0";
    public IAppUpdateRelease? PendingUpdate=>IsInstalled&&manager.UpdatePendingRestart is { } asset?new Release(new UpdateInfo(asset,false)):null;

    internal WindowsUpdateBackend()
    {
        string? localFeed=typeof(App).Assembly.GetCustomAttributes<AssemblyMetadataAttribute>().FirstOrDefault(a=>a.Key=="WindowsUpdateTestFeed")?.Value;
        bool preview=VelopackLocator.Current.Channel?.EndsWith("-preview",StringComparison.Ordinal)==true;
        IUpdateSource source=string.IsNullOrEmpty(localFeed)
            ?new WindowsGithubSource(preview,downloader)
            :new SimpleFileSource(new DirectoryInfo(localFeed));
        manager=new UpdateManager(source,new UpdateOptions {AllowVersionDowngrade=false});
    }
    public async Task<IAppUpdateRelease?> CheckAsync(CancellationToken cancellation)
    {
        cancellation.ThrowIfCancellationRequested();
        using var timeout=CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        timeout.CancelAfter(TimeSpan.FromSeconds(90));downloader.CheckCancellation=timeout.Token;
        var update=await manager.CheckForUpdatesAsync().ConfigureAwait(false);
        cancellation.ThrowIfCancellationRequested();
        if(update==null)return null;
        Validate(update.TargetFullRelease);
        return new Release(update);
    }
    public async Task DownloadAsync(IAppUpdateRelease release,Action<int> progress,CancellationToken cancellation)
    {
        var update=((Release)release).Update;Validate(update.TargetFullRelease);
        try {await manager.DownloadUpdatesAsync(update,progress,cancellation);}
        catch(Velopack.Exceptions.ChecksumFailedException error){throw new InvalidDataException("The downloaded update failed verification.",error);}
    }
    public void InstallAfterExit(IAppUpdateRelease release,string[] restartArguments)
    {
        var asset=((Release)release).Update.TargetFullRelease;Validate(asset);
        manager.WaitExitThenApplyUpdates(asset,silent:false,restart:true,restartArgs:restartArguments);
    }
    private void Validate(VelopackAsset asset)
    {
        if(asset.PackageId!=manager.AppId||asset.Type!=VelopackAssetType.Full||asset.Version<=manager.CurrentVersion)
            throw new InvalidDataException("The update does not match this installation.");
    }
    private sealed record Release(UpdateInfo Update):IAppUpdateRelease
    {
        public string Version=>Update.TargetFullRelease.Version.ToString();
    }
    private sealed class UpdateDownloader:HttpClientFileDownloader
    {
        internal CancellationToken CheckCancellation {get;set;}
        public override async Task<byte[]> DownloadBytes(string url,IDictionary<string,string>? headers,double timeout)
        {
            using var client=CreateHttpClient(headers,1.0/3);
            return await client.GetByteArrayAsync(url,CheckCancellation).ConfigureAwait(false);
        }
        public override async Task<string> DownloadString(string url,IDictionary<string,string>? headers,double timeout)
        {
            using var client=CreateHttpClient(headers,1.0/3);
            return await client.GetStringAsync(url,CheckCancellation).ConfigureAwait(false);
        }
        public override async Task DownloadFile(string url,string targetFile,Action<int> progress,IDictionary<string,string>? headers,double timeout,CancellationToken cancelToken=default)
        {
            using var limit=CancellationTokenSource.CreateLinkedTokenSource(cancelToken);limit.CancelAfter(TimeSpan.FromMinutes(30));
            await base.DownloadFile(url,targetFile,progress,headers,timeout,limit.Token).ConfigureAwait(false);
        }
    }
    private sealed class WindowsGithubSource(bool preview,IFileDownloader downloader):GithubSource(Repository,null,preview,downloader)
    {
        private string? requestedChannel;
        protected override async Task<GithubRelease[]> GetReleases(bool includePrereleases)
        {
            // Mac-only releases must not hide the most recent Windows installer.
            var json=await Downloader.DownloadString("https://api.github.com/repos/ericjypark/codex-island/releases?per_page=100",GetRequestHeaders("application/vnd.github+json"));
            var releases=JsonSerializer.Deserialize<GithubRelease[]>(json)??[];
            string name="releases."+requestedChannel+".json";
            return releases.Where(r=>(includePrereleases||!r.Prerelease)&&r.Assets.Any(a=>a.Name==name)).OrderByDescending(r=>r.PublishedAt).Take(3).ToArray();
        }
        public override async Task<VelopackAssetFeed> GetReleaseFeed(IVelopackLogger logger,string? appId,string channel,Guid? stagingId=null,VelopackAsset? latestLocalRelease=null)
        {
            requestedChannel=channel;
            var feed=await base.GetReleaseFeed(logger,appId,channel,stagingId,latestLocalRelease);
            if(!feed.Assets.Any(a=>a.Type==VelopackAssetType.Full&&a.PackageId==appId))throw new WindowsUpdateFeedUnavailableException();
            if(feed.Assets.Any(a=>a.PackageId!=appId))throw new InvalidDataException("The update feed contains another application.");
            return feed;
        }
    }
}

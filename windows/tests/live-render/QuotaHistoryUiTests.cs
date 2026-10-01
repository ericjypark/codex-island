using System;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using IslandPrototype;

internal static class QuotaHistoryUiTests
{
    [DllImport("user32.dll")]private static extern IntPtr GetDC(IntPtr window);
    [DllImport("user32.dll")]private static extern int ReleaseDC(IntPtr window,IntPtr dc);
    [DllImport("gdi32.dll")]private static extern bool BitBlt(IntPtr destination,int x,int y,int width,int height,IntPtr source,int sourceX,int sourceY,uint flags);
    [DllImport("dwmapi.dll")]private static extern int DwmFlush();
    internal static async Task Run(string output,Action<string,bool> check,string? macQuota)
    {
        string directory=Path.Combine(Path.GetTempPath(),"CodexIslandQuotaUi-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(directory);
        string key=new CliCredential("fixture-token","quota-render").AccountKey;
        DateTimeOffset now=DateTimeOffset.UtcNow;double[] values=[0,12,6,42,18,31];
        string path=Path.Combine(directory,"quota.json");var store=new QuotaHistoryStore(path);
        for(int i=0;i<values.Length;i++)store.Record("codex",new(UsageStatus.Ready,[new("week",values[i],now.AddDays(5))],"pro",key),now.AddMinutes((i-values.Length+1)*5));
        var client=new Client(key);using var feed=new UsageFeed(new LiveUsageCoordinator(client,quotaHistory:new QuotaHistoryStore(path)));
        feed.Select(["claude","codex"]);await feed.RefreshAsync(true);
        var surface=new IslandVisual {Width=800,Height=226,Expanded=true,ContentOpacity=1,LogoOpacity=0,ChartStyle=4,Preferences=new IslandPreferences {LeftProvider="claude",RightProvider="codex"},Feed=feed};
        var window=new Window {Width=800,Height=226,Left=90,Top=170,WindowStyle=WindowStyle.None,AllowsTransparency=true,Background=Brushes.Transparent,ShowInTaskbar=false,Topmost=true,Content=surface,Title="CodexIsland recorded quota verification"};
        window.Show();window.Activate();
        async Task Capture(string name,double[] observed,bool remaining=false) {
            surface.Remaining=remaining;surface.InvalidateVisual();await Task.Delay(300);Marshal.ThrowExceptionForHR(DwmFlush());
            Point start=surface.PointToScreen(new Point()),end=surface.PointToScreen(new Point(800,226));double scale=(end.X-start.X)/800;
            using var bitmap=new System.Drawing.Bitmap((int)(end.X-start.X),(int)(end.Y-start.Y));
            using(var graphics=System.Drawing.Graphics.FromImage(bitmap)) {
                IntPtr source=GetDC(IntPtr.Zero),target=graphics.GetHdc();
                try{if(!BitBlt(target,0,0,bitmap.Width,bitmap.Height,source,(int)start.X,(int)start.Y,0x40CC0020))throw new Exception("Native quota capture failed.");}
                finally{graphics.ReleaseHdc(target);ReleaseDC(IntPtr.Zero,source);}
            }
            bitmap.Save(Path.Combine(output,name+"-panel.png"));
            using(var chart=bitmap.Clone(new System.Drawing.Rectangle((int)(467.5*scale),(int)(89*scale),(int)(240*scale),(int)(50*scale)),bitmap.PixelFormat))chart.Save(Path.Combine(output,name+"-plot.png"));
            bool Lit(double x,double y) {
                int cx=(int)(x*scale),cy=(int)(y*scale),radius=(int)Math.Ceiling(2*scale);
                for(int row=Math.Max(0,cy-radius);row<Math.Min(bitmap.Height,cy+radius+1);row++)for(int col=Math.Max(0,cx-radius);col<Math.Min(bitmap.Width,cx+radius+1);col++) {
                    var pixel=bitmap.GetPixel(col,row);if(pixel.B>120&&pixel.G>70&&pixel.B>pixel.R*1.35)return true;
                }
                return false;
            }
            var positions=Enumerable.Range(0,Math.Min(12,observed.Length)).Select(i=>(int)Math.Round(i*(observed.Length-1.0)/Math.Max(1,Math.Min(12,observed.Length)-1))).Distinct().ToArray();
            check(name+": native curve passes through the recorded samples",positions.All(index=>Lit(467.5+(observed.Length>1?index*240.0/(observed.Length-1):240),135-(remaining?100-observed[index]:observed[index])*.42)));
        }
        try {
            check("The rendered feed reloads all saved observations without a successful poll",feed.Provider("codex").Limits.Single().Observations!.SequenceEqual(values)&&feed.State("codex") is {Status:UsageStatus.Offline,FromHistory:true});
            await Capture("quota-history-used",values);
            await Capture("quota-history-remaining",values,true);
            check("Remaining mode retains the original stored used percentages",new QuotaHistoryStore(path).Latest("codex",key,now)?.Windows is [{Used:31}]&&feed.Provider("codex").Limits.Single().Observations!.SequenceEqual(values));
            check("A restart failure is visible beside restored readings",surface.AccessibleDescription.Contains("Could not refresh")&&surface.AccessibleDescription.Contains("week 69% remaining"));
            client.Next=new(UsageStatus.Ready,[new("week",null,null)],"pro",key);await feed.RefreshAsync(true);surface.InvalidateVisual();await Task.Delay(100);
            check("A missing current reading suppresses the recorded curve",surface.AccessibleDescription.Contains("week no reading")&&feed.Provider("codex").Limits.Single().Used==null);
            if(macQuota!=null) {
                using var data=JsonDocument.Parse(File.ReadAllBytes(macQuota));var source=data.RootElement;
                var raw=source.GetProperty("series").GetProperty("codex.weekly").EnumerateArray().ToArray();
                var samples=raw.Select(p=>new QuotaSample(DateTimeOffset.UnixEpoch.AddTicks((long)Math.Round(p.GetProperty("atMilliseconds").GetDouble()*10000)),p.GetProperty("used").GetDouble())).ToArray();
                string replayPath=Path.Combine(directory,"mac-quota-replay.json");
                var captured=new QuotaHistoryFile(1,[new("codex",key,samples[^1].At,null,[new("week",samples[^1].Used,null,SpanSeconds:604800)],[new("default","week",samples)])]);
                File.WriteAllText(replayPath,JsonSerializer.Serialize(captured));
                using var replay=new UsageFeed(new LiveUsageCoordinator(new Client(key),quotaHistory:new QuotaHistoryStore(replayPath)));replay.Select(["claude","codex"]);await replay.RefreshAsync(true);
                surface.Feed=replay;
                double[] expected=samples.Select(p=>p.Used).ToArray();
                check("Copied Mac quota observations survive the Windows cache without substitutions",replay.Provider("codex").Limits.Single().Observations!.SequenceEqual(expected));
                await Capture("mac-quota-used-windows",expected);
                await Capture("mac-quota-remaining-windows",expected,true);
                File.WriteAllText(Path.Combine(output,"mac-quota-replay-results.json"),JsonSerializer.Serialize(new{build=typeof(IslandVisual).Assembly.ManifestModule.ModuleVersionId,sourceSha256=source.GetProperty("sourceSha256").GetString(),series="codex.weekly",observations=expected.Length,firstAt=samples[0].At,lastAt=samples[^1].At,accountMode="isolated historical replay",valuesMatch=true,usedCurve=true,remainingCurve=true},new JsonSerializerOptions{WriteIndented=true}));
                surface.Feed=feed;
            }
        }finally{window.Close();Directory.Delete(directory,true);}
    }
    private sealed class Client(string account):IUsageClient,IUsageAccountReader
    {
        internal UsageResult? Next;
        public Task<string?> ReadAccountKeyAsync(string provider,CancellationToken cancellation)=>Task.FromResult(provider=="codex"?(string?)account:null);
        public Task<UsageResult> FetchAsync(string provider,CancellationToken cancellation)=>Task.FromResult(provider=="codex"?Next??new UsageResult(UsageStatus.Offline,[],AccountKey:account):new UsageResult(UsageStatus.NotConnected,[]));
    }
}

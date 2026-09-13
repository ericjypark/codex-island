using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace IslandPrototype;

internal static class CliAccountActions
{
    private static readonly HashSet<string> active=new();
    internal static event Action? Changed;
    internal static bool IsBusy(string provider)=>active.Contains(provider);
    internal static bool TryBegin(string provider)
    {
        if(!Supported(provider)||!active.Add(provider))return false;
        Changed?.Invoke();return true;
    }
    internal static void End(string provider){active.Remove(provider);Changed?.Invoke();}
    internal static bool Supported(string provider)=>provider is "codex" or "claude" or "grok" or "antigravity";
    internal static string Command(string provider)=>provider=="antigravity"?"agy":provider;
    internal static string InstallerUrl(string provider)=>provider switch {
        "codex"=>"https://chatgpt.com/codex/install.ps1",
        "claude"=>"https://claude.ai/install.ps1",
        "grok"=>"https://x.ai/cli/install.ps1",
        "antigravity"=>"https://antigravity.google/cli/install.ps1",
        _=>throw new ArgumentException("This provider does not have a Windows account connection.")
    };
    internal static string ActionLabel(string provider,bool installed,UsageStatus status)=>!installed
        ?provider switch {"codex"=>"Install Codex","claude"=>"Install Claude Code","grok"=>"Install Grok",_=>"Install Antigravity CLI"}
        :provider=="antigravity"&&status is UsageStatus.Ready or UsageStatus.Offline or UsageStatus.RateLimited or UsageStatus.Cached?"Open Antigravity CLI"
        :status is UsageStatus.Ready or UsageStatus.RateLimited or UsageStatus.Offline or UsageStatus.Cached?"Switch account"
        :status is UsageStatus.Expired or UsageStatus.NeedsLogin?"Sign in again"
        :provider switch {"codex"=>"Sign in with ChatGPT","claude"=>"Sign in with Claude","grok"=>"Sign in with Grok",_=>"Sign in with Google"};
    private static string Quote(string value)=>"'"+value.Replace("'","''")+"'";
    internal static string PowerShell=>Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),@"WindowsPowerShell\v1.0\powershell.exe");
    internal static string CurrentPath=>string.Join(Path.PathSeparator,new[]{Environment.GetEnvironmentVariable("PATH"),
        Environment.GetEnvironmentVariable("PATH",EnvironmentVariableTarget.User),Environment.GetEnvironmentVariable("PATH",EnvironmentVariableTarget.Machine)}.Where(p=>!string.IsNullOrWhiteSpace(p)));

    internal static string? FindExecutable(string provider)
    {
        if(!Supported(provider))return null;
        string profile=Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        string local=Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var locations=new List<string> {CurrentPath};
        if(provider=="codex")locations.Add(Environment.GetEnvironmentVariable("CODEX_INSTALL_DIR")??"");
        if(provider=="grok")locations.Add(Environment.GetEnvironmentVariable("GROK_BIN_DIR")??"");
        locations.Add(Path.Combine(profile,".grok","bin"));
        locations.Add(Path.Combine(local,"agy","bin"));
        locations.Add(Path.Combine(local,"Programs","OpenAI","Codex","bin"));
        locations.Add(Path.Combine(profile,".local","bin"));
        locations.Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),"npm"));
        locations.Add(Path.Combine(local,"Microsoft","WinGet","Links"));
        string? native=FindExecutable(provider,locations,File.Exists);
        return provider=="grok"&&native!=null?GrokCompatibility.Resolve(native):native;
    }
    internal static string? FindExecutable(string provider,IEnumerable<string> locations,Func<string,bool> exists)
    {
        if(!Supported(provider))return null;
        foreach(string entry in locations.SelectMany(p=>p.Split(Path.PathSeparator)).Distinct(StringComparer.OrdinalIgnoreCase)) {
            string directory=Environment.ExpandEnvironmentVariables(entry.Trim().Trim('"'));
            if(!Path.IsPathFullyQualified(directory))continue;
            foreach(string suffix in new[]{".exe",".cmd",".bat",".ps1"}) {
                string path=Path.Combine(directory,Command(provider)+suffix);
                if(exists(path))return path;
            }
        }
        return null;
    }

    internal static async Task InstallAsync(string provider)
    {
        string url=InstallerUrl(provider);
        if(FindExecutable(provider)!=null)return;
        string directory=Path.Combine(Path.GetTempPath(),"CodexIsland-setup-"+Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        try {
            using var http=new HttpClient {Timeout=TimeSpan.FromMinutes(2),MaxResponseContentBufferSize=4*1024*1024};
            byte[] bytes=await http.GetByteArrayAsync(url);
            string script=Path.Combine(directory,"install.ps1");
            await File.WriteAllBytesAsync(script,bytes);
            var start=new ProcessStartInfo(PowerShell) {UseShellExecute=false,CreateNoWindow=true,
                RedirectStandardOutput=true,RedirectStandardError=true,WorkingDirectory=directory};
            start.ArgumentList.Add("-NoProfile");start.ArgumentList.Add("-ExecutionPolicy");start.ArgumentList.Add("Bypass");
            start.ArgumentList.Add("-File");start.ArgumentList.Add(script);
            if(provider=="antigravity")start.ArgumentList.Add("--skip-aliases");
            start.Environment["CODEX_NON_INTERACTIVE"]="1";
            using var process=Process.Start(start)??throw new InvalidOperationException("The installer could not start.");
            Task output=DrainAsync(process.StandardOutput),errors=DrainAsync(process.StandardError);
            try {await process.WaitForExitAsync().WaitAsync(TimeSpan.FromMinutes(10));}
            catch(TimeoutException) {if(!process.HasExited)process.Kill(true);throw;}
            await Task.WhenAll(output,errors);
            if(process.ExitCode!=0||FindExecutable(provider)==null)throw new InvalidOperationException("Installation did not finish. Please retry.");
        } finally {
            try {Directory.Delete(directory,true);}catch(IOException){}catch(UnauthorizedAccessException){}
        }
    }
    private static async Task DrainAsync(StreamReader reader)
    {
        char[] buffer=new char[4096];while(await reader.ReadAsync(buffer)>0){}
    }
    internal static string LoginScript(string provider,string executable,string path)
    {
        if(!Supported(provider))throw new ArgumentException("Unsupported provider.");
        return "$ErrorActionPreference='Stop'; $env:PATH="+Quote(path)+"; try { & "+Quote(executable)
            +(provider switch {"codex" or "grok"=>" login","claude"=>" auth login",_=>""})+"; exit $LASTEXITCODE } catch { exit 1 }";
    }
    internal static async Task<bool> SignInAsync(string provider,bool waitForCredential=true)
    {
        string executable=FindExecutable(provider)??throw new InvalidOperationException("Install the CLI first.");
        if(provider=="grok")executable=await GrokCompatibility.PrepareAsync(executable);
        var start=new ProcessStartInfo(PowerShell) {UseShellExecute=true,WorkingDirectory=Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)};
        start.ArgumentList.Add("-NoProfile");start.ArgumentList.Add("-ExecutionPolicy");start.ArgumentList.Add("Bypass");
        start.ArgumentList.Add("-EncodedCommand");start.ArgumentList.Add(Convert.ToBase64String(Encoding.Unicode.GetBytes(LoginScript(provider,executable,CurrentPath))));
        var credentials=new FileCliCredentials();string before=credentials.ChangeStamp(provider);
        using var process=Process.Start(start)??throw new InvalidOperationException("Sign-in could not start.");
        if(provider=="antigravity") {
            if(!waitForCredential)return true;
            Task exit=process.WaitForExitAsync();
            while(!exit.IsCompleted) {
                await Task.WhenAny(exit,Task.Delay(2000));
                if(credentials.ChangeStamp(provider)!=before) {
                    var read=await credentials.ReadAsync(provider,[],CancellationToken.None);
                    if(read.Credential!=null&&read.Status!=UsageStatus.Expired)return true;
                }
            }
        }
        await process.WaitForExitAsync();return process.ExitCode==0;
    }
}

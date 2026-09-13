using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

namespace IslandPrototype;

internal static class CodexAccountReader
{
    internal static Task<UsageResult> ReadAsync(CancellationToken cancellation)=>ReadAsync(CliAccountActions.FindExecutable("codex"),cancellation);
    internal static async Task<UsageResult> ReadAsync(string? executable,CancellationToken cancellation)
    {
        if(executable==null)return new(UsageStatus.Unsupported,[]);
        using var timeout=CancellationTokenSource.CreateLinkedTokenSource(cancellation);timeout.CancelAfter(TimeSpan.FromSeconds(30));
        try {
            var start=StartInfo(executable);
            using var process=Process.Start(start)??throw new IOException("The Codex account reader could not start.");
            Task errors=DrainAsync(process.StandardError);
            try {return await ReadProtocolAsync(process.StandardOutput,process.StandardInput,timeout.Token);}
            finally {
                process.StandardInput.Close();
                try {await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(2));}
                catch(TimeoutException){if(!process.HasExited)process.Kill(true);}
                try {await errors.WaitAsync(TimeSpan.FromSeconds(2));}catch(Exception error) when(error is IOException or TimeoutException){}
            }
        } catch(OperationCanceledException) when(!cancellation.IsCancellationRequested){return new(UsageStatus.Offline,[]);}
        catch(Exception error) when(error is IOException or Win32Exception or InvalidOperationException){return new(UsageStatus.CredentialUnavailable,[]);}
        catch(JsonException){return new(UsageStatus.InvalidResponse,[]);}
    }
    internal static ProcessStartInfo StartInfo(string executable)
    {
        bool native=executable.EndsWith(".exe",StringComparison.OrdinalIgnoreCase);
        var start=new ProcessStartInfo(native?executable:CliAccountActions.PowerShell) {UseShellExecute=false,CreateNoWindow=true,
            RedirectStandardInput=true,RedirectStandardOutput=true,RedirectStandardError=true,
            StandardInputEncoding=new UTF8Encoding(false),StandardOutputEncoding=Encoding.UTF8,StandardErrorEncoding=Encoding.UTF8,
            WorkingDirectory=Path.GetTempPath()};
        if(native) {start.ArgumentList.Add("app-server");start.ArgumentList.Add("--listen");start.ArgumentList.Add("stdio://");}
        else {
            string script="$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); & '"+executable.Replace("'","''")+"' app-server --listen stdio://; exit $LASTEXITCODE";
            start.ArgumentList.Add("-NoProfile");start.ArgumentList.Add("-NonInteractive");start.ArgumentList.Add("-EncodedCommand");
            start.ArgumentList.Add(Convert.ToBase64String(Encoding.Unicode.GetBytes(script)));
        }
        return start;
    }
    internal static async Task<UsageResult> ReadProtocolAsync(TextReader reader,TextWriter writer,CancellationToken cancellation)
    {
        var channel=new JsonLines(reader,writer);
        var initialize=await channel.RequestAsync(1,"initialize",new {clientInfo=new {name="codexisland_windows",title="CodexIsland",version=typeof(CodexAccountReader).Assembly.GetName().Version?.ToString()??"0.0.0"}},cancellation);
        if(initialize.Error!=null)return new(initialize.Error.Value,[]);
        await channel.NotifyAsync("initialized",cancellation);
        var identity=await channel.RequestAsync(2,"account/read",new {refreshToken=false},cancellation);
        if(identity.Error!=null)return new(identity.Error.Value,[]);
        var account=identity.Result;
        if(account.ValueKind!=JsonValueKind.Object||!account.TryGetProperty("account",out var details))return new(UsageStatus.InvalidResponse,[]);
        if(details.ValueKind==JsonValueKind.Null)return new(UsageStatus.NotConnected,[]);
        if(details.ValueKind!=JsonValueKind.Object||FileCliCredentials.String(details,"type")==null)return new(UsageStatus.InvalidResponse,[]);
        if(FileCliCredentials.String(details,"type")!="chatgpt")return new(UsageStatus.NotConnected,[]);
        string? plan=FileCliCredentials.String(details,"planType");
        var usage=await channel.RequestAsync(3,"account/rateLimits/read",new {supportsLunaReserve=false,excludeResetCreditDetails=false},cancellation);
        return usage.Error!=null?new(usage.Error.Value,[],plan):Parse(usage.Result,plan);
    }
    internal static UsageResult Parse(JsonElement root,string? fallbackPlan=null)
    {
        if(root.ValueKind!=JsonValueKind.Object)return new(UsageStatus.InvalidResponse,[]);
        JsonElement snapshot=default;
        if(root.TryGetProperty("rateLimitsByLimitId",out var groups)&&groups.ValueKind==JsonValueKind.Object&&groups.TryGetProperty("codex",out var codex))snapshot=codex;
        else if(root.TryGetProperty("rateLimits",out var legacy))snapshot=legacy;
        if(snapshot.ValueKind!=JsonValueKind.Object)return new(UsageStatus.InvalidResponse,[]);
        var windows=new List<LiveWindow>();
        foreach(string name in new[]{"primary","secondary"}) {
            if(!snapshot.TryGetProperty(name,out var window)||window.ValueKind==JsonValueKind.Null)continue;
            if(window.ValueKind!=JsonValueKind.Object)return new(UsageStatus.InvalidResponse,[]);
            double? duration=Number(window,"windowDurationMins"),used=Number(window,"usedPercent");
            string label=duration.HasValue?(duration>=1440?"week":"5h"):name=="primary"?"5h":"week";
            DateTimeOffset? reset=CodexResetCredits.Date(window,"resetsAt");
            if(windows.All(w=>w.Label!=label))windows.Add(new(label,used>=0?Math.Min(100,used.Value):null,reset,SpanSeconds:duration is >0 and <=44640?duration*60:null));
        }
        string? account=FileCliCredentials.String(root,"accountId");
        string? key=string.IsNullOrWhiteSpace(account)?null:Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes("account:"+account)));
        return new(UsageStatus.Ready,windows.OrderBy(w=>w.Label=="5h"?0:1).ToArray(),FileCliCredentials.String(snapshot,"planType")??fallbackPlan,key,
            ResetCredits:root.TryGetProperty("rateLimitResetCredits",out var credits)?CodexResetCredits.Parse(credits,true):null);
    }
    private static double? Number(JsonElement root,string name)=>root.TryGetProperty(name,out var value)&&value.ValueKind==JsonValueKind.Number&&value.TryGetDouble(out double number)&&double.IsFinite(number)?number:null;
    internal static UsageStatus ErrorStatus(JsonElement error)
    {
        if(error.ValueKind!=JsonValueKind.Object)return UsageStatus.InvalidResponse;
        string message=FileCliCredentials.String(error,"message")??"";
        if(error.TryGetProperty("code",out var code)) {
            if(code.ValueKind!=JsonValueKind.Number||!code.TryGetInt32(out int number))return UsageStatus.InvalidResponse;
            if(number==-32601)return UsageStatus.Unsupported;
        }
        if(Regex.IsMatch(message,@"\b429\b|rate.?limit|too many requests",RegexOptions.IgnoreCase))return UsageStatus.RateLimited;
        if(Regex.IsMatch(message,@"\b401\b|unauthorized|not (?:logged|signed) in|token.{0,20}expired",RegexOptions.IgnoreCase))return UsageStatus.Expired;
        if(Regex.IsMatch(message,@"\b403\b|forbidden",RegexOptions.IgnoreCase))return UsageStatus.AccessDenied;
        return UsageStatus.Offline;
    }
    private static async Task DrainAsync(TextReader reader)
    {
        char[] buffer=new char[4096];while(await reader.ReadAsync(buffer)>0){}
    }
    private sealed class JsonLines(TextReader reader,TextWriter writer)
    {
        private readonly char[] buffer=new char[4096];
        private int offset,length,total;
        internal async Task NotifyAsync(string method,CancellationToken cancellation)
        {
            await writer.WriteLineAsync(JsonSerializer.Serialize(new {method}).AsMemory(),cancellation);await writer.FlushAsync(cancellation);
        }
        internal async Task<(JsonElement Result,UsageStatus? Error)> RequestAsync(int id,string method,object parameters,CancellationToken cancellation)
        {
            await writer.WriteLineAsync(JsonSerializer.Serialize(new {id,method,@params=parameters}).AsMemory(),cancellation);await writer.FlushAsync(cancellation);
            for(int count=0;count<256;count++) {
                string line=await LineAsync(cancellation);
                if(string.IsNullOrWhiteSpace(line))continue;
                using var document=ParseLine(line);var root=document.RootElement;
                if(root.ValueKind!=JsonValueKind.Object)throw new JsonException("Invalid CLI protocol response.");
                if(!root.TryGetProperty("id",out var responseId))continue;
                if(root.TryGetProperty("method",out _))throw new IOException("The account reader received an unexpected request.");
                if(responseId.ValueKind!=JsonValueKind.Number||!responseId.TryGetInt32(out int value)||value!=id)continue;
                if(root.TryGetProperty("error",out var error))return (default,ErrorStatus(error));
                return root.TryGetProperty("result",out var result)?(result.Clone(),null):(default,UsageStatus.InvalidResponse);
            }
            throw new IOException("Too many CLI protocol messages.");
        }
        private static JsonDocument ParseLine(string line)
        {
            try{return JsonDocument.Parse(line);}
            catch(JsonException){throw new JsonException("Invalid CLI protocol response.");}
        }
        private async Task<string> LineAsync(CancellationToken cancellation)
        {
            var text=new StringBuilder();
            while(true) {
                cancellation.ThrowIfCancellationRequested();
                if(offset==length) {
                    length=await reader.ReadAsync(buffer.AsMemory(),cancellation);offset=0;
                    if(length==0)throw new IOException("The Codex account reader closed unexpectedly.");
                    total+=length;if(total>8*1024*1024)throw new IOException("CLI protocol size limit exceeded.");
                }
                char next=buffer[offset++];
                if(next=='\n')return text.ToString();
                if(text.Length>=2*1024*1024)throw new IOException("CLI protocol message size limit exceeded.");
                text.Append(next);
            }
        }
    }
}

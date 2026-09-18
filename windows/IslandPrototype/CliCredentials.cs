using System;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

namespace IslandPrototype;

internal sealed class CliCredential
{
    internal readonly string AccessToken;
    internal readonly string AccountKey;
    internal readonly string? Plan;
    internal readonly string? UserId;
    internal CliCredential(string token,string? account=null,string? plan=null,string? userId=null)
    {
        AccessToken=token;Plan=plan;UserId=userId;
        AccountKey=Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(string.IsNullOrWhiteSpace(account)?"token:"+token:"account:"+account)));
    }
    public override string ToString()=>"[credential redacted]";
}
internal sealed record CredentialRead(CliCredential? Credential,UsageStatus Status=UsageStatus.NotConnected);
internal interface ICliCredentials
{
    Task<CredentialRead> ReadAsync(string provider,string[] excludedTokens,CancellationToken cancellation);
}
internal sealed class FileCliCredentials : ICliCredentials
{
    private readonly string profile;
    private readonly Func<string,string?> environment;
    private readonly Func<byte[]?> antigravityCredential;
    internal FileCliCredentials(string? profile=null,Func<string,string?>? environment=null,Func<byte[]?>? antigravityCredential=null)
    {
        this.profile=profile??Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        this.environment=environment??Environment.GetEnvironmentVariable;
        this.antigravityCredential=antigravityCredential??WindowsCliCredential.ReadAntigravity;
    }
    internal string ChangeStamp(string provider)
    {
        if(provider=="antigravity")return WindowsCliCredential.AntigravityStamp();
        string variable=provider switch {"codex"=>"CODEX_HOME","claude"=>"CLAUDE_CONFIG_DIR","grok"=>"GROK_HOME",_=>""};
        if(variable.Length==0)return "unsupported";
        string? configured=environment(variable);
        string directory=string.IsNullOrWhiteSpace(configured)?Path.Combine(profile,"."+provider):configured;
        return Stamp(Path.Combine(directory,provider=="claude"?".credentials.json":"auth.json"))
            +(provider=="codex"?"|"+Stamp(Path.Combine(directory,"config.toml"))+"|"+Stamp(Path.Combine(directory,"secrets","codex_auth.age")):"");
    }
    private static string Stamp(string path)
    {
        try {
            var file=new FileInfo(path);
            return file.Exists?file.CreationTimeUtc.Ticks+":"+file.LastWriteTimeUtc.Ticks+":"+file.Length:"missing";
        } catch(Exception error) when(error is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException){return "unavailable";}
    }
    public Task<CredentialRead> ReadAsync(string provider,string[] excludedTokens,CancellationToken cancellation)=>Task.Run(()=>{
        cancellation.ThrowIfCancellationRequested();
        if(provider is not ("codex" or "claude" or "grok" or "antigravity"))return new CredentialRead(null,UsageStatus.Unsupported);
        try {
            if(provider=="antigravity") {
                byte[]? bytes=antigravityCredential();
                if(bytes==null)return new CredentialRead(null);
                try {return ProviderCredentialParser.Antigravity(bytes,excludedTokens,DateTimeOffset.UtcNow);}
                finally {CryptographicOperations.ZeroMemory(bytes);}
            }
            if(provider=="grok") {
                string grokHome=environment("GROK_HOME")??Path.Combine(profile,".grok");
                if(string.IsNullOrWhiteSpace(grokHome))grokHome=Path.Combine(profile,".grok");
                string? grokJson=ReadBounded(Path.Combine(grokHome,"auth.json"));
                return grokJson==null?new CredentialRead(null):ProviderCredentialParser.Grok(grokJson,excludedTokens,DateTimeOffset.UtcNow);
            }
            string directory=environment(provider=="codex"?"CODEX_HOME":"CLAUDE_CONFIG_DIR")??Path.Combine(profile,provider=="codex"?".codex":".claude");
            if(string.IsNullOrWhiteSpace(directory))directory=Path.Combine(profile,provider=="codex"?".codex":".claude");
            string? envToken=provider=="claude"?environment("CLAUDE_CODE_OAUTH_TOKEN"):null;
            if(ValidToken(envToken)&&!excludedTokens.Contains(envToken!))return new CredentialRead(new CliCredential(envToken!));
            if(provider=="codex") {
                string? config=ReadBounded(Path.Combine(directory,"config.toml"));
                if(config!=null) {
                    string top=string.Join('\n',config.Split('\n').TakeWhile(line=>!line.TrimStart().StartsWith('[')));
                    var mode=Regex.Match(top,"(?m)^\\s*cli_auth_credentials_store\\s*=\\s*[\"']([^\"']+)[\"']");
                    if(mode.Success&&mode.Groups[1].Value!="file")return new CredentialRead(null,UsageStatus.Unsupported);
                }
            }
            string? json=ReadBounded(Path.Combine(directory,provider=="codex"?"auth.json":".credentials.json"));
            if(json==null)return new CredentialRead(null);
            using var doc=JsonDocument.Parse(json);
            JsonElement root=doc.RootElement;
            string objectName=provider=="codex"?"tokens":"claudeAiOauth";
            if(root.ValueKind!=JsonValueKind.Object||!root.TryGetProperty(objectName,out var tokenData)||tokenData.ValueKind!=JsonValueKind.Object)return new CredentialRead(null);
            string? token=String(tokenData,provider=="codex"?"access_token":"accessToken");
            if(!ValidToken(token)||excludedTokens.Contains(token!))return new CredentialRead(null);
            string? account=provider=="codex"?String(tokenData,"account_id"):Subject(token!);
            return new CredentialRead(new CliCredential(token!,account,provider=="claude"?String(tokenData,"subscriptionType"):null));
        } catch(Exception error) when(error is IOException or UnauthorizedAccessException or JsonException or ArgumentException or NotSupportedException) {
            return new CredentialRead(null,UsageStatus.CredentialUnavailable);
        }
    },cancellation);
    internal static string? ReadBounded(string path)
    {
        try {
            using var stream=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete);
            if(stream.Length>1024*1024)throw new IOException("Credential file exceeds size limit.");
            using var reader=new StreamReader(stream,Encoding.UTF8,true,4096);
            char[] text=new char[1024*1024+1];int count=reader.ReadBlock(text,0,text.Length);
            if(count>1024*1024)throw new IOException("Credential file exceeds size limit.");
            return new string(text,0,count);
        } catch(FileNotFoundException){return null;}catch(DirectoryNotFoundException){return null;}
    }
    internal static bool ValidToken(string? value)=>value is {Length:>0 and <=65536}&&value.All(c=>c>=33&&c<=126);
    internal static string? String(JsonElement obj,string key)=>obj.ValueKind==JsonValueKind.Object&&obj.TryGetProperty(key,out var value)&&value.ValueKind==JsonValueKind.String?value.GetString():null;
    private static string? Subject(string token)
    {
        try {
            var parts=token.Split('.');if(parts.Length!=3||parts[1].Length>32000)return null;
            string payload=parts[1].Replace('-','+').Replace('_','/');payload=payload.PadRight((payload.Length+3)/4*4,'=');
            using var doc=JsonDocument.Parse(Convert.FromBase64String(payload));
            return String(doc.RootElement,"sub");
        } catch(Exception error) when(error is FormatException or JsonException){return null;}
    }
}

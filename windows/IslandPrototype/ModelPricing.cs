using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;

namespace IslandPrototype;

internal sealed record ModelRates(double Input,double Output,double CacheWrite,double CacheRead,string? DisplayName=null)
{
    internal double Cost(TokenRecord e)=>(e.Input/1_000_000.0)*Input+(e.Output/1_000_000.0)*Output+(e.CacheWrite/1_000_000.0)*CacheWrite+(e.CacheRead/1_000_000.0)*CacheRead;
}
internal sealed class ModelPricing : IDisposable
{
    internal const string Endpoint="https://ericjypark.github.io/codex-island-model-catalog/v1/models.json";
    private sealed record Cached(string Payload,string? ETag,DateTimeOffset FetchedAt);
    private readonly Dictionary<string,ModelRates> seed;
    private Dictionary<string,ModelRates> remote=new();
    private readonly string path;
    private readonly HttpClient client;
    private readonly CancellationTokenSource lifetime=new();
    private readonly object gate=new();
    private Cached? cached;
    private DateTimeOffset? attemptedAt;
    private Task<bool>? running;
    internal DateTimeOffset? UpdatedAt=>cached?.FetchedAt;
    internal ModelPricing(string? path=null,HttpMessageHandler? handler=null,Dictionary<string,ModelRates>? seed=null)
    {
        this.path=path??DataPaths.File("model-prices.json");
        client=handler==null?new HttpClient():new HttpClient(handler);client.Timeout=TimeSpan.FromSeconds(15);
        if(seed!=null)this.seed=seed;
        else {
            using var stream=Application.GetResourceStream(new Uri("/Assets/pricing-seed.json",UriKind.Relative))!.Stream;
            using var reader=new StreamReader(stream);this.seed=Parse(reader.ReadToEnd());
        }
        try {
            if(File.Exists(this.path)&&new FileInfo(this.path).Length<=4_194_304) {
                var value=JsonSerializer.Deserialize<Cached>(File.ReadAllText(this.path));
                if(value!=null){remote=Parse(value.Payload);cached=value;}
            }
        }catch(Exception e) when(e is IOException or UnauthorizedAccessException or JsonException or InvalidDataException){}
    }
    internal ModelRates? Rates(string raw,DateTimeOffset timestamp)
    {
        string model=Canonical(raw);
        if(model is "gemini-3.6-flash" or "gemini-3.7-flash" or "gemini-3.8-flash") {
            double factor=timestamp.ToUnixTimeSeconds()<1_798_761_600?1:2;return new(.75*factor,3.75*factor,.75*factor,.075*factor);
        }
        lock(gate)return remote.GetValueOrDefault(model)??seed.GetValueOrDefault(model);
    }
    internal string Pretty(string model)
    {
        string? display;lock(gate)display=remote.GetValueOrDefault(model)?.DisplayName;
        if(!string.IsNullOrEmpty(display))return display;
        if(model.StartsWith("claude-",StringComparison.Ordinal)) {
            string trimmed=model[7..];int dash=trimmed.IndexOf('-');
            string family=dash<0?trimmed:trimmed[..dash];if(family.Length>0)family=char.ToUpperInvariant(family[0])+family[1..];
            return dash<0?family:family+" "+trimmed[(dash+1)..].Replace('-','.');
        }
        if(model.StartsWith("gpt-",StringComparison.Ordinal))return "GPT-"+model[4..];
        if(model.Length>1&&model[0]=='o'&&char.IsDigit(model[1]))return "O"+model[1..];return model;
    }
    internal static string Canonical(string raw)
    {
        if(raw.StartsWith("claude-",StringComparison.Ordinal)&&raw.EndsWith("-thinking",StringComparison.Ordinal))raw=raw[..^9];
        return Regex.Replace(raw,"-[0-9]{8}$","");
    }
    internal static bool IsInternalUsage(string raw)=>Canonical(raw)=="codex-auto-review";
    internal static Dictionary<string,ModelRates> Parse(string payload)
    {
        using var document=JsonDocument.Parse(payload);var root=document.RootElement;
        var schema=LocalLogScanner.Get(root,"schemaVersion");var models=LocalLogScanner.Get(root,"models");
        if(schema.ValueKind!=JsonValueKind.Number||!schema.TryGetInt32(out int version)||version!=1||models.ValueKind!=JsonValueKind.Object)throw new InvalidDataException("Unsupported price catalog.");
        var result=new Dictionary<string,ModelRates>();
        foreach(var model in models.EnumerateObject()) {
            if(string.IsNullOrWhiteSpace(model.Name)||model.Name.Length>512||result.ContainsKey(model.Name))throw new InvalidDataException("Invalid model catalog.");
            double Rate(string key) {
                var field=LocalLogScanner.Get(model.Value,key);
                if(field.ValueKind!=JsonValueKind.Number||!field.TryGetDouble(out double n)||!double.IsFinite(n)||n<0||n>1e9)throw new InvalidDataException("Invalid model rate.");return n;
            }
            result[model.Name]=new(Rate("inputPerMillion"),Rate("outputPerMillion"),Rate("cacheCreationPerMillion"),Rate("cacheReadPerMillion"),LocalLogScanner.String(model.Value,"displayName"));
        }
        if(result.Count==0)throw new InvalidDataException("Empty model catalog.");return result;
    }
    internal Task<bool> RefreshAsync(DateTimeOffset now,bool force=false)
    {
        lock(gate) {
            if(lifetime.IsCancellationRequested)return Task.FromResult(false);
            if(running!=null)return running;
            if(!force&&(cached!=null&&now-cached.FetchedAt<TimeSpan.FromDays(1)||attemptedAt!=null&&now-attemptedAt<TimeSpan.FromHours(6)))return Task.FromResult(false);
            attemptedAt=now;return running=FetchAsync(now);
        }
    }
    private async Task<bool> FetchAsync(DateTimeOffset now)
    {
        await Task.Yield();
        try {
            using var request=new HttpRequestMessage(HttpMethod.Get,Endpoint);
            if(cached?.ETag is string etag)request.Headers.TryAddWithoutValidation("If-None-Match",etag);
            using var response=await client.SendAsync(request,HttpCompletionOption.ResponseHeadersRead,lifetime.Token);
            Cached next;Dictionary<string,ModelRates>? rates=null;
            if(response.StatusCode==HttpStatusCode.NotModified&&cached!=null)next=cached with {FetchedAt=now};
            else {
                if(response.StatusCode!=HttpStatusCode.OK||response.Content.Headers.ContentLength>2_097_152)return false;
                using var stream=await response.Content.ReadAsStreamAsync(lifetime.Token);using var bytes=new MemoryStream();byte[] buffer=new byte[16_384];int count;
                while((count=await stream.ReadAsync(buffer,lifetime.Token))>0) {if(bytes.Length+count>2_097_152)return false;bytes.Write(buffer,0,count);}
                string payload=System.Text.Encoding.UTF8.GetString(bytes.ToArray());rates=Parse(payload);next=new(payload,response.Headers.ETag?.ToString(),now);
            }
            lock(gate){if(rates!=null)remote=rates;cached=next;}
            string temporary=path+"."+Guid.NewGuid().ToString("N")+".tmp";
            try {
                string? directory=Path.GetDirectoryName(path);if(!string.IsNullOrEmpty(directory))Directory.CreateDirectory(directory);
                await File.WriteAllTextAsync(temporary,JsonSerializer.Serialize(next),lifetime.Token);File.Move(temporary,path,true);
            }catch(Exception e) when(e is IOException or UnauthorizedAccessException){}
            finally{try{File.Delete(temporary);}catch(IOException){}catch(UnauthorizedAccessException){}}
            return rates!=null;
        }catch(Exception e) when(e is HttpRequestException or IOException or JsonException or InvalidDataException or OperationCanceledException){return false;}
        finally{lock(gate)running=null;}
    }
    public void Dispose(){lifetime.Cancel();client.Dispose();}
}

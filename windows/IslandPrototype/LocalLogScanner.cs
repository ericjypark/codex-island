using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading;

namespace IslandPrototype;

internal interface ILocalLogScanner
{
    HistoryScan Scan(string source,DateTimeOffset now,CancellationToken cancellation);
}

internal sealed class LocalLogScanner : ILocalLogScanner
{
    private readonly string profile;
    private readonly Func<string,string?> environment;
    private sealed record Cached(long Length,DateTime Modified,HistoryScan Scan);
    private readonly ConcurrentDictionary<string,Cached> cache=new(StringComparer.OrdinalIgnoreCase);
    internal LocalLogScanner(string? profile=null,Func<string,string?>? environment=null)
    {
        this.profile=profile??Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        this.environment=environment??Environment.GetEnvironmentVariable;
    }
    private string Home(string variable,string fallback)=>string.IsNullOrWhiteSpace(environment(variable))?fallback:environment(variable)!;
    internal string[] Roots(string source)=>source switch {
        "codex"=>[Path.Combine(Home("CODEX_HOME",Path.Combine(profile,".codex")),"sessions")],
        "claude"=>string.IsNullOrWhiteSpace(environment("CLAUDE_CONFIG_DIR"))
            ?[Path.Combine(profile,".claude","projects"),Path.Combine(profile,".config","claude","projects")]
            :environment("CLAUDE_CONFIG_DIR")!.Split(',',StringSplitOptions.RemoveEmptyEntries|StringSplitOptions.TrimEntries).Select(p=>Path.Combine(p,"projects")).ToArray(),
        "grok"=>[Path.Combine(Home("GROK_HOME",Path.Combine(profile,".grok")),"sessions")],
        "antigravity"=>[Path.Combine(profile,".gemini","antigravity-cli","conversations")],
        "opencode"=>[Path.Combine(Home("XDG_DATA_HOME",Path.Combine(profile,".local","share")),"opencode")],_=>[]};
    public HistoryScan Scan(string source,DateTimeOffset now,CancellationToken cancellation)
    {
        if(source is "antigravity" or "opencode")return DatabaseLogScanner.Scan(source,Roots(source),now,cancellation);
        var records=new Dictionary<string,TokenRecord>();int files=0,unreadable=0,skipped=0;
        var visited=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach(string root in Roots(source).Distinct(StringComparer.OrdinalIgnoreCase)) {
            foreach(string file in Files(root,p=>source=="codex"?Path.GetFileName(p).StartsWith("rollout-",StringComparison.Ordinal)&&p.EndsWith(".jsonl",StringComparison.OrdinalIgnoreCase)
                :source=="grok"?Path.GetFileName(p)=="updates.jsonl":p.EndsWith(".jsonl",StringComparison.OrdinalIgnoreCase),()=>unreadable++,cancellation)) {
                cancellation.ThrowIfCancellationRequested();if(!visited.Add(file))continue;files++;
                try {
                    var before=new FileInfo(file);
                    HistoryScan parsed;
                    if(cache.TryGetValue(file,out var hit)&&hit.Length==before.Length&&hit.Modified==before.LastWriteTimeUtc)parsed=hit.Scan;
                    else {
                        parsed=ParseFile(source,file,cancellation);var after=new FileInfo(file);
                        if(before.Length==after.Length&&before.LastWriteTimeUtc==after.LastWriteTimeUtc)cache[file]=new(before.Length,before.LastWriteTimeUtc,parsed);
                    }
                    skipped+=parsed.SkippedRecords;
                    foreach(var e in parsed.Events.Where(e=>e.Valid(now))) {
                        if(!records.TryGetValue(e.Id,out var previous)||source!="claude"||e.Dominates(previous))records[e.Id]=e;
                    }
                }catch(Exception e) when(e is IOException or UnauthorizedAccessException or ArgumentException){unreadable++;}
            }
        }
        foreach(string stale in cache.Keys.Where(p=>!visited.Contains(p)&&Roots(source).Any(r=>p.StartsWith(r+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))).ToArray())cache.TryRemove(stale,out _);
        return new(records.Values.ToArray(),files,unreadable,skipped);
    }
    internal static IEnumerable<string> Files(string root,Func<string,bool> match,Action unreadable,CancellationToken cancellation)
    {
        var pending=new Stack<string>();pending.Push(root);
        while(pending.Count>0) {
            cancellation.ThrowIfCancellationRequested();string directory=pending.Pop();string[] entries;
            try{entries=Directory.GetFileSystemEntries(directory);Array.Sort(entries,StringComparer.Ordinal);}
            catch(DirectoryNotFoundException){continue;}
            catch(Exception e) when(e is IOException or UnauthorizedAccessException){unreadable();continue;}
            foreach(string path in entries) {
                FileAttributes flags;
                try{flags=File.GetAttributes(path);}catch(Exception e) when(e is IOException or UnauthorizedAccessException){unreadable();continue;}
                if((flags&FileAttributes.ReparsePoint)!=0)continue;
                if((flags&FileAttributes.Directory)!=0)pending.Push(path);else if(match(path))yield return path;
            }
        }
    }
    private static HistoryScan ParseFile(string source,string file,CancellationToken cancellation)
    {
        var records=new Dictionary<string,TokenRecord>();var occurrences=new Dictionary<long,int>();int skipped=0;string model="gpt-5.4";
        foreach(byte[] line in Lines(file,source=="grok"?2_097_152:1_048_576,()=>skipped++,cancellation)) {
            if(line.Length==0)continue;
            try {
                using var doc=JsonDocument.Parse(line,new JsonDocumentOptions{MaxDepth=96});var row=doc.RootElement;
                if(source=="codex") {
                    var payload=Get(row,"payload");
                    if(String(row,"type")=="turn_context"){model=String(payload,"model")??model;continue;}
                    if(String(row,"type")!="event_msg"||String(payload,"type")!="token_count")continue;
                    var usage=Get(Get(payload,"info"),"last_token_usage");if(usage.ValueKind!=JsonValueKind.Object){skipped++;continue;}
                    long full=Count(usage,"input_tokens"),read=Count(usage,"cached_input_tokens"),output=Count(usage,"output_tokens");
                    var date=Date(Get(row,"timestamp"));if(date==null){skipped++;continue;}
                    if(full<read){skipped++;continue;}
                    var e=new TokenRecord(source,date.Value,model,full-read,output,0,read,RecordId(file,date.Value,occurrences));
                    if(e.Tokens>0&&!ModelPricing.IsInternalUsage(model))records[e.Id]=e;
                }else if(source=="claude") {
                    if(String(row,"type")!="assistant")continue;
                    var message=Get(row,"message");var usage=Get(message,"usage");if(usage.ValueKind!=JsonValueKind.Object)continue;
                    string? rawModel=String(message,"model");if(rawModel==null||rawModel=="<synthetic>"||rawModel.StartsWith("synthetic",StringComparison.Ordinal))continue;
                    var date=Date(Get(row,"timestamp"));if(date==null){skipped++;continue;}
                    string? mid=String(message,"id"),rid=String(row,"requestId");
                    string id=!string.IsNullOrEmpty(mid)&&!string.IsNullOrEmpty(rid)?mid+":"+rid:RecordId(file,date.Value,occurrences);
                    var e=new TokenRecord(source,date.Value,rawModel,Count(usage,"input_tokens"),Count(usage,"output_tokens"),Count(usage,"cache_creation_input_tokens"),Count(usage,"cache_read_input_tokens"),id);
                    if(e.Tokens>0&&(!records.TryGetValue(id,out var previous)||e.Dominates(previous)))records[id]=e;
                }else if(source=="grok") {
                    foreach(var e in Grok(row))records[e.Id]=e;
                }
            }catch(Exception e) when(e is JsonException or InvalidDataException or OverflowException or ArgumentOutOfRangeException){skipped++;}
        }
        return new(records.Values.ToArray(),1,0,skipped);
    }
    private static IEnumerable<TokenRecord> Grok(JsonElement row)
    {
        var meta=Get(row,"_meta");if(meta.ValueKind!=JsonValueKind.Object)meta=Get(Get(row,"update"),"_meta");
        if(meta.ValueKind!=JsonValueKind.Object)meta=Get(Get(Get(row,"params"),"update"),"_meta");
        if(Get(meta,"usageIsIncomplete").ValueKind==JsonValueKind.True)yield break;
        string? prompt=String(meta,"promptId");var date=Date(Get(row,"timestamp"))??Date(Get(meta,"timestamp"));
        var models=Get(meta,"modelUsage");if(models.ValueKind!=JsonValueKind.Object)models=Get(Get(meta,"usage"),"modelUsage");
        if(string.IsNullOrEmpty(prompt)||date==null||models.ValueKind!=JsonValueKind.Object)yield break;
        foreach(var pair in models.EnumerateObject()) {
            var usage=pair.Value;if(Get(usage,"costIsPartial").ValueKind==JsonValueKind.True)continue;
            if(Get(usage,"inputTokens").ValueKind!=JsonValueKind.Number||Get(usage,"outputTokens").ValueKind!=JsonValueKind.Number)continue;
            long full=Count(usage,"inputTokens"),output=Count(usage,"outputTokens"),read=Count(usage,"cacheReadTokens"),write=Count(usage,"cacheCreationTokens");
            if(new[]{full,output,read,write}.Any(v=>v>1_000_000_000)||full<read+write||full+output==0)continue;
            yield return new("grok",date.Value,pair.Name,full-read-write,output,write,read,prompt+":"+pair.Name);
        }
    }
    private static string RecordId(string file,DateTimeOffset date,Dictionary<long,int> occurrences)
    {
        long millis=(long)Math.Round((date-DateTimeOffset.UnixEpoch).TotalMilliseconds,MidpointRounding.AwayFromZero);
        int occurrence=occurrences.GetValueOrDefault(millis);occurrences[millis]=occurrence+1;
        return Path.GetFileName(file)+":"+millis.ToString(CultureInfo.InvariantCulture)+":"+occurrence;
    }
    internal static IEnumerable<byte[]> Lines(string file,int limit,Action oversized,CancellationToken cancellation)
    {
        using var stream=new FileStream(file,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete,65_536,FileOptions.SequentialScan);
        using var line=new MemoryStream();byte[] buffer=new byte[65_536];bool dropping=false;int read;
        while((read=stream.Read(buffer))>0) {
            cancellation.ThrowIfCancellationRequested();int start=0;
            for(int i=0;i<read;i++) {
                if(buffer[i]!=10)continue;
                int count=i-start;if(!dropping&&line.Length+count<=limit){line.Write(buffer,start,count);yield return line.ToArray();}
                else if(!dropping)oversized();
                line.SetLength(0);dropping=false;start=i+1;
            }
            int remainder=read-start;
            if(!dropping&&line.Length+remainder<=limit)line.Write(buffer,start,remainder);
            else if(!dropping){line.SetLength(0);dropping=true;oversized();}
        }
        if(!dropping&&line.Length>0)yield return line.ToArray();
    }
    internal static JsonElement Get(JsonElement value,string key)=>value.ValueKind==JsonValueKind.Object&&value.TryGetProperty(key,out var result)?result:default;
    internal static string? String(JsonElement value,string key){var field=Get(value,key);return field.ValueKind==JsonValueKind.String?field.GetString():null;}
    internal static long Count(JsonElement value,string key)
    {
        var field=Get(value,key);if(field.ValueKind is JsonValueKind.Undefined or JsonValueKind.Null)return 0;
        if(field.ValueKind!=JsonValueKind.Number||!field.TryGetInt64(out long n)||n<0||n>long.MaxValue/4)throw new InvalidDataException("Invalid local token count.");return n;
    }
    internal static DateTimeOffset? Date(JsonElement value)
    {
        if(value.ValueKind==JsonValueKind.String&&DateTimeOffset.TryParse(value.GetString(),CultureInfo.InvariantCulture,DateTimeStyles.AssumeUniversal,out var date))return date;
        if(value.ValueKind==JsonValueKind.Number&&value.TryGetDouble(out double n)&&double.IsFinite(n)&&n>0) {
            double ms=n>100_000_000_000?n:n*1000;
            if(ms<=253402300799999)return DateTimeOffset.FromUnixTimeMilliseconds((long)ms);
        }
        return null;
    }
}

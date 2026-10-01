using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading;
using static IslandPrototype.LocalLogScanner;

namespace IslandPrototype;

internal static class DatabaseLogScanner
{
    internal static HistoryScan Scan(string source,string[] roots,DateTimeOffset now,CancellationToken cancellation)
    {
        var records=new Dictionary<string,TokenRecord>();var fingerprints=new HashSet<string>();int files=0,unreadable=0,skipped=0;
        void Emit(TokenRecord? e)
        {
            if(e==null||!e.Valid(now))return;
            if(records.ContainsKey(e.Id))return;
            if(source=="opencode") {
                string fingerprint=$"fingerprint:{e.Timestamp.ToUnixTimeMilliseconds()}:{e.Model}:{e.Input}:{e.Output}:{e.CacheRead}:{e.CacheWrite}";
                if(!fingerprints.Add(e.Provider+":"+fingerprint))return;
                e=e with {Aliases=[fingerprint]};
            }
            records[e.Id]=e;
        }
        foreach(string root in roots) {
            string[] databases;
            try{databases=Directory.GetFiles(root,source=="antigravity"?"*.db":"opencode*.db").Order(StringComparer.Ordinal).ToArray();}
            catch(DirectoryNotFoundException){continue;}
            catch(Exception e) when(e is IOException or UnauthorizedAccessException){unreadable++;continue;}
            foreach(string file in databases) {
                cancellation.ThrowIfCancellationRequested();files++;
                try {
                    using var db=new NativeSqlite(file,true);db.Execute("BEGIN");
                    if(source=="antigravity") {
                        var dates=new Dictionary<long,DateTimeOffset>();
                        using(var steps=db.Prepare("SELECT idx,metadata FROM steps")) {
                            while(steps.Read()) {
                                cancellation.ThrowIfCancellationRequested();
                                try {var stamp=WireFields.Parse(steps.Bytes(1))?.Message(1)?.Timestamp;if(stamp!=null)dates[steps.Long(0)]=stamp.Value;}
                                catch(InvalidDataException){skipped++;}
                            }
                        }
                        using var generations=db.Prepare("SELECT idx,data FROM gen_metadata ORDER BY idx");
                        while(generations.Read()) {
                            cancellation.ThrowIfCancellationRequested();
                            try {
                                var generation=WireFields.Parse(generations.Bytes(1));var record=AntigravityRecord(generation,dates,Path.GetFileNameWithoutExtension(file)+":"+generations.Long(0));
                                if(record==null&&generation?.Message(1)!=null)skipped++;Emit(record);
                            }catch(InvalidDataException){skipped++;}
                        }
                    }else {
                        using var messages=db.Prepare("SELECT id,data FROM message ORDER BY id");
                        while(messages.Read()) {
                            cancellation.ThrowIfCancellationRequested();
                            try{using var doc=JsonDocument.Parse(messages.Text(1));Emit(OpenCode(doc.RootElement,messages.Text(0)));}
                            catch(Exception e) when(e is JsonException or InvalidDataException or OverflowException){skipped++;}
                        }
                    }
                    db.Execute("ROLLBACK");
                }catch(Exception e) when(e is IOException or UnauthorizedAccessException or DllNotFoundException or EntryPointNotFoundException){unreadable++;}
            }
            if(source!="opencode")continue;
            foreach(string file in Files(Path.Combine(root,"storage","message"),p=>p.EndsWith(".json",StringComparison.OrdinalIgnoreCase),()=>unreadable++,cancellation)) {
                files++;cancellation.ThrowIfCancellationRequested();
                try {
                    using var stream=new FileStream(file,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete);
                    if(stream.Length>2_097_152){skipped++;continue;}
                    using var doc=JsonDocument.Parse(stream);Emit(OpenCode(doc.RootElement,Path.GetFileNameWithoutExtension(file)));
                }catch(Exception e) when(e is JsonException or InvalidDataException or OverflowException){skipped++;}
                catch(Exception e) when(e is IOException or UnauthorizedAccessException){unreadable++;}
            }
        }
        return new(records.Values.ToArray(),files,unreadable,skipped);
    }
    private static TokenRecord? OpenCode(JsonElement row,string id)
    {
        if(String(row,"role")!="assistant")return null;
        var tokens=Get(row,"tokens");if(tokens.ValueKind!=JsonValueKind.Object)return null;
        string? provider=String(row,"providerID") switch {"anthropic"=>"claude","openai"=>"codex",_=>null};
        var created=Get(Get(row,"time"),"created");
        if(provider==null||created.ValueKind!=JsonValueKind.Number||!created.TryGetInt64(out long millis)||millis<=0||millis>253402300799999)return null;
        var cache=Get(tokens,"cache");
        return new(provider,DateTimeOffset.FromUnixTimeMilliseconds(millis),String(row,"modelID")??"unknown",Count(tokens,"input"),
            checked(Count(tokens,"output")+Count(tokens,"reasoning")),Count(cache,"write"),Count(cache,"read"),id);
    }
    internal static TokenRecord? AntigravityRecord(WireFields? generation,Dictionary<long,DateTimeOffset> dates,string fallbackId)
    {
        var chat=generation?.Message(1);var usage=chat?.Message(4);var indices=generation?.Integers(2);
        if(chat==null||usage==null||indices==null)return null;
        var date=indices.Where(dates.ContainsKey).Select(i=>(DateTimeOffset?)dates[i]).Min();if(date==null)return null;
        if(new[]{2,3,4,5}.Any(field=>usage.Has(field)&&usage.Integer(field)==null))return null;
        long input=usage.Integer(2)??0,output=usage.Integer(3)??0,write=usage.Integer(4)??0,read=usage.Integer(5)??0;
        if(new[]{input,output,write,read}.Any(n=>n>1_000_000_000)||input+output+write+read==0)return null;
        string? model=chat.String(19)??chat.String(22)??chat.String(21);
        if(string.IsNullOrEmpty(model))model="antigravity-model-"+(chat.Integer(3)??0).ToString(CultureInfo.InvariantCulture);
        string? id=usage.String(12)??usage.String(7)??usage.String(11);
        return new("antigravity",date.Value,model,input,output,write,read,string.IsNullOrEmpty(id)?fallbackId:id);
    }
}

internal sealed class WireFields
{
    private readonly Dictionary<int,List<object>> fields=new();
    internal static WireFields? Parse(byte[] data)
    {
        var result=new WireFields();int position=0;
        while(position<data.Length) {
            ulong? raw=Varint(data,ref position);if(raw==null||raw>>3==0||raw>>3>536_870_911)return null;
            ulong tag=raw.Value;int field=(int)(tag>>3);object value;
            switch(tag&7) {
                case 0:var integer=Varint(data,ref position);if(integer==null)return null;value=integer.Value;break;
                case 2:var length=Varint(data,ref position);if(length==null||length>(ulong)(data.Length-position))return null;
                    value=data.AsSpan(position,(int)length.Value).ToArray();position+=(int)length.Value;break;
                case 1:case 5:int size=(tag&7)==1?8:4;if(data.Length-position<size)return null;position+=size;value=new object();break;
                default:return null;
            }
            if(!result.fields.TryGetValue(field,out var values))result.fields[field]=values=new();values.Add(value);
        }
        return result;
    }
    internal long? Integer(int field)=>fields.GetValueOrDefault(field)?.LastOrDefault() is ulong value&&value<=long.MaxValue?(long)value:null;
    internal bool Has(int field)=>fields.ContainsKey(field);
    private byte[]? Bytes(int field)=>fields.GetValueOrDefault(field)?.LastOrDefault() as byte[];
    internal WireFields? Message(int field)=>Bytes(field) is byte[] bytes?Parse(bytes):null;
    internal string? String(int field)
    {
        if(Bytes(field) is not byte[] bytes)return null;
        try{return new UTF8Encoding(false,true).GetString(bytes);}catch(DecoderFallbackException){return null;}
    }
    internal long[]? Integers(int field)
    {
        var result=new List<long>();
        foreach(object value in fields.GetValueOrDefault(field)??[]) {
            if(value is ulong n&&n<=long.MaxValue)result.Add((long)n);
            else if(value is byte[] bytes) {
                int position=0;while(position<bytes.Length){var item=Varint(bytes,ref position);if(item==null||item>long.MaxValue)return null;result.Add((long)item.Value);}
            }else return null;
        }
        return result.ToArray();
    }
    internal DateTimeOffset? Timestamp {
        get {var seconds=Integer(1);long nanos=Integer(2)??0;return seconds is >0 and <=253402300799&&nanos<1_000_000_000?DateTimeOffset.FromUnixTimeSeconds(seconds.Value).AddTicks(nanos/100):null;}
    }
    private static ulong? Varint(byte[] bytes,ref int position)
    {
        ulong result=0;
        for(int shift=0;shift<=63;shift+=7) {
            if(position>=bytes.Length)return null;byte value=bytes[position++];if(shift==63&&value>1)return null;
            result|=(ulong)(value&127)<<shift;if(value<128)return result;
        }
        return null;
    }
}

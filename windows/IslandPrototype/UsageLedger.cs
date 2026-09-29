using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;

namespace IslandPrototype;

internal sealed partial class UsageLedger
{
    private readonly string path;
    private readonly object gate=new();
    private readonly Dictionary<string,Dictionary<string,TokenRecord>> memory=new();
    private readonly Dictionary<string,long> observations=new();
    private readonly Dictionary<string,Dictionary<string,string>> memoryAliases=new();
    private readonly HashSet<string> dirty=new();
    private readonly Dictionary<string,HistoricalUsageDay[]> historical=new();
    internal UsageLedger(string? path=null)=>this.path=path??DataPaths.File("usage-history.sqlite3");
    internal RetainedHistory Retain(string source,IEnumerable<TokenRecord> incoming,DateTimeOffset observedAt,DateTimeOffset now)
    {
        lock(gate) {
            var events=incoming.Where(e=>e.Valid(now)).ToArray();
            long observed=observedAt.ToUnixTimeMilliseconds();
            if(!memory.TryGetValue(source,out var retained))memory[source]=retained=new();
            if(!memoryAliases.TryGetValue(source,out var aliases))memoryAliases[source]=aliases=new();
            string? error=null;
            try {
                string? directory=Path.GetDirectoryName(path);if(!string.IsNullOrEmpty(directory))Directory.CreateDirectory(directory);
                using var db=new NativeSqlite(path);
                using(var version=db.Prepare("PRAGMA user_version")) {
                    if(!version.Read()||version.Long(0)>1)throw new IOException("The local usage database version is newer than this app.");
                }
                db.Execute("PRAGMA journal_mode=WAL");db.Execute("PRAGMA synchronous=FULL");db.Execute("BEGIN IMMEDIATE");
                try {
                    db.Execute("CREATE TABLE IF NOT EXISTS usage_events(source TEXT NOT NULL,record_id TEXT NOT NULL,provider TEXT NOT NULL,timestamp_ms INTEGER NOT NULL,model TEXT NOT NULL,input_tokens INTEGER NOT NULL,output_tokens INTEGER NOT NULL,cache_creation_tokens INTEGER NOT NULL,cache_read_tokens INTEGER NOT NULL,PRIMARY KEY(source,record_id)) WITHOUT ROWID");
                    db.Execute("CREATE TABLE IF NOT EXISTS event_aliases(source TEXT NOT NULL,alias_id TEXT NOT NULL,record_id TEXT NOT NULL,PRIMARY KEY(source,alias_id)) WITHOUT ROWID");
                    db.Execute("CREATE TABLE IF NOT EXISTS source_scans(source TEXT PRIMARY KEY NOT NULL,observed_at INTEGER NOT NULL) WITHOUT ROWID");
                    CreateHistoricalTable(db);
                    db.Execute("PRAGMA user_version=1");
                    long diskObserved=0;
                    using(var scan=db.Prepare("SELECT observed_at FROM source_scans WHERE source=?")) {scan.Bind(source);if(scan.Read())diskObserved=scan.Long(0);}
                    var diskRecords=new Dictionary<string,TokenRecord>();var diskAliases=new Dictionary<string,string>();
                    using(var query=db.Prepare("SELECT record_id,provider,timestamp_ms,model,input_tokens,output_tokens,cache_creation_tokens,cache_read_tokens FROM usage_events WHERE source=?")) {
                        query.Bind(source);
                        while(query.Read()) {
                            var e=new TokenRecord(query.Text(1),DateTimeOffset.FromUnixTimeMilliseconds(query.Long(2)),query.Text(3),query.Long(4),query.Long(5),query.Long(6),query.Long(7),"ledger:"+query.Text(0));
                            if(e.Valid(now))diskRecords[e.Id[7..]]=e;
                        }
                    }
                    using(var query=db.Prepare("SELECT alias_id,record_id FROM event_aliases WHERE source=?")) {
                        query.Bind(source);while(query.Read())diskAliases.TryAdd(query.Text(0),query.Text(1));
                    }
                    historical[source]=ReadHistorical(db,source);
                    var combined=new Dictionary<string,TokenRecord>(diskRecords);var combinedAliases=new Dictionary<string,string>(diskAliases);
                    if(dirty.Contains(source)) {
                        foreach(var item in retained)if(observations.GetValueOrDefault(source)>=diskObserved||!combined.ContainsKey(item.Key))combined[item.Key]=item.Value;
                        foreach(var item in aliases)combinedAliases.TryAdd(item.Key,item.Value);
                    }
                    memory[source]=retained=combined;memoryAliases[source]=aliases=combinedAliases;
                    observations[source]=Math.Max(observations.GetValueOrDefault(source),diskObserved);
                    bool current=observed>=observations.GetValueOrDefault(source);
                    Merge(retained,aliases,events,current);
                    using var write=db.Prepare("INSERT INTO usage_events VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(source,record_id) DO UPDATE SET provider=excluded.provider,timestamp_ms=excluded.timestamp_ms,model=excluded.model,input_tokens=excluded.input_tokens,output_tokens=excluded.output_tokens,cache_creation_tokens=excluded.cache_creation_tokens,cache_read_tokens=excluded.cache_read_tokens");
                    foreach(var item in retained) {
                        var e=item.Value;if(diskRecords.GetValueOrDefault(item.Key)==e)continue;
                        write.Bind(source,item.Key,e.Provider,e.Timestamp.ToUnixTimeMilliseconds(),e.Model,e.Input,e.Output,e.CacheWrite,e.CacheRead);write.Read();
                    }
                    using var aliasWrite=db.Prepare("INSERT OR IGNORE INTO event_aliases VALUES(?,?,?)");
                    foreach(var alias in aliases){if(diskAliases.ContainsKey(alias.Key))continue;aliasWrite.Bind(source,alias.Key,alias.Value);aliasWrite.Read();}
                    db.Execute("INSERT INTO source_scans VALUES(?,?) ON CONFLICT(source) DO UPDATE SET observed_at=MAX(observed_at,excluded.observed_at)",source,observed);
                    db.Execute("COMMIT");observations[source]=Math.Max(observed,observations.GetValueOrDefault(source));dirty.Remove(source);
                } catch {try{db.Execute("ROLLBACK");}catch(IOException){}throw;}
            } catch(Exception e) when(e is IOException or UnauthorizedAccessException or ArgumentException or DllNotFoundException or EntryPointNotFoundException) {
                error="Usage history could not be saved. Current records are kept in memory.";
                Merge(retained,aliases,events,observed>=observations.GetValueOrDefault(source));
                observations[source]=Math.Max(observed,observations.GetValueOrDefault(source));
                dirty.Add(source);
            }
            return new(retained.Values.OrderBy(e=>e.Timestamp).ToArray(),error,historical.GetValueOrDefault(source)??[]);
        }
    }
    private static void Merge(Dictionary<string,TokenRecord> retained,Dictionary<string,string> aliases,TokenRecord[] events,bool current)
    {
        foreach(var e in events) {
            string key=e.Id.StartsWith("ledger:",StringComparison.Ordinal)?e.Id[7..]:Key(e.Provider,e.Id);
            string[] keys=(e.Aliases??[]).Where(a=>!string.IsNullOrEmpty(a)&&a.Length<=4096).Prepend(e.Id).Select(a=>Key(e.Provider,a)).ToArray();
            string? existing=keys.Select(a=>aliases.GetValueOrDefault(a)).FirstOrDefault(a=>a!=null);if(existing!=null)key=existing;
            if(current||!retained.ContainsKey(key))retained[key]=e with {Timestamp=DateTimeOffset.FromUnixTimeMilliseconds(e.Timestamp.ToUnixTimeMilliseconds()),Id="ledger:"+key,Aliases=null};
            foreach(string alias in keys)aliases.TryAdd(alias,key);
        }
    }
    internal static string Key(string provider,string id)=>Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Encoding.UTF8.GetByteCount(provider)+":"+provider+Encoding.UTF8.GetByteCount(id)+":"+id))).ToLowerInvariant();
}

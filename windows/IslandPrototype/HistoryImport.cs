using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace IslandPrototype;

internal sealed record HistoryImportResult(int AddedRecords,int AddedDays,string? BackupPath,string SourcePlatform);
internal sealed partial class UsageLedger
{
    private sealed record ImportedRecord(string Source,string Key,TokenRecord Value);
    private sealed record ImportedAlias(string Source,string Alias,string Key);
    internal HistoryImportResult Import(string sourcePath,DateTimeOffset now)
    {
        lock(gate) {
            if(string.Equals(Path.GetFullPath(sourcePath),Path.GetFullPath(path),StringComparison.OrdinalIgnoreCase))throw new IOException("Choose a different usage-history backup.");
            var input=new FileInfo(sourcePath);
            if(!input.Exists||input.Length>1024L*1024*1024)throw new IOException("The usage-history backup could not be read.");
            var rows=new List<ImportedRecord>();var aliases=new List<ImportedAlias>();var days=new List<HistoricalUsageDay>();
            string platform;
            using(var source=new NativeSqlite(sourcePath,true)) {
                source.Execute("BEGIN");
                using(var version=source.Prepare("PRAGMA user_version")){if(!version.Read()||version.Long(0)!=1)throw new IOException("This usage-history format is not supported.");}
                var columns=new HashSet<string>();using(var table=source.Prepare("PRAGMA table_info(usage_events)")){while(table.Read())columns.Add(table.Text(1));}
                bool mac=columns.Contains("timestamp")&&!columns.Contains("timestamp_ms");
                if(!mac&&!columns.Contains("timestamp_ms"))throw new IOException("This file is not a CodexIsland usage-history backup.");
                platform=mac?"Mac":"Windows";
                using(var query=source.Prepare("SELECT source,record_id,provider,"+(mac?"timestamp":"timestamp_ms")+",model,input_tokens,output_tokens,cache_creation_tokens,cache_read_tokens FROM usage_events")) {
                    while(query.Read()) {
                        if(rows.Count>=2_000_000)throw new IOException("This usage-history backup is too large.");
                        string sourceId=NormalizeSource(query.Text(0,64)),key=query.Text(1,128),provider=query.Text(2,64);
                        var stamp=mac?Unix(query.Number(3)):Milliseconds(query.Integer(3));
                        var value=new TokenRecord(provider,stamp,query.Text(4,2048),query.Integer(5),query.Integer(6),query.Integer(7),query.Integer(8),"ledger:"+key);
                        if(!Hash(key)||!value.Valid(now)||!SourceOwns(sourceId,provider))throw new IOException("The usage-history backup contains an invalid record.");
                        rows.Add(new(sourceId,key,value));
                    }
                }
                var keys=rows.Select(r=>r.Source+":"+r.Key).ToHashSet();
                using(var query=source.Prepare("SELECT source,alias_id,record_id FROM event_aliases")) {
                    while(query.Read()) {
                        if(aliases.Count>=8_000_000)throw new IOException("This usage-history backup has too many aliases.");
                        string sourceId=NormalizeSource(query.Text(0,64)),alias=query.Text(1,128),key=query.Text(2,128);
                        if(!Hash(alias)||!Hash(key)||!keys.Contains(sourceId+":"+key))throw new IOException("The usage-history backup contains an invalid alias.");
                        aliases.Add(new(sourceId,alias,key));
                    }
                }
                bool historicalTable;using(var query=source.Prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='historical_daily_usage'"))historicalTable=query.Read();
                if(historicalTable) {
                    using var query=source.Prepare("SELECT provider,"+(mac?"interval_start,interval_end":"interval_start_ms,interval_end_ms")+",source_date,utc_offset,tokens,billable_tokens,evidence_id FROM historical_daily_usage ORDER BY provider,1");
                    while(query.Read()) {
                        if(days.Count>=100_000)throw new IOException("This usage-history backup contains too many daily totals.");
                        long offset=query.Integer(4);if(offset is <int.MinValue or >int.MaxValue)throw new IOException("The usage-history backup contains an invalid timezone.");
                        var day=new HistoricalUsageDay(query.Text(0,64),mac?Unix(query.Number(1)):Milliseconds(query.Integer(1)),mac?Unix(query.Number(2)):Milliseconds(query.Integer(2)),query.Text(3,32),(int)offset,query.Integer(5),query.Integer(6),query.Text(7,4096));
                        if(!day.Valid)throw new IOException("The usage-history backup contains an invalid daily total.");days.Add(day);
                    }
                }
                ValidateIntervals(days);
            }
            string? directory=Path.GetDirectoryName(path);if(!string.IsNullOrEmpty(directory))Directory.CreateDirectory(directory);
            string? backup=null;
            if(File.Exists(path)) {
                backup=path+".before-import-"+DateTime.UtcNow.ToString("yyyyMMdd-HHmmss")+"-"+Guid.NewGuid().ToString("N")[..8]+".sqlite3";
                using var existing=new NativeSqlite(path,true);existing.BackupTo(backup);
            }
            using var db=new NativeSqlite(path);
            using(var version=db.Prepare("PRAGMA user_version")){if(!version.Read()||version.Long(0)>1)throw new IOException("The Windows usage database is newer than this app.");}
            db.Execute("PRAGMA journal_mode=WAL");db.Execute("PRAGMA synchronous=FULL");db.Execute("BEGIN IMMEDIATE");
            try {
                CreateTables(db);
                long before=Count(db,"usage_events"),beforeDays=Count(db,"historical_daily_usage");
                var knownAliases=new Dictionary<string,string>();
                using(var query=db.Prepare("SELECT source,alias_id,record_id FROM event_aliases")){while(query.Read())knownAliases[query.Text(0)+":"+query.Text(1)]=query.Text(2);}
                var incomingAliases=aliases.GroupBy(a=>a.Source+":"+a.Key).ToDictionary(g=>g.Key,g=>g.Select(a=>a.Alias).ToArray());
                var canonical=new Dictionary<string,string>();
                using(var write=db.Prepare("INSERT OR IGNORE INTO usage_events VALUES(?,?,?,?,?,?,?,?,?)"))foreach(var row in rows) {
                    string identity=row.Source+":"+row.Key;
                    string key=(incomingAliases.GetValueOrDefault(identity)??[]).Prepend(row.Key).Select(a=>knownAliases.GetValueOrDefault(row.Source+":"+a)).FirstOrDefault(v=>v!=null)??row.Key;
                    canonical[identity]=key;var e=row.Value;
                    write.Bind(row.Source,key,e.Provider,e.Timestamp.ToUnixTimeMilliseconds(),e.Model,e.Input,e.Output,e.CacheWrite,e.CacheRead);write.Read();
                }
                using(var write=db.Prepare("INSERT OR IGNORE INTO event_aliases VALUES(?,?,?)"))foreach(var alias in aliases) {
                    write.Bind(alias.Source,alias.Alias,canonical[alias.Source+":"+alias.Key]);write.Read();
                }
                using(var write=db.Prepare("INSERT OR IGNORE INTO historical_daily_usage VALUES(?,?,?,?,?,?,?,?)"))foreach(var day in days) {
                    write.Bind(day.Provider,day.IntervalStart.ToUnixTimeMilliseconds(),day.IntervalEnd.ToUnixTimeMilliseconds(),day.SourceDate,day.UtcOffsetSeconds,day.Tokens,day.BillableTokens,day.EvidenceId);write.Read();
                }
                foreach(string provider in new[]{"codex","claude","grok","antigravity"})ValidateIntervals(ReadHistorical(db,provider));
                var result=new HistoryImportResult(checked((int)(Count(db,"usage_events")-before)),checked((int)(Count(db,"historical_daily_usage")-beforeDays)),backup,platform);
                db.Execute("COMMIT");return result;
            } catch {try{db.Execute("ROLLBACK");}catch(IOException){}throw;}
        }
    }
    internal bool CopyDatabase(string destination)
    {
        lock(gate) {
            if(string.Equals(Path.GetFullPath(destination),Path.GetFullPath(path),StringComparison.OrdinalIgnoreCase))throw new IOException("Choose a different location for the backup.");
            if(!File.Exists(path))return false;
            string temporary=destination+"."+Guid.NewGuid().ToString("N")+".tmp";
            try{using(var source=new NativeSqlite(path,true))source.BackupTo(temporary);File.Move(temporary,destination,true);return true;}
            finally{try{File.Delete(temporary);}catch(IOException){}catch(UnauthorizedAccessException){}}
        }
    }
    private static DateTimeOffset Unix(double value)
    {
        if(!double.IsFinite(value)||value<=0||value>=253402300800)throw new IOException("The usage-history backup contains an invalid timestamp.");
        try{return DateTimeOffset.UnixEpoch.AddSeconds(value);}catch(ArgumentOutOfRangeException){throw new IOException("The usage-history backup contains an invalid timestamp.");}
    }
    private static DateTimeOffset Milliseconds(long value)
    {
        try{return DateTimeOffset.FromUnixTimeMilliseconds(value);}catch(ArgumentOutOfRangeException){throw new IOException("The usage-history backup contains an invalid timestamp.");}
    }
    private static string NormalizeSource(string source)=>source=="openCode"?"opencode":source;
    private static bool SourceOwns(string source,string provider)=>source==provider&&source is "codex" or "claude" or "grok" or "antigravity"||source=="opencode"&&provider is "codex" or "claude";
    private static bool Hash(string value)=>Regex.IsMatch(value,"^[a-fA-F0-9]{64}$");
    private static long Count(NativeSqlite db,string table){using var query=db.Prepare("SELECT COUNT(*) FROM "+table);return query.Read()?query.Long(0):0;}
    private static void ValidateIntervals(IEnumerable<HistoricalUsageDay> days)
    {
        foreach(var group in days.GroupBy(d=>d.Provider)) {
            DateTimeOffset? previous=null;
            foreach(var day in group.OrderBy(d=>d.IntervalStart)) {
                if(!day.Valid||previous>day.IntervalStart)throw new IOException("Recovered usage intervals overlap.");previous=day.IntervalEnd;
            }
        }
    }
    private static void CreateTables(NativeSqlite db)
    {
        db.Execute("CREATE TABLE IF NOT EXISTS usage_events(source TEXT NOT NULL,record_id TEXT NOT NULL,provider TEXT NOT NULL,timestamp_ms INTEGER NOT NULL,model TEXT NOT NULL,input_tokens INTEGER NOT NULL,output_tokens INTEGER NOT NULL,cache_creation_tokens INTEGER NOT NULL,cache_read_tokens INTEGER NOT NULL,PRIMARY KEY(source,record_id)) WITHOUT ROWID");
        db.Execute("CREATE TABLE IF NOT EXISTS event_aliases(source TEXT NOT NULL,alias_id TEXT NOT NULL,record_id TEXT NOT NULL,PRIMARY KEY(source,alias_id)) WITHOUT ROWID");
        db.Execute("CREATE TABLE IF NOT EXISTS source_scans(source TEXT PRIMARY KEY NOT NULL,observed_at INTEGER NOT NULL) WITHOUT ROWID");
        CreateHistoricalTable(db);db.Execute("PRAGMA user_version=1");
    }
    private static void CreateHistoricalTable(NativeSqlite db)=>db.Execute("CREATE TABLE IF NOT EXISTS historical_daily_usage(provider TEXT NOT NULL,interval_start_ms INTEGER NOT NULL,interval_end_ms INTEGER NOT NULL,source_date TEXT NOT NULL,utc_offset INTEGER NOT NULL,tokens INTEGER NOT NULL,billable_tokens INTEGER NOT NULL,evidence_id TEXT NOT NULL,PRIMARY KEY(provider,interval_start_ms)) WITHOUT ROWID");
    private static HistoricalUsageDay[] ReadHistorical(NativeSqlite db,string source)
    {
        var days=new List<HistoricalUsageDay>();
        using var query=db.Prepare("SELECT interval_start_ms,interval_end_ms,source_date,utc_offset,tokens,billable_tokens,evidence_id FROM historical_daily_usage WHERE provider=? ORDER BY interval_start_ms");query.Bind(source);
        while(query.Read()) {
            long offset=query.Long(3);if(offset is <int.MinValue or >int.MaxValue)throw new IOException("The saved daily usage could not be read.");
            var day=new HistoricalUsageDay(source,DateTimeOffset.FromUnixTimeMilliseconds(query.Long(0)),DateTimeOffset.FromUnixTimeMilliseconds(query.Long(1)),query.Text(2),(int)offset,query.Long(4),query.Long(5),query.Text(6));
            if(!day.Valid)throw new IOException("The saved daily usage could not be read.");days.Add(day);
        }
        ValidateIntervals(days);return days.ToArray();
    }
}

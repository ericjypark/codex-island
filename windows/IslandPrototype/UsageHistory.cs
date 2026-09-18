using System;
using System.Collections.Generic;
using System.Linq;

namespace IslandPrototype;

internal sealed record TokenRecord(string Provider,DateTimeOffset Timestamp,string Model,long Input,long Output,long CacheWrite,long CacheRead,string Id,string[]? Aliases=null)
{
    internal long Tokens=>Input+Output+CacheWrite+CacheRead;
    internal long BillableTokens=>Input+Output;
    internal bool Valid(DateTimeOffset now)=>Provider is "claude" or "codex" or "grok" or "antigravity"
        &&Timestamp>DateTimeOffset.UnixEpoch&&Timestamp<=now&&!string.IsNullOrWhiteSpace(Model)&&Model.Length<=512
        &&!string.IsNullOrEmpty(Id)&&Id.Length<=4096
        &&new[]{Input,Output,CacheWrite,CacheRead}.All(v=>v>=0&&v<=long.MaxValue/4)&&Tokens>0;
    internal bool Dominates(TokenRecord previous)=>Model==previous.Model&&Input>=previous.Input&&Output>=previous.Output&&CacheWrite>=previous.CacheWrite&&CacheRead>=previous.CacheRead;
    internal static long Add(long a,long b)=>a>long.MaxValue-b?long.MaxValue:a+b;
    internal static long Sum(IEnumerable<long> values)=>values.Aggregate(0L,Add);
}

internal sealed record HistoryScan(TokenRecord[] Events,int Files=0,int UnreadableFiles=0,int SkippedRecords=0)
{
    internal string? Notice=>UnreadableFiles>0?"Some local usage files could not be read.":SkippedRecords>0?"Some local usage records could not be read.":null;
}
internal sealed record RetainedHistory(TokenRecord[] Events,string? SaveError=null,HistoricalUsageDay[]? HistoricalDays=null);

internal sealed record ModelCost(string Model,string Name,long Tokens,long AllTokens,double Dollars,double TokenShare,double DollarShare);
internal sealed record HistoryTotal(double Dollars,long Tokens,long BillableTokens,long UnpricedTokens,double[] Series);
internal sealed record HistoryDay(DateTime Date,long Tokens,long BillableTokens,double Dollars,long UnpricedTokens,long RecoveredTokens=0);
internal sealed record ProviderHistory(string Id,bool HasEvidence,HistoryTotal Today,HistoryTotal Month,
    ModelCost[][] Models,HistoryDay[] Days,DateTimeOffset UpdatedAt,string? Notice=null,string? LocalNotice=null);

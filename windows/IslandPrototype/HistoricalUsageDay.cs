using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

namespace IslandPrototype;

internal sealed record HistoricalUsageDay(string Provider,DateTimeOffset IntervalStart,DateTimeOffset IntervalEnd,
    string SourceDate,int UtcOffsetSeconds,long Tokens,long BillableTokens,string EvidenceId)
{
    internal DateTime? DisplayDate=>DateTime.TryParseExact(SourceDate,"yyyy-MM-dd",CultureInfo.InvariantCulture,DateTimeStyles.None,out var date)?date:null;
    internal bool Valid=>Provider is "codex" or "claude" or "grok" or "antigravity"
        &&IntervalStart>DateTimeOffset.UnixEpoch&&(IntervalEnd-IntervalStart).TotalHours is >=23 and <=25
        &&Tokens is >0 and <=long.MaxValue/4&&BillableTokens>=0&&BillableTokens<=Tokens
        &&UtcOffsetSeconds is >=-50400 and <=50400&&UtcOffsetSeconds%60==0
        &&DisplayDate is DateTime day&&day.Year>=1970&&new DateTimeOffset(day,TimeSpan.FromSeconds(UtcOffsetSeconds))==IntervalStart
        &&EvidenceId.Length is >0 and <=4096;
    internal static HistoryDay[] Supplements(IEnumerable<HistoricalUsageDay> source,TokenRecord[] events,DateTimeOffset now)
    {
        var result=new List<HistoryDay>();
        foreach(var group in source.Where(d=>d.Valid).GroupBy(d=>d.Provider)) {
            var days=group.OrderBy(d=>d.IntervalStart).ToArray();var observed=new long[days.Length];var billable=new long[days.Length];
            foreach(var e in events.Where(e=>e.Provider==group.Key&&e.Valid(now))) {
                int left=0,right=days.Length;
                while(left<right){int middle=(left+right)/2;if(days[middle].IntervalStart<=e.Timestamp)left=middle+1;else right=middle;}
                int index=left-1;if(index<0||e.Timestamp>=days[index].IntervalEnd)continue;
                observed[index]=TokenRecord.Add(observed[index],e.Tokens);billable[index]=TokenRecord.Add(billable[index],e.BillableTokens);
            }
            for(int i=0;i<days.Length;i++) {
                long remainder=Math.Max(0,days[i].Tokens-observed[i]);if(remainder==0)continue;
                result.Add(new(days[i].DisplayDate!.Value,remainder,Math.Min(remainder,Math.Max(0,days[i].BillableTokens-billable[i])),0,remainder,remainder));
            }
        }
        return result.ToArray();
    }
}

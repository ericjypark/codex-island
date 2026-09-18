using System;
using System.Collections.Generic;
using System.Linq;

namespace IslandPrototype;

internal static class HistorySummary
{
    private sealed class Total
    {
        internal long Tokens,Billable,Unpriced,Recovered;internal double Dollars;
        internal void Add(TokenRecord e,double? dollars){Tokens=TokenRecord.Add(Tokens,e.Tokens);Billable=TokenRecord.Add(Billable,e.BillableTokens);if(dollars==null)Unpriced=TokenRecord.Add(Unpriced,e.Tokens);else Dollars+=dollars.Value;}
        internal HistoryTotal Build(double[] series)=>new(Dollars,Tokens,Billable,Unpriced,series);
        internal void Add(HistoryDay day){Tokens=TokenRecord.Add(Tokens,day.Tokens);Billable=TokenRecord.Add(Billable,day.BillableTokens);Unpriced=TokenRecord.Add(Unpriced,day.UnpricedTokens);Recovered=TokenRecord.Add(Recovered,day.RecoveredTokens);Dollars+=day.Dollars;}
    }
    internal static ProviderHistory Build(string provider,IEnumerable<TokenRecord> source,ModelPricing pricing,DateTimeOffset now,TimeZoneInfo zone,string? notice=null,IEnumerable<HistoricalUsageDay>? historicalDays=null)
    {
        DateTime local=TimeZoneInfo.ConvertTime(now,zone).DateTime,today=local.Date,month=new(today.Year,today.Month,1);
        var todayTotal=new Total();var monthTotal=new Total();var daily=new Dictionary<DateTime,Total>();
        var recent=new Dictionary<string,Total>();var week=new Dictionary<string,Total>();
        double[] hourly=new double[local.Hour+1],monthly=new double[local.Day];bool evidence=false;
        var events=source.Where(e=>e.Provider==provider&&e.Valid(now)).ToArray();
        foreach(var e in events) {
            if(ModelPricing.IsInternalUsage(e.Model))continue;evidence=true;
            DateTime localDate=TimeZoneInfo.ConvertTime(e.Timestamp,zone).DateTime,date=localDate.Date;
            double? value=pricing.Rates(e.Model,e.Timestamp)?.Cost(e);
            if(!daily.TryGetValue(date,out var day))daily[date]=day=new();day.Add(e,value);
            if(date>=month){monthTotal.Add(e,value);monthly[date.Day-1]+=value??0;}
            if(date==today){todayTotal.Add(e,value);hourly[Math.Min(localDate.Hour,hourly.Length-1)]+=value??0;}
            string canonical=ModelPricing.Canonical(e.Model);
            if(e.Timestamp>=now-TimeSpan.FromDays(7)) {
                if(!week.TryGetValue(canonical,out var total))week[canonical]=total=new();total.Add(e,value);
                if(e.Timestamp>=now-TimeSpan.FromHours(5)){if(!recent.TryGetValue(canonical,out var shortTotal))recent[canonical]=shortTotal=new();shortTotal.Add(e,value);}
            }
        }
        foreach(var recovered in HistoricalUsageDay.Supplements((historicalDays??[]).Where(d=>d.Provider==provider),events,now)) {
            if(recovered.Date>today)continue;evidence=true;
            if(!daily.TryGetValue(recovered.Date,out var day))daily[recovered.Date]=day=new();day.Add(recovered);
            if(recovered.Date>=month)monthTotal.Add(recovered);
            if(recovered.Date==today)todayTotal.Add(recovered);
        }
        ModelCost[] Models(Dictionary<string,Total> totals) {
            long tokens=TokenRecord.Sum(totals.Values.Select(t=>t.Billable));double dollars=totals.Values.Sum(t=>t.Dollars);
            return totals.Select(p=>new ModelCost(p.Key,pricing.Pretty(p.Key),p.Value.Billable,p.Value.Tokens,p.Value.Dollars,tokens==0?0:p.Value.Billable*100.0/tokens,dollars==0?0:p.Value.Dollars*100.0/dollars))
                .OrderByDescending(m=>m.Tokens).ThenByDescending(m=>m.Dollars).ThenBy(m=>m.Model,StringComparer.Ordinal).ToArray();
        }
        static double[] Cumulative(double[] series){for(int i=1;i<series.Length;i++)series[i]+=series[i-1];return series;}
        string? pricingNotice=daily.Values.Any(d=>d.Unpriced>0)?"Some tokens have no known API price.":null;
        return new(provider,evidence,todayTotal.Build(Cumulative(hourly)),monthTotal.Build(Cumulative(monthly)),[Models(recent),Models(week)],
            daily.OrderBy(p=>p.Key).Select(p=>new HistoryDay(p.Key,p.Value.Tokens,p.Value.Billable,p.Value.Dollars,p.Value.Unpriced,p.Value.Recovered)).ToArray(),now,notice??pricingNotice,notice);
    }
}

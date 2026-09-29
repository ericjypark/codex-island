using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

namespace IslandPrototype;

internal enum CardMetric { ApiValue, Tokens }
internal enum CardFormat { Feed, Square, Story }
internal enum CardPeriod { LastSevenDays, LastThirtyDays, LastThreeMonths, ThisYear, AllTime }
internal enum CardTier { White, Black, Blue }
internal sealed record CardProvider(string Id,long Tokens,double Dollars,long UnpricedTokens);

internal sealed class UsageCardSnapshot
{
    public CardPeriod Period {get;}
    public bool IsDemo {get;}
    public DemoDay[] Days {get;}
    public CardProvider[] Providers {get;}
    public long TotalTokens=>Providers.Sum(p=>p.Tokens);
    public double TotalDollars=>Providers.Sum(p=>p.Dollars);
    public long RecoveredTokens=>Days.Sum(d=>d.RecoveredTokens?.Values.Sum()??0);
    public int ActiveDays=>Days.Count(d=>d.Total>0);
    public bool PartialPricing=>Providers.Any(p=>p.UnpricedTokens>0);
    public bool HasPricedUsage=>Providers.Any(p=>p.Tokens>p.UnpricedTokens);
    public DateTime Start=>Days[0].Date;
    public DateTime End=>Days[^1].Date;
    public string DateLabel=>Days.Length==1?End.ToString("MMM d, yyyy",English):Start.ToString(Start.Year==End.Year?"MMM d":"MMM d, yyyy",English)+" - "+End.ToString("MMM d, yyyy",English);
    public string TokenLabel {get {var t=CompactTokens(TotalTokens);return t.Value+t.Unit+(TotalTokens==1?" token":" tokens");}}
    public string ActivityLabel=>$"{ActiveDays} active {(ActiveDays==1?"day":"days")}";
    public string DurationLabel=>$"{Days.Length} {(Days.Length==1?"day":"days")}";
    public string ValueSuffix=>PartialPricing?"+":"";
    public string ValueChallenge=>MilestoneLabel==null?"What does yours look like?":"Can you top this?";
    public static readonly CultureInfo English=CultureInfo.GetCultureInfo("en-US");
    public static readonly string[] PeriodTitles=["Last 7 days","Last 30 days","Last 3 months","This year","All time"];
    public static readonly string[] TokenHeadlines=["My week with AI.","30 days with AI.","Three months with AI.","My year with AI.","My AI journey."];
    public static readonly string[] Qualifiers=["In just 7 days.","In just 30 days.","In just 3 months.","This year so far.","All time."];
    public static readonly string[] CallsToAction=["Your week. Your card.","Your 30 days. Your card.","Your AI. Your card.","Your year. Your card.","Your AI. Your card."];
    private static readonly (double Minimum,string Label,string Headline)[] Milestones=[
        (1e9,"$1B","Billions. One week."),(1e8,"$100M","Nine-figure week."),(1e7,"$10M","Eight-figure week."),
        (1e6,"$1M","Seven-figure week."),(1e5,"$100K","Six-figure week."),(1e4,"$10K","Five-figure week."),
        (1e3,"$1K","Four-figure week."),(1e2,"$100","Three-figure week.")];
    public string? MilestoneLabel=>Milestones.FirstOrDefault(m=>TotalDollars>=m.Minimum).Label;
    public string ValueHeadline {
        get {
            var m=Milestones.FirstOrDefault(m=>TotalDollars>=m.Minimum);
            if(m.Label==null)return TokenHeadlines[(int)Period];
            return Period switch {
                CardPeriod.LastThirtyDays=>m.Minimum>=1e9?"Billions. 30 days.":m.Headline.Replace("-figure week."," figures. 30 days."),
                CardPeriod.LastThreeMonths=>m.Minimum>=1e9?"Billions. 3 months.":m.Headline.Replace("-figure week."," figures. 3 months."),
                CardPeriod.ThisYear=>m.Headline.Replace("week","year"),
                CardPeriod.AllTime=>m.Minimum>=1e9?"Billions. All time.":m.Headline.Replace("week","total"),_=>m.Headline};
        }
    }
    public UsageCardSnapshot(CardPeriod period,HashSet<string> included,DateTime now,IEnumerable<DemoDay>? history=null,bool isDemo=true)
    {
        Period=period;IsDemo=isDemo;DateTime today=now.Date;
        var recorded=(history??(isDemo?ParityData.Days:[])).ToArray();
        DateTime earliest=recorded.Where(d=>d.Date<=today&&d.Tokens.Any(p=>included.Contains(p.Key)&&p.Value>0)).Select(d=>d.Date).DefaultIfEmpty(today).Min();
        DateTime start=period switch {CardPeriod.LastSevenDays=>today.AddDays(-6),CardPeriod.LastThirtyDays=>today.AddDays(-29),CardPeriod.LastThreeMonths=>today.AddDays(1).AddMonths(-3),CardPeriod.ThisYear=>new DateTime(today.Year,1,1),_=>earliest};
        var source=recorded.ToDictionary(d=>d.Date);
        Days=Enumerable.Range(0,(today-start).Days+1).Select(i=> {
            DateTime date=start.AddDays(i);var original=source.GetValueOrDefault(date);
            return new DemoDay(date,original?.Tokens.Where(p=>included.Contains(p.Key)).ToDictionary()??new(),
                original?.BillableTokens.Where(p=>included.Contains(p.Key)).ToDictionary()??new(),
                original?.Dollars.Where(p=>included.Contains(p.Key)&&double.IsFinite(p.Value)&&p.Value>=0).ToDictionary()??new(),
                original?.UnpricedTokens?.Where(p=>included.Contains(p.Key)).ToDictionary(),
                original?.RecoveredTokens?.Where(p=>included.Contains(p.Key)).ToDictionary());
        }).ToArray();
        Providers=ParityData.Providers.Where(p=>included.Contains(p.Id)).Select(p=>new CardProvider(p.Id,Days.Sum(d=>d.Tokens.GetValueOrDefault(p.Id)),Days.Sum(d=>d.Dollars.GetValueOrDefault(p.Id)),Days.Sum(d=>!d.Dollars.ContainsKey(p.Id)?d.Tokens.GetValueOrDefault(p.Id):Math.Clamp(d.UnpricedTokens?.GetValueOrDefault(p.Id)??0,0,d.Tokens.GetValueOrDefault(p.Id))))).Where(p=>p.Tokens>0).OrderByDescending(p=>p.Tokens).ThenBy(p=>p.Id,StringComparer.Ordinal).ToArray();
    }
    public CardProvider[] Ranked(CardMetric metric)=>metric==CardMetric.Tokens?Providers:Providers.OrderByDescending(p=>p.Dollars).ThenBy(p=>p.Id,StringComparer.Ordinal).ToArray();
    public CardTier Tier(CardMetric metric)=>Earned(metric==CardMetric.ApiValue?TotalDollars:TotalTokens,metric);
    public static CardTier Earned(double value,CardMetric metric)=>value>=(metric==CardMetric.ApiValue?1e4:1e9)?CardTier.Blue:value>=(metric==CardMetric.ApiValue?1e3:1e8)?CardTier.Black:CardTier.White;
    public int[] LabelIndices=>Days.Length<=7?Enumerable.Range(0,Days.Length).ToArray():Enumerable.Range(1,5).Select(i=>Math.Max(0,(int)Math.Round(Days.Length*i/5.0,MidpointRounding.AwayFromZero)-1)).ToArray();
    public int[] PointIndices {
        get {if(Days.Length<=31)return Enumerable.Range(0,Days.Length+1).ToArray();int step=Math.Max(1,(int)Math.Ceiling(Days.Length/60.0));return Enumerable.Range(1,(Days.Length-1)/step).Select(i=>i*step).Concat([0,Days.Length]).Concat(LabelIndices.Select(i=>i+1)).Distinct().Order().ToArray();}
    }
    public double[] Cumulative(string id,CardMetric metric)
    {
        var values=new double[Days.Length+1];for(int i=0;i<Days.Length;i++)values[i+1]=values[i]+(metric==CardMetric.ApiValue?Days[i].Dollars.GetValueOrDefault(id):Days[i].Tokens.GetValueOrDefault(id));return values;
    }
    public string ChartLabel(int index)=>Days[index].Date.ToString(Days.Length<=7?"ddd":Days.Length<=366?"MMM d":"MMM yy",English).ToUpperInvariant();
    public string Percent(long tokens) {double p=TotalTokens>0?tokens*100.0/TotalTokens:0;return p>0&&p<1?"<1%":$"{Math.Round(p,MidpointRounding.AwayFromZero):0}%";}
    public string Caption(CardMetric metric)
    {
        string stack=string.Join(" + ",Providers.Select(p=>ParityData.Provider(p.Id).Name));
        string recovery=RecoveredTokens>0?" Includes recovered daily totals on their original dates.":"";
        if(metric==CardMetric.ApiValue)return $"{(IsDemo?"Demo: ":"")}{ValueHeadline} My AI usage: {Money(TotalDollars)}{ValueSuffix} at API rates {(Period==CardPeriod.LastThreeMonths?"over the last 3 months":"in "+DurationLabel)}.\n{TokenLabel} · {ActivityLabel} · {stack}\n{Tier(metric)} card\n{DateLabel}\nAPI-rate estimate (USD), not a bill. Tokens include cache.{recovery}{(PartialPricing?" Some tokens have no known price.":"")}\n\n{ValueChallenge}\nhttps://codexisland.com";
        string periodLabel=IsDemo?(Period==CardPeriod.LastSevenDays?"Demo week":"Demo "+PeriodTitles[(int)Period].ToLowerInvariant()):TokenHeadlines[(int)Period].TrimEnd('.');
        return $"{periodLabel}: {TokenLabel}. {ActivityLabel} out of {Days.Length}.\n{Tier(metric)} card · {stack}\n{DateLabel} · Includes cache tokens.{recovery}\n\n{(Period==CardPeriod.LastSevenDays?"What does your week look like?":"What does your AI usage look like?")}\nMake your card with CodexIsland → https://codexisland.com";
    }
    public static string Money(double amount)
    {
        if(!double.IsFinite(amount)||amount<=0)return "$0.00";
        if(amount>0&&amount<.01)return "<$0.01";
        double rounded=Math.Round(amount,2,MidpointRounding.AwayFromZero);
        if(Milestones.FirstOrDefault(m=>rounded>=m.Minimum).Label!=Milestones.FirstOrDefault(m=>amount>=m.Minimum).Label)rounded=Math.Floor(amount*100)/100;
        return "$"+Math.Max(0,rounded).ToString("N2",English);
    }
    public static (string Value,string Unit) CompactTokens(long count)
    {
        foreach(var unit in new[]{(1e12,"T"),(1e9,"B"),(1e6,"M"),(1e3,"K")}) {
            if(count<unit.Item1*.99995)continue;
            double raw=count/unit.Item1,value=Math.Round(raw,1,MidpointRounding.AwayFromZero);
            if(Earned(value*unit.Item1,CardMetric.Tokens)!=Earned(count,CardMetric.Tokens)){if(raw<1)continue;value=Math.Floor(raw*10)/10;}
            return (value.ToString("#,0.#",English),unit.Item2);
        }
        return (Math.Max(0,count).ToString(English),"");
    }
}

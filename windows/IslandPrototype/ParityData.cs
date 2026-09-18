using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;

namespace IslandPrototype;

public sealed record UsageMetric(string Label, double? Used, string Reset, int Seed,DateTimeOffset? ResetAt=null,bool? IsPrimary=null,double[]? Observations=null);
public sealed record CostMetric(string Label, double Dollars, long Tokens, double[] Series, long BillableTokens = 0,long UnpricedTokens=0);
public sealed record DemoProvider(string Id, string Name, string Plan, Color Color, UsageMetric[] Limits, CostMetric[] Costs)
{
    public double? PlanDollars => Id switch { "claude" => 200, "codex" => 200, "antigravity" => 19.99, "grok" => 30, _ => null };
}
public sealed record DemoDay(DateTime Date, Dictionary<string,long> Tokens, Dictionary<string,long> BillableTokens, Dictionary<string,double> Dollars,Dictionary<string,long>? UnpricedTokens=null,Dictionary<string,long>? RecoveredTokens=null)
{
    public long Total => Tokens.Values.Sum();
}

internal static class ParityData
{
    public static readonly string[] ChartNames = ["RING","BAR","STEPPED","NUMERIC","SPARKLINE"];
    public static readonly string[] CostNames = ["USD","VALUE","TOKENS","TREND"];
    public static readonly string[] PageNames = ["Usage","Cost","Overview"];
    public static readonly Dictionary<string,Color> Colors = new() { ["claude"]=ParityTheme.Claude,["codex"]=ParityTheme.Codex,["antigravity"]=ParityTheme.Antigravity,["grok"]=System.Windows.Media.Colors.White };
    public static readonly DemoProvider[] Providers;
    public static readonly List<DemoDay> Days;
    public static readonly DateTime FixtureDate;

    static ParityData()
    {
        var resource = Application.GetResourceStream(new Uri("/Assets/mac-fixture.json",UriKind.Relative)) ?? throw new InvalidDataException("The reference fixture is missing.");
        using var stream = resource.Stream;
        using var document = JsonDocument.Parse(stream);
        var capturedAt=DateTimeOffset.Parse(document.RootElement.GetProperty("date").GetString()!,CultureInfo.InvariantCulture);
        FixtureDate=capturedAt.LocalDateTime.Date;
        var all = new List<DemoProvider>();
        var map = new Dictionary<DateTime,DemoDay>();
        foreach(var data in document.RootElement.GetProperty("providers").EnumerateArray())
        {
            string id=data.GetProperty("id").GetString()!;
            var limits=data.GetProperty("limits").EnumerateArray().Select(l=>new UsageMetric(l.GetProperty("label").GetString()!,
                l.GetProperty("used").ValueKind==JsonValueKind.Null?null:l.GetProperty("used").GetDouble(),
                Duration(l.GetProperty("resetSeconds").GetDouble()),l.GetProperty("seed").GetInt32(),
                l.TryGetProperty("resetAt",out var reset)&&reset.ValueKind==JsonValueKind.String?DateTimeOffset.Parse(reset.GetString()!,CultureInfo.InvariantCulture)
                    :l.GetProperty("resetSeconds").GetDouble()>0?capturedAt.AddSeconds(l.GetProperty("resetSeconds").GetDouble()):null)).ToArray();
            CostMetric Cost(string key)
            {
                var c=data.GetProperty(key);
                return new CostMetric(c.GetProperty("label").GetString()!,c.GetProperty("dollars").GetDouble(),c.GetProperty("tokens").GetInt64(),
                    c.GetProperty("series").EnumerateArray().Select(v=>v.GetDouble()).ToArray(),c.GetProperty("billableTokens").GetInt64());
            }
            all.Add(new DemoProvider(id,data.GetProperty("name").GetString()!,data.GetProperty("plan").GetString()!,Colors[id],limits,[Cost("today"),Cost("month")]));
            foreach(var day in data.GetProperty("days").EnumerateArray())
            {
                DateTime date=DateTimeOffset.Parse(day.GetProperty("date").GetString()!,CultureInfo.InvariantCulture).LocalDateTime.Date;
                if(!map.TryGetValue(date,out var record))map[date]=record=new DemoDay(date,new(),new(),new());
                record.Tokens[id]=day.GetProperty("tokens").GetInt64();
                record.BillableTokens[id]=day.GetProperty("billableTokens").GetInt64();
                if(day.GetProperty("dollars").ValueKind==JsonValueKind.Number)record.Dollars[id]=day.GetProperty("dollars").GetDouble();
            }
        }
        Providers=all.ToArray();Days=map.OrderBy(p=>p.Key).Select(p=>p.Value).ToList();
    }
    public static DemoProvider Provider(string id) => Providers.First(p=>p.Id==id);
    public static string Duration(double seconds)
    {
        seconds=Math.Max(0,seconds);
        if(seconds<60)return $"{(int)seconds}s";
        if(seconds<3600)return $"{(int)(seconds/60)}m";
        if(seconds<86400)return $"{(int)(seconds/3600)}h";
        int days=(int)(seconds/86400),hours=(int)(seconds%86400/3600);
        return hours==0?$"{days}d":$"{days}d {hours}h";
    }
    public static string TodayResetIn(DateTimeOffset now,TimeZoneInfo zone)
    {
        DateTime next=DateTime.SpecifyKind(TimeZoneInfo.ConvertTime(now,zone).Date.AddDays(1),DateTimeKind.Unspecified);
        while(zone.IsInvalidTime(next))next=next.AddMinutes(1);
        return Duration((TimeZoneInfo.ConvertTimeToUtc(next,zone)-now.UtcDateTime).TotalSeconds);
    }
    public static string MonthResetIn(DateTime date)=>$"{Math.Max(1,DateTime.DaysInMonth(date.Year,date.Month)-date.Day)}d";
    public static (string Value,string Unit) Tokens(long count) => count switch
    {
        <1000 => (count.ToString(CultureInfo.InvariantCulture),"tok"),
        <10000 => ((count/1000.0).ToString("F1",CultureInfo.InvariantCulture),"k"),
        <1000000 => ((count/1000.0).ToString("F0",CultureInfo.InvariantCulture),"k"),
        <1000000000 => ((count/1000000.0).ToString("F1",CultureInfo.InvariantCulture),"M"),
        _ => ((count/1000000000.0).ToString("F1",CultureInfo.InvariantCulture),"B")
    };
}

using System;
using System.Collections.Generic;
using System.Linq;

namespace IslandPrototype;

public enum AlertSeverity {None,Warning,Critical}
public sealed record AlertWindow(string Provider,bool Visible,double? UsedPercent,DateTimeOffset? ResetAt,bool FromHistory=false)
{
    public int? Percent=>UsedPercent is double value&&double.IsFinite(value)
        ?(int)Math.Round(Math.Clamp(value,0,100),MidpointRounding.AwayFromZero):null;
}
public sealed record AlertLine(string Provider,int Percent,DateTimeOffset ResetAt);
public sealed record AlertPulse(Guid Id,AlertSeverity Severity,IReadOnlyList<AlertLine> Lines);

public sealed class AlertEngine
{
    private sealed record Crossing(string Provider,AlertSeverity Threshold,DateTimeOffset ResetAt);
    private readonly HashSet<Crossing> crossings=new();
    private readonly HashSet<string> awaitingFresh=new();
    private bool warmedUp;
    public IReadOnlyDictionary<string,AlertSeverity> ProviderSeverities {get;private set;}=new Dictionary<string,AlertSeverity>();
    public AlertSeverity Severity {get;private set;}
    public int CrossingCount=>crossings.Count;

    public AlertPulse? Update(IEnumerable<AlertWindow> windows,bool enabled,int warning,int critical,bool hasUpdated,bool isDemo)
    {
        var inputs=windows.ToArray();
        var severities=new Dictionary<string,AlertSeverity>();
        bool valid=enabled&&warning is >=50 and <=98&&critical is >=51 and <=99&&warning<critical;
        if(valid)foreach(var input in inputs) {
            if(!input.Visible||input.Percent is not int percent)continue;
            if(percent>=critical)severities[input.Provider]=AlertSeverity.Critical;
            else if(percent>=warning)severities[input.Provider]=AlertSeverity.Warning;
        }
        ProviderSeverities=severities;
        Severity=severities.Values.DefaultIfEmpty(AlertSeverity.None).Max();
        if(!valid){crossings.Clear();awaitingFresh.Clear();warmedUp=false;return null;}
        foreach(var input in inputs)if(input.FromHistory)awaitingFresh.Add(input.Provider);
        if(!hasUpdated)return null;
        foreach(var input in inputs)if(!input.FromHistory&&input.ResetAt is DateTimeOffset reset)
            crossings.RemoveWhere(key=>key.Provider==input.Provider&&key.ResetAt!=reset);
        var lines=new List<AlertLine>();
        AlertSeverity pulseSeverity=AlertSeverity.None;
        foreach(var input in inputs) {
            if(input.FromHistory)continue;
            bool restored=awaitingFresh.Remove(input.Provider);
            if(!input.Visible||input.ResetAt is not DateTimeOffset reset||input.Percent is not int percent)continue;
            bool crossed=false;
            if(percent>=warning)crossed|=crossings.Add(new(input.Provider,AlertSeverity.Warning,reset));
            if(percent>=critical)crossed|=crossings.Add(new(input.Provider,AlertSeverity.Critical,reset));
            if(!crossed||restored)continue;
            var severity=percent>=critical?AlertSeverity.Critical:AlertSeverity.Warning;
            if(severity>pulseSeverity)pulseSeverity=severity;
            lines.Add(new(input.Provider,percent,reset));
        }
        bool wasWarm=warmedUp;warmedUp=true;
        return wasWarm&&!isDemo&&lines.Count>0?new(Guid.NewGuid(),pulseSeverity,lines):null;
    }

    internal void PreparePreview(){crossings.Clear();warmedUp=true;}
}

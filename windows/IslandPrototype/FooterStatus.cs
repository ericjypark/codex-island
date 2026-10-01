using System;
using System.Globalization;
using System.Linq;

namespace IslandPrototype;

internal sealed record FooterStatus(string Label,DateTimeOffset? UpdatedAt=null,bool Loading=false,string? Notice=null,bool Active=false)
{
    internal static FooterStatus Read(UsageFeed? feed,int page,string[] selected)
    {
        if(feed==null||feed.IsDemo)return new("Demo data",Notice:"Illustrative values only. Refresh the demo.");
        var states=selected.Select(feed.State).ToArray();
        var histories=selected.Select(feed.History).ToArray();
        if(page==0?feed.Loading:feed.HistoryLoading)return new("Syncing…",Loading:true);
        string? notice=page==0?null:histories.Select(h=>h?.LocalNotice).FirstOrDefault(n=>n!=null);
        if(notice!=null)return new("Check local records",Notice:notice);
        if(page==0&&states.Any(s=>s is {Id:"grok" or "antigravity",UpdatedAt:null}))return new("Check connection");
        var dates=page==0?states.Select(s=>s?.FromHistory==true?null:s?.UpdatedAt).ToArray():histories.Select(h=>(DateTimeOffset?)h?.UpdatedAt).ToArray();
        if(dates.Length==0||dates.Any(d=>d==null))return new("Idle");
        return new("Synced",dates.Min(),Active:true);
    }

    // Foundation's abbreviated relative formatter floors elapsed units.
    internal static string Relative(DateTimeOffset updated,DateTimeOffset now,bool chinese)
    {
        bool future=updated>=now;var earlier=updated<now?updated:now;var later=updated<now?now:updated;
        double seconds=(later-earlier).TotalSeconds;
        int months=(later.Year-earlier.Year)*12+later.Month-earlier.Month;
        if(earlier.AddMonths(months)>later)months--;
        (long count,string unit,string zh)=months>=12?(months/12,"y","年"):months>=1?(months,"mo","个月")
            :seconds>=604800?((long)(seconds/604800),"w","周"):seconds>=86400?((long)(seconds/86400),"d","天")
            :seconds>=3600?((long)(seconds/3600),"h","小时"):seconds>=60?((long)(seconds/60),"m","分钟"):((long)seconds,"s","秒");
        string number=count.ToString(CultureInfo.InvariantCulture);
        return chinese?number+zh+(future?"后":"前"):future?"in "+number+unit:number+unit+" ago";
    }
}

using System;
using System.Linq;

namespace IslandPrototype;

public sealed record ProviderQuotaSelection(string? GroupId=null,string[]? MetricIds=null,string? PrimaryId=null)
{
    internal bool IsDefault=>GroupId==null&&MetricIds==null&&PrimaryId==null;
    internal static LiveWindow[] Resolve(LiveWindow[] windows,ProviderQuotaSelection selection)
    {
        var groups=windows.Select(w=>w.GroupId).Distinct().OrderBy(id=>id,StringComparer.Ordinal).ToArray();
        string? preferred=groups.FirstOrDefault(id=>windows.Any(w=>w.GroupId==id&&w.GroupLabel?.Contains("gemini",StringComparison.OrdinalIgnoreCase)==true));
        string? group=selection.GroupId??preferred??groups.FirstOrDefault();
        if(group==null||!groups.Contains(group))return [];
        var candidates=windows.Where(w=>w.GroupId==group).OrderBy(w=>w.Kind).ThenBy(w=>w.MetricId,StringComparer.Ordinal).ToArray();
        if(selection.MetricIds==null)return candidates.Take(2).ToArray();
        return selection.MetricIds.Take(2).Distinct().Select(id=>candidates.FirstOrDefault(w=>w.MetricId==id)
            ??new LiveWindow("Unavailable",null,null,id,group,candidates.FirstOrDefault()?.GroupLabel)).ToArray();
    }
    internal ProviderQuotaSelection SelectMetric(LiveWindow[] displayed,int slot,string id)
    {
        if(slot is <0 or >1||slot==0&&string.IsNullOrEmpty(id))return this;
        var ids=displayed.Select(w=>w.MetricId).Take(2).ToList();
        if(id.Length==0){if(slot<ids.Count)ids.RemoveAt(slot);}
        else {
            int other=ids.IndexOf(id);
            if(other>=0&&other!=slot){if(slot<ids.Count)(ids[slot],ids[other])=(ids[other],ids[slot]);}
            else if(slot<ids.Count)ids[slot]=id;else ids.Add(id);
        }
        return this with {MetricIds=ids.ToArray(),PrimaryId=PrimaryId!=null&&ids.Contains(PrimaryId)?PrimaryId:null};
    }
}

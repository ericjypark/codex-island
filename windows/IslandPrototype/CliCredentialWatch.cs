using System;
using System.Collections.Generic;
using System.Linq;

namespace IslandPrototype;

internal sealed class CliCredentialWatch
{
    private readonly Func<string,string> stamp;
    private readonly Dictionary<string,string> previous=new();
    internal CliCredentialWatch(Func<string,string> stamp)
    {
        this.stamp=stamp;
        foreach(string id in new[]{"codex","claude","grok","antigravity"})previous[id]=stamp(id);
    }
    internal string[] ChangedProviders()
    {
        var changed=new List<string>();
        foreach(string id in previous.Keys.ToArray()) {
            string next=stamp(id);
            if(next==previous[id])continue;
            previous[id]=next;changed.Add(id);
        }
        return changed.ToArray();
    }
}

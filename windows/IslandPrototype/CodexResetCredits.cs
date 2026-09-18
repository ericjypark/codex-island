using System;
using System.Globalization;
using System.Linq;
using System.Text.Json;

namespace IslandPrototype;

internal sealed record CodexResetCredit(string Id,string Status,DateTimeOffset? ExpiresAt);
internal sealed record CodexResetCredits(int AvailableCount,CodexResetCredit[]? Credits)
{
    internal CodexResetCredit[] Available(DateTimeOffset now)=>Credits?.Where(c=>c.Status.Equals("available",StringComparison.OrdinalIgnoreCase)&&c.ExpiresAt>now).OrderBy(c=>c.ExpiresAt).ToArray()??[];
    internal bool ShowBadge(DateTimeOffset now)=>AvailableCount>0&&Available(now).Length>0;
    internal static CodexResetCredits? Parse(JsonElement root,bool camelCase=false)
    {
        if(root.ValueKind!=JsonValueKind.Object||!root.TryGetProperty(camelCase?"availableCount":"available_count",out var count)||count.ValueKind!=JsonValueKind.Number||!count.TryGetInt32(out int total)||total<0)return null;
        CodexResetCredit[]? credits=null;
        if(root.TryGetProperty("credits",out var items)&&items.ValueKind==JsonValueKind.Array) {
            credits=items.EnumerateArray().Take(1000).Select(item=>new CodexResetCredit(FileCliCredentials.String(item,"id")??"",FileCliCredentials.String(item,"status")??"",Date(item,camelCase?"expiresAt":"expires_at")))
                .Where(c=>c.Id.Length>0&&c.Id.Length<=1024&&c.Status.Length>0).DistinctBy(c=>c.Id).ToArray();
        }
        return new(total,credits);
    }
    internal static DateTimeOffset? Date(JsonElement root,string key)
    {
        if(root.ValueKind!=JsonValueKind.Object||!root.TryGetProperty(key,out var value))return null;
        if(value.ValueKind==JsonValueKind.String&&DateTimeOffset.TryParse(value.GetString(),CultureInfo.InvariantCulture,DateTimeStyles.AssumeUniversal,out var date))return date;
        if(value.ValueKind==JsonValueKind.Number&&value.TryGetInt64(out long unix))try{return DateTimeOffset.FromUnixTimeSeconds(unix);}catch(ArgumentOutOfRangeException){}
        return null;
    }
}

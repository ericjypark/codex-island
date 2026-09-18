using System;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace IslandPrototype;

internal static class ProviderCredentialParser
{
    internal static CredentialRead Grok(string json,string[] excluded,DateTimeOffset now)
    {
        using var document=JsonDocument.Parse(json);
        if(document.RootElement.ValueKind!=JsonValueKind.Object)return new(null,UsageStatus.CredentialUnavailable);
        CliCredential? expired=null;
        var entries=document.RootElement.EnumerateObject().Where(p=>p.Name.StartsWith("https://auth.x.ai::",StringComparison.Ordinal)||p.Name=="https://accounts.x.ai/sign-in")
            .OrderBy(p=>p.Name.StartsWith("https://auth.x.ai::",StringComparison.Ordinal)?0:1).ThenBy(p=>p.Name,StringComparer.Ordinal);
        foreach(var entry in entries) {
            string? token=FileCliCredentials.String(entry.Value,"key");
            if(!FileCliCredentials.ValidToken(token)||excluded.Contains(token!))continue;
            string? user=FileCliCredentials.String(entry.Value,"user_id");
            if(user!=null&&!FileCliCredentials.ValidToken(user))return new(null,UsageStatus.CredentialUnavailable);
            var credential=new CliCredential(token!,user??FileCliCredentials.String(entry.Value,"email"),userId:user);
            string? expiry=FileCliCredentials.String(entry.Value,"expires_at");
            if(Date(expiry) is DateTimeOffset date&&date<=now){expired??=credential;continue;}
            return new(credential);
        }
        return expired==null?new(null):new(expired,UsageStatus.Expired);
    }
    internal static CredentialRead Antigravity(byte[] bytes,string[] excluded,DateTimeOffset now)
    {
        if(bytes.Length>1024*1024)return new(null,UsageStatus.CredentialUnavailable);
        try {
            string text=new UTF8Encoding(false,true).GetString(bytes).Trim();
            const string prefix="go-keyring-base64:";
            if(text.StartsWith(prefix,StringComparison.Ordinal))text=new UTF8Encoding(false,true).GetString(Convert.FromBase64String(text[prefix.Length..]));
            using var document=JsonDocument.Parse(text);
            var root=document.RootElement;
            if(root.ValueKind!=JsonValueKind.Object||!root.TryGetProperty("token",out var stored)||stored.ValueKind!=JsonValueKind.Object)return new(null,UsageStatus.CredentialUnavailable);
            string? token=FileCliCredentials.String(stored,"access_token");
            if(!FileCliCredentials.ValidToken(token)||excluded.Contains(token!))return new(null);
            if(Date(FileCliCredentials.String(stored,"expiry")) is not DateTimeOffset expiry)return new(null,UsageStatus.CredentialUnavailable);
            return new(new CliCredential(token!,FileCliCredentials.String(root,"email")),expiry<=now?UsageStatus.Expired:UsageStatus.NotConnected);
        } catch(Exception error) when(error is FormatException or JsonException or DecoderFallbackException){return new(null,UsageStatus.CredentialUnavailable);}
    }
    internal static DateTimeOffset? Date(string? value)=>DateTimeOffset.TryParse(value,CultureInfo.InvariantCulture,DateTimeStyles.AssumeUniversal,out var date)?date:null;
}

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace IslandPrototype;

public sealed record IslandPreferences
{
    public int SchemaVersion { get; init; } = 2;
    public int ChartStyle { get; init; } = 4;
    public int CostStyle { get; init; }
    public int Page { get; init; }
    public bool HasNavigated {get;init;}
    public bool HasSeenIntroduction {get;init;}
    public bool HasCycledChart { get; init; }
    public bool HasCycledCost { get; init; }
    public bool Remaining { get; init; }
    public bool AlwaysShowUsage { get; init; }
    public bool LowPower { get; init; }
    public bool ReduceMotion { get; init; }
    public bool LiveMode {get;init;} = true;
    public int RefreshSeconds { get; init; } = 300;
    public string Language { get; init; } = "auto";
    public string LeftProvider { get; init; } = "codex";
    public string? RightProvider { get; init; } = "antigravity";
    public string TargetDisplay { get; init; } = "auto";
    public string Spacing { get; init; } = "reference";
    public bool AlertsEnabled { get; init; }
    public int WarningPercent { get; init; } = 80;
    public int CriticalPercent { get; init; } = 95;
    public bool AutomaticUpdates { get; init; } = true;
    public string TokenMode { get; init; } = "all";
    public string Currency { get; init; } = "USD";
    public string CardMetric {get;init;}="apiValue";
    public string CardFormat {get;init;}="feed";
    public string SettingsTab { get; init; } = "display";
    public Dictionary<string,ProviderQuotaSelection> QuotaSelections {get;init;}=new();

    public string[] SelectedProviders => RightProvider == null ? [LeftProvider] : [LeftProvider, RightProvider];
    public double NotchWidth => Spacing == "compact" ? 100 : Spacing == "notchStyle" ? 200 : 220;

    public IslandPreferences Normalize()
    {
        string[] providers = ["claude", "codex", "antigravity", "grok"];
        string left = providers.Contains(LeftProvider) ? LeftProvider : "claude";
        string? right = providers.Contains(RightProvider) && RightProvider != left ? RightProvider : null;
        int warning = Math.Clamp(WarningPercent, 50, 98);
        int critical = Math.Clamp(CriticalPercent, warning + 1, 99);
        return this with {
            SchemaVersion = Math.Max(2, SchemaVersion),
            LiveMode = SchemaVersion < 2 || LiveMode,
            ChartStyle = Math.Clamp(ChartStyle, 0, 4), CostStyle = Math.Clamp(CostStyle, 0, 3), Page = Math.Clamp(Page, 0, 2),
            RefreshSeconds = new[] {300,900,1800}.Contains(RefreshSeconds) ? RefreshSeconds : 300,
            Language = new[] {"auto","en","zh-Hans"}.Contains(Language) ? Language : "auto",
            LeftProvider = left, RightProvider = right, WarningPercent = warning, CriticalPercent = critical,
            TargetDisplay = string.IsNullOrWhiteSpace(TargetDisplay) ? "auto" : TargetDisplay,
            Spacing = new[] {"reference","compact","notchStyle"}.Contains(Spacing) ? Spacing : "compact",
            TokenMode = TokenMode == "billable" ? "billable" : "all",
            Currency = new[] {"USD","CNY","EUR","GBP","JPY","KRW","CAD","AUD","CHF"}.Contains(Currency) ? Currency : "USD",
            CardMetric=CardMetric=="tokens"?"tokens":"apiValue",
            CardFormat=new[]{"feed","square","story"}.Contains(CardFormat)?CardFormat:"feed",
            QuotaSelections=QuotaSelections??new(),
            SettingsTab = new[] {"general","display","providers"}.Contains(SettingsTab) ? SettingsTab : "general"
        };
    }

    public IslandPreferences SelectProvider(string? id, int slot)
    {
        if (slot < 0 || slot > 1) return this;
        if (id == null) return slot == 1 ? this with { RightProvider = null } : this;
        if (!new[] {"claude","codex","antigravity","grok"}.Contains(id)) return this;
        if (id == LeftProvider || id == RightProvider)
            return RightProvider != null && ((slot == 0 && id == RightProvider) || (slot == 1 && id == LeftProvider)) ? SwapProviders() : this;
        return slot == 0 ? this with { LeftProvider = id } : this with { RightProvider = id };
    }

    public IslandPreferences SwapProviders() => RightProvider == null ? this : this with { LeftProvider = RightProvider, RightProvider = LeftProvider };
}

public sealed class PreferenceStore
{
    internal static string DefaultPath=>DataPaths.File("preferences.json");
    private readonly string path;
    public IslandPreferences Value { get; private set; }
    public string? Error { get; private set; }
    public event Action<IslandPreferences, IslandPreferences>? Changed;
    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true, IgnoreReadOnlyProperties = true };

    public PreferenceStore(string path)
    {
        this.path = path;
        Value = new IslandPreferences();
        if (!File.Exists(path)) return;
        try {
            Value = (JsonSerializer.Deserialize<IslandPreferences>(File.ReadAllText(path)) ?? throw new JsonException("Empty preferences")).Normalize();
        }
        catch (Exception error) when (error is IOException or JsonException or UnauthorizedAccessException) {
            Error = "Saved settings could not be read. The original file has been preserved.";
        }
    }

    public bool Update(IslandPreferences candidate)
    {
        var next = candidate.Normalize();
        if (next == Value) return true;
        string temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            if (Error != null && File.Exists(path)) File.Copy(path, path + ".recovery-" + DateTime.UtcNow.ToString("yyyyMMddHHmmssfff"), false);
            File.WriteAllText(temporary, JsonSerializer.Serialize(next, Options));
            File.Move(temporary, path, true);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) {
            Error = "Settings could not be saved. Check that your app-data folder is writable.";
            try { File.Delete(temporary); } catch (IOException) { } catch (UnauthorizedAccessException) { }
            return false;
        }
        var previous = Value; Value = next; Error = null;
        Changed?.Invoke(previous, next);
        return true;
    }
}

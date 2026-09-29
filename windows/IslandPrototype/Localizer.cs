using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text.Json;
using System.Windows;

namespace IslandPrototype;

internal static class Localizer
{
    private static readonly Dictionary<string,string> Chinese = Load();
    public static string Language { get; set; } = "auto";
    public static bool IsChinese => Language == "zh-Hans" || Language == "auto" && CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "zh";
    public static CultureInfo Culture => IsChinese ? CultureInfo.GetCultureInfo("zh-Hans") : Language == "en" ? CultureInfo.GetCultureInfo("en-US") : CultureInfo.CurrentCulture;
    public static string Text(string text) => IsChinese ? Chinese.GetValueOrDefault(text, text) : text;
    private static Dictionary<string,string> Load()
    {
        var resource = Application.GetResourceStream(new Uri("/Assets/zh-Hans.json",UriKind.Relative));
        if (resource == null) return new();
        using var stream = resource.Stream;
        return JsonSerializer.Deserialize<Dictionary<string,string>>(stream) ?? new();
    }
}

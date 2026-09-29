using System;
using System.IO;

namespace IslandPrototype;

internal static class DataPaths
{
    internal static string DefaultRoot {get;}=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"CodexIslandPrototype");
    internal static string Root {get;private set;}=DefaultRoot;
    internal static bool IsCustom {get;private set;}
    internal static string File(string name)=>Path.Combine(Root,name);
    internal static void Configure(string[] arguments)
    {
        int index=Array.IndexOf(arguments,"--data-dir");if(index<0)return;
        if(index+1>=arguments.Length||!Path.IsPathFullyQualified(arguments[index+1]))throw new ArgumentException("Choose an absolute folder path for the separate data profile.");
        Root=Path.GetFullPath(arguments[index+1]);IsCustom=true;
    }
}

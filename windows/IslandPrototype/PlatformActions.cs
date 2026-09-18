using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Microsoft.Win32;

namespace IslandPrototype;

internal static class StartupRegistration
{
    private const string Key = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private static string Name=>DataPaths.IsCustom?"CodexIslandProfile-"+Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(Encoding.UTF8.GetBytes(DataPaths.Root.TrimEnd('\\','/').ToUpperInvariant())))[..16]:"CodexIslandPrototype";
    public static bool IsEnabled {
        get { using var key = Registry.CurrentUser.OpenSubKey(Key); return key?.GetValue(Name) is string; }
    }
    public static void Set(bool enabled,bool? liveMode=null)
    {
        using var key = Registry.CurrentUser.CreateSubKey(Key);
        if (enabled) {
            string executable=Environment.ProcessPath??throw new IOException("The application path is unavailable.");
            if(App.IsInstalled&&Velopack.Locators.VelopackLocator.Current.RootAppDir is string root) {
                string launcher=Path.Combine(root,Path.GetFileName(executable));
                if(File.Exists(launcher))executable=launcher;
            }
            string arguments=string.Join(" ",Array.ConvertAll(App.RestartArguments(liveMode),Quote));
            key.SetValue(Name,Quote(executable)+" "+arguments);
        }
        else key.DeleteValue(Name, false);
    }
    private static string Quote(string value)
    {
        var result=new StringBuilder("\"");int slashes=0;
        foreach(char character in value) {
            if(character=='\\'){slashes++;continue;}
            result.Append('\\',character=='"'?slashes*2+1:slashes).Append(character);slashes=0;
        }
        return result.Append('\\',slashes*2).Append('"').ToString();
    }
    internal static void RemoveForInstallation(string root)
    {
        using var key=Registry.CurrentUser.OpenSubKey(Key,true);if(key==null)return;
        string prefix="\""+root.TrimEnd('\\')+"\\";
        foreach(string name in key.GetValueNames()) {
            if(name!="CodexIslandPrototype"&&!name.StartsWith("CodexIslandProfile-",StringComparison.Ordinal))continue;
            if(key.GetValue(name) is string command&&command.StartsWith(prefix,StringComparison.OrdinalIgnoreCase))key.DeleteValue(name,false);
        }
    }
}

internal static class IslandDialog
{
    public static bool Show(Window owner, string title, string message, string primary, string? secondary = null)
    {
        bool accepted = false;
        var dialog = new Window {
            Owner=owner,Title=Localizer.Text(title),Width=390,SizeToContent=SizeToContent.Height,
            WindowStartupLocation=WindowStartupLocation.CenterOwner,WindowStyle=WindowStyle.None,
            ResizeMode=ResizeMode.NoResize,Background=Brushes.Black,Foreground=Brushes.White,
            ShowInTaskbar=false
        };
        var body = new StackPanel {Margin=new Thickness(24)};
        body.Children.Add(SettingsControls.Label(title,15,.95,true));
        var detail = SettingsControls.Label(message,12,.6); detail.Margin=new Thickness(0,10,0,22); body.Children.Add(detail);
        var actions = new StackPanel {Orientation=Orientation.Horizontal,HorizontalAlignment=HorizontalAlignment.Right};
        if (secondary != null) {
            var cancel=SettingsControls.Button(secondary,()=>dialog.Close());cancel.Margin=new Thickness(0,0,8,0);cancel.IsCancel=true;actions.Children.Add(cancel);
        }
        var okay=SettingsControls.Button(primary,()=>{accepted=true;dialog.Close();});okay.IsDefault=true;actions.Children.Add(okay);
        body.Children.Add(actions);
        dialog.Content=new Border {Child=body,BorderBrush=ParityTheme.White(.18),BorderThickness=new Thickness(1),CornerRadius=new CornerRadius(10)};
        dialog.ShowDialog();return accepted;
    }
}

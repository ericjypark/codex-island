using System;
using System.IO;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Windows;
using Velopack;
using Velopack.Locators;

namespace IslandPrototype;

public partial class App : Application
{
    [STAThread]
    private static void Main(string[] args)
    {
        VelopackApp.Build().SetArgs(args).SetAutoApplyOnStartup(false)
            .OnBeforeUninstallFastCallback(_=>{
                if(VelopackLocator.Current.RootAppDir is string root)StartupRegistration.RemoveForInstallation(root);
            }).Run();
        var app=new App();app.InitializeComponent();app.Run();
    }

    private Mutex? instance;
    internal bool RestartRequested {get;set;}
    internal bool? RestartLiveMode {get;set;}
    internal bool RestartProviders {get;set;}
    internal static bool PreviewAlerts {get;private set;}
    internal static bool Live {get;private set;}
    internal static bool IsInstalled=>VelopackLocator.Current.CurrentlyInstalledVersion!=null&&!VelopackLocator.Current.IsPortable;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        try{DataPaths.Configure(e.Args);}catch(ArgumentException error){MessageBox.Show(error.Message,"CodexIsland");Shutdown();return;}
        string profile=Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(DataPaths.Root.TrimEnd('\\','/').ToUpperInvariant())));
        string instanceName=string.Equals(DataPaths.Root.TrimEnd('\\','/'),DataPaths.DefaultRoot,StringComparison.OrdinalIgnoreCase)?"Local\\CodexIslandWindowsPrototype":"Local\\CodexIsland-"+profile;
        instance = new Mutex(true, instanceName, out bool first);
        if (!first) { Shutdown(); return; }
        if(Array.IndexOf(e.Args,"--trace-frames")>=0)FrameDiagnostics.Start();
        Live=Array.IndexOf(e.Args,"--demo")<0&&Array.IndexOf(e.Args,"--preview-alerts")<0
            &&(Array.IndexOf(e.Args,"--live")>=0||new PreferenceStore(PreferenceStore.DefaultPath).Value.LiveMode);
        PreviewAlerts=!Live&&Array.IndexOf(e.Args,"--preview-alerts")>=0;
        MainWindow = new MainWindow();
        MainWindow.Show();
        if(Array.IndexOf(e.Args,"--providers")>=0)Dispatcher.BeginInvoke(new Action(()=>((MainWindow)MainWindow).OpenProviderSettings()));
        else if(Array.IndexOf(e.Args,"--settings")>=0)Dispatcher.BeginInvoke(new Action(()=>((MainWindow)MainWindow).OpenGeneralSettings()));
        else if(Live) ((MainWindow)MainWindow).OfferIntroduction();
    }

    internal static string[] RestartArguments(bool? live=null,bool providers=false,bool settings=false)
    {
        var arguments=new List<string>{(live??Live)?"--live":"--demo"};
        if(providers)arguments.Add("--providers");else if(settings)arguments.Add("--settings");
        if(DataPaths.IsCustom){arguments.Add("--data-dir");arguments.Add(DataPaths.Root);}
        return arguments.ToArray();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        FrameDiagnostics.Save();
        instance?.Dispose();
        if(RestartRequested && Environment.ProcessPath is string executable) {
            var start=new System.Diagnostics.ProcessStartInfo(executable){UseShellExecute=true};
            foreach(string argument in RestartArguments(RestartLiveMode,RestartProviders))start.ArgumentList.Add(argument);
            System.Diagnostics.Process.Start(start);
        }
        base.OnExit(e);
    }
}

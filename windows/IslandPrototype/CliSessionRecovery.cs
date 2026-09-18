using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace IslandPrototype;

internal static class CliSessionRecovery
{
    internal static async Task<bool> RenewAsync(string provider,CancellationToken cancellation)
    {
        if(provider is not ("grok" or "antigravity"))return false;
        string? executable=CliAccountActions.FindExecutable(provider);
        if(executable==null)return false;
        string script="$ErrorActionPreference='Stop'; $env:PATH='"+CliAccountActions.CurrentPath.Replace("'","''")
            +"'; try { & '"+executable.Replace("'","''")+"' models; exit $LASTEXITCODE } catch { exit 1 }";
        var start=new ProcessStartInfo(CliAccountActions.PowerShell) {UseShellExecute=false,CreateNoWindow=true,
            RedirectStandardInput=true,RedirectStandardOutput=true,RedirectStandardError=true,WorkingDirectory=Path.GetTempPath()};
        start.ArgumentList.Add("-NoProfile");start.ArgumentList.Add("-NonInteractive");start.ArgumentList.Add("-EncodedCommand");
        start.ArgumentList.Add(Convert.ToBase64String(Encoding.Unicode.GetBytes(script)));
        using var timeout=CancellationTokenSource.CreateLinkedTokenSource(cancellation);timeout.CancelAfter(TimeSpan.FromSeconds(25));
        try {
            using var process=Process.Start(start);
            if(process==null)return false;
            process.StandardInput.Close();
            Task output=DrainAsync(process.StandardOutput),errors=DrainAsync(process.StandardError);
            try {
                await process.WaitForExitAsync(timeout.Token);
                await Task.WhenAll(output,errors).WaitAsync(timeout.Token);
                return process.ExitCode==0;
            } finally {if(!process.HasExited)process.Kill(true);}
        } catch(OperationCanceledException) when(!cancellation.IsCancellationRequested){return false;}
        catch(Exception error) when(error is Win32Exception or IOException or InvalidOperationException){return false;}
    }
    private static async Task DrainAsync(StreamReader reader)
    {
        char[] buffer=new char[4096];while(await reader.ReadAsync(buffer)>0){}
    }
}

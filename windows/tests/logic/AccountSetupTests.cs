using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;
using IslandPrototype;

internal static class AccountSetupTests
{
    internal static void Run(Action<string,bool> check)
    {
        string native=@"C:\Users\Example\AppData\Local\Programs\OpenAI\Codex\bin";
        string npm=@"C:\Users\Example\AppData\Roaming\npm";
        var files=new HashSet<string>(StringComparer.OrdinalIgnoreCase) {Path.Combine(native,"codex.exe"),Path.Combine(npm,"claude.cmd")};
        check("A missing Codex install offers installation instead of opening documentation",CliAccountActions.ActionLabel("codex",false,UsageStatus.NotConnected)=="Install Codex");
        check("An installed Codex CLI offers ChatGPT sign-in",CliAccountActions.ActionLabel("codex",true,UsageStatus.NotConnected)=="Sign in with ChatGPT");
        check("A missing Claude CLI offers its own installer",CliAccountActions.ActionLabel("claude",false,UsageStatus.NotConnected)=="Install Claude Code");
        check("Connected and expired accounts offer the appropriate sign-in action",CliAccountActions.ActionLabel("codex",true,UsageStatus.Ready)=="Switch account"&&CliAccountActions.ActionLabel("claude",true,UsageStatus.Expired)=="Sign in again");
        check("Standalone installs remain discoverable after a stale process PATH",CliAccountActions.FindExecutable("codex",[@"C:\old-path",native],files.Contains)==Path.Combine(native,"codex.exe"));
        check("Quoted npm PATH entries are resolved",CliAccountActions.FindExecutable("claude",["\""+npm+"\""],files.Contains)==Path.Combine(npm,"claude.cmd"));
        check("Relative PATH entries cannot launch a CLI from the current project",CliAccountActions.FindExecutable("codex",[".","relative"],_=>true)==null);
        check("Unsupported providers cannot borrow a different CLI",CliAccountActions.FindExecutable("unknown",[native],_=>true)==null);
        check("Antigravity discovers its agy command",CliAccountActions.FindExecutable("antigravity",[native],path=>path.EndsWith("agy.exe"))==Path.Combine(native,"agy.exe"));
        check("Grok offers install and sign-in actions",CliAccountActions.ActionLabel("grok",false,UsageStatus.NotConnected)=="Install Grok"&&CliAccountActions.ActionLabel("grok",true,UsageStatus.NotConnected)=="Sign in with Grok");
        string script=CliAccountActions.LoginScript("codex",@"C:\Users\O'Brien\$(bad)\codex.exe",@"C:\$env:TEST\bin");
        check("Login paths are literal PowerShell strings even with quotes and interpolation syntax",script.Contains("& 'C:\\Users\\O''Brien\\$(bad)\\codex.exe' login;")&&script.Contains("$env:PATH='C:\\$env:TEST\\bin'"));
        check("Claude sign-in uses the CLI's own auth command",CliAccountActions.LoginScript("claude",@"C:\claude.exe","").Contains("' auth login;"));
        check("Installers use fixed official HTTPS sources",CliAccountActions.InstallerUrl("codex")=="https://chatgpt.com/codex/install.ps1"&&CliAccountActions.InstallerUrl("claude")=="https://claude.ai/install.ps1");
        check("Grok compatibility is limited to the observed ARM64 release",GrokCompatibility.IsAffected(Architecture.Arm64,0xAA64,"1.0.30")&&!GrokCompatibility.IsAffected(Architecture.X64,0xAA64,"1.0.30")&&!GrokCompatibility.IsAffected(Architecture.Arm64,0x8664,"1.0.30")&&!GrokCompatibility.IsAffected(Architecture.Arm64,0xAA64,"1.0.31"));
        check("Grok version parsing rejects preview releases and unrelated output",GrokCompatibility.ParseVersion("1.0.30 (04b7ffed98c6)")=="1.0.30"&&GrokCompatibility.ParseVersion("grok 1.0.30")=="1.0.30"&&GrokCompatibility.ParseVersion("1.0.30-beta")==null&&GrokCompatibility.ParseVersion("warning 1.0.30")==null);
        string root=Path.Combine(Path.GetTempPath(),"CodexIsland-Grok-"+Guid.NewGuid().ToString("N"));
        try {
            Directory.CreateDirectory(Path.Combine(root,"1.0.30"));
            string original=Path.Combine(root,"native.exe"),compatible=Path.Combine(root,"1.0.30","grok.exe");
            File.WriteAllBytes(original,new byte[128]);File.WriteAllBytes(compatible,new byte[128]);
            check("An unregistered compatibility copy never overrides the CLI",GrokCompatibility.Resolve(original,root)==original);
            var nativeInfo=new FileInfo(original);var compatibleInfo=new FileInfo(compatible);
            File.WriteAllText(Path.Combine(root,"registration.json"),JsonSerializer.Serialize(new {NativePath=nativeInfo.FullName,NativeLength=nativeInfo.Length,NativeWritten=nativeInfo.LastWriteTimeUtc.Ticks,CompatibleLength=compatibleInfo.Length,CompatibleWritten=compatibleInfo.LastWriteTimeUtc.Ticks}));
            check("A verified compatibility registration selects its own executable",GrokCompatibility.Resolve(original,root)==compatible);
            File.SetLastWriteTimeUtc(original,nativeInfo.LastWriteTimeUtc.AddSeconds(2));
            check("Updating the native CLI invalidates the old compatibility registration",GrokCompatibility.Resolve(original,root)==original);
            File.SetLastWriteTimeUtc(original,nativeInfo.LastWriteTimeUtc);File.AppendAllText(compatible,"changed");
            check("Changing the compatibility executable invalidates its registration",GrokCompatibility.Resolve(original,root)==original);
            check("An invalid executable header is rejected",GrokCompatibility.Machine(original)==0);
        } finally {Directory.Delete(root,true);}
    }
}

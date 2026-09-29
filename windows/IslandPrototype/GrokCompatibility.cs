using System;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

namespace IslandPrototype;

internal static class GrokCompatibility
{
    private const string AffectedVersion="1.0.30";
    private static readonly SemaphoreSlim gate=new(1,1);
    private static string Root=>Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"CodexIslandPrototype","grok-compat");
    private sealed record Registration(string NativePath,long NativeLength,long NativeWritten,long CompatibleLength,long CompatibleWritten);
    private static string CompatiblePath(string root)=>Path.Combine(root,AffectedVersion,"grok.exe");
    internal static string Resolve(string native)=>RuntimeInformation.OSArchitecture==Architecture.Arm64?Resolve(native,Root):native;
    internal static string Resolve(string native,string root)
    {
        try {
            string manifest=Path.Combine(root,"registration.json");
            if(!File.Exists(manifest)||new FileInfo(manifest).Length>4096)return native;
            var saved=JsonSerializer.Deserialize<Registration>(File.ReadAllText(manifest));
            var original=new FileInfo(native);var compatible=new FileInfo(CompatiblePath(root));
            return saved!=null&&original.Exists&&compatible.Exists
                &&string.Equals(original.FullName,saved.NativePath,StringComparison.OrdinalIgnoreCase)
                &&original.Length==saved.NativeLength&&original.LastWriteTimeUtc.Ticks==saved.NativeWritten
                &&compatible.Length==saved.CompatibleLength&&compatible.LastWriteTimeUtc.Ticks==saved.CompatibleWritten
                ?compatible.FullName:native;
        } catch(Exception error) when(error is IOException or UnauthorizedAccessException or JsonException or ArgumentException){return native;}
    }
    internal static bool IsAffected(Architecture architecture,ushort machine,string? version)=>architecture==Architecture.Arm64&&machine==0xAA64&&version==AffectedVersion;
    internal static async Task<string> PrepareAsync(string native)
    {
        if(RuntimeInformation.OSArchitecture!=Architecture.Arm64||!native.EndsWith(".exe",StringComparison.OrdinalIgnoreCase))return native;
        await gate.WaitAsync();
        try {
            string resolved=Resolve(native);if(resolved!=native)return resolved;
            if(!IsAffected(RuntimeInformation.OSArchitecture,Machine(native),await VersionAsync(native)))return native;
            // The official 1.0.30 ARM64 binary overflows its main-thread stack during login.
            // Keep that installation intact and use the same official release under x64 emulation.
            string destination=CompatiblePath(Root);Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            string staging=destination+"."+Guid.NewGuid().ToString("N")+".exe";
            try {
                string probe=Path.Combine(Path.GetDirectoryName(Root)!,"grok-compat-probe","grok.exe");
                if(File.Exists(probe)&&Machine(probe)==0x8664&&await VersionAsync(probe)==AffectedVersion)File.Copy(probe,staging);
                else {
                    using var timeout=new CancellationTokenSource(TimeSpan.FromMinutes(3));
                    using var http=new HttpClient {Timeout=Timeout.InfiniteTimeSpan};
                    using var response=await http.GetAsync("https://x.ai/cli/grok-1.0.30-windows-x86_64.exe",HttpCompletionOption.ResponseHeadersRead,timeout.Token);
                    response.EnsureSuccessStatusCode();
                    const long maximum=300L*1024*1024;
                    if(response.Content.Headers.ContentLength>maximum)throw new IOException("Unexpected Grok download size.");
                    await using var input=await response.Content.ReadAsStreamAsync(timeout.Token);
                    await using var output=new FileStream(staging,FileMode.CreateNew,FileAccess.Write,FileShare.None);
                    byte[] buffer=new byte[65536];long total=0;int count;
                    while((count=await input.ReadAsync(buffer,timeout.Token))>0) {
                        total+=count;if(total>maximum)throw new IOException("Unexpected Grok download size.");
                        await output.WriteAsync(buffer.AsMemory(0,count),timeout.Token);
                    }
                }
                if(Machine(staging)!=0x8664||await VersionAsync(staging)!=AffectedVersion)throw new IOException("The Grok compatibility download could not be verified.");
                File.Move(staging,destination,true);
                var original=new FileInfo(native);var compatible=new FileInfo(destination);
                var saved=new Registration(original.FullName,original.Length,original.LastWriteTimeUtc.Ticks,compatible.Length,compatible.LastWriteTimeUtc.Ticks);
                string manifest=Path.Combine(Root,"registration.json");
                await File.WriteAllTextAsync(manifest+".tmp",JsonSerializer.Serialize(saved));File.Move(manifest+".tmp",manifest,true);
                return destination;
            } finally {if(File.Exists(staging))File.Delete(staging);}
        } finally {gate.Release();}
    }
    internal static ushort Machine(string path)
    {
        using var file=File.OpenRead(path);using var reader=new BinaryReader(file);
        if(file.Length<64||reader.ReadUInt16()!=0x5A4D)return 0;
        file.Position=60;int offset=reader.ReadInt32();
        if(offset<64||offset>file.Length-24)return 0;
        file.Position=offset;return reader.ReadUInt32()==0x4550?reader.ReadUInt16():(ushort)0;
    }
    internal static string? ParseVersion(string text)
    {
        var match=Regex.Match(text.Trim(),@"^(?:grok(?:-cli)?\s+)?(\d+\.\d+\.\d+)(?:\s|$)",RegexOptions.IgnoreCase);
        return match.Success?match.Groups[1].Value:null;
    }
    private static async Task<string?> VersionAsync(string executable)
    {
        var start=new ProcessStartInfo(executable) {UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true};
        start.ArgumentList.Add("--version");
        using var process=Process.Start(start)??throw new IOException("Grok could not start.");
        using var timeout=new CancellationTokenSource(TimeSpan.FromSeconds(10));
        Task<string> output=ReadBoundedAsync(process.StandardOutput,timeout.Token),error=ReadBoundedAsync(process.StandardError,timeout.Token);
        try {
            await process.WaitForExitAsync(timeout.Token);await Task.WhenAll(output,error).WaitAsync(timeout.Token);
            return process.ExitCode==0?ParseVersion(await output):null;
        } finally {if(!process.HasExited)process.Kill(true);}
    }
    private static async Task<string> ReadBoundedAsync(StreamReader reader,CancellationToken cancellation)
    {
        char[] buffer=new char[32769];int total=0,count;
        while(total<buffer.Length&&(count=await reader.ReadAsync(buffer.AsMemory(total),cancellation))>0)total+=count;
        if(total==buffer.Length)throw new IOException("Unexpected CLI version output.");
        return new string(buffer,0,total);
    }
}

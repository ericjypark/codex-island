using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;

namespace IslandPrototype;

internal static class WindowsCliCredential
{
    internal const string AntigravityTarget="gemini:antigravity";
    internal static byte[]? ReadAntigravity()=>Read(AntigravityTarget);
    internal static byte[]? Read(string target)
    {
        if(!OperatingSystem.IsWindows())return null;
        if(!CredRead(target,1,0,out var pointer)) {
            int error=Marshal.GetLastWin32Error();
            if(error==1168)return null;
            throw new IOException("The CLI credential could not be read.",new Win32Exception(error));
        }
        try {
            var credential=Marshal.PtrToStructure<Credential>(pointer);
            if(credential.Size>1024*1024||credential.Size>0&&credential.Blob==IntPtr.Zero)throw new IOException("Invalid CLI credential size.");
            byte[] bytes=new byte[credential.Size];
            if(bytes.Length>0)Marshal.Copy(credential.Blob,bytes,0,bytes.Length);
            return bytes;
        } finally {CredFree(pointer);}
    }
    internal static string AntigravityStamp()
    {
        if(!OperatingSystem.IsWindows())return "unavailable";
        if(!CredRead(AntigravityTarget,1,0,out var pointer))return "missing:"+Marshal.GetLastWin32Error();
        try {
            var credential=Marshal.PtrToStructure<Credential>(pointer);
            return credential.Written+":"+credential.Size;
        } finally {CredFree(pointer);}
    }
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]
    private struct Credential
    {
        internal uint Flags,Type;
        internal IntPtr Target,Comment;
        internal long Written;
        internal uint Size;
        internal IntPtr Blob;
        internal uint Persist,AttributeCount;
        internal IntPtr Attributes,Alias,UserName;
    }
    [DllImport("advapi32.dll",EntryPoint="CredReadW",CharSet=CharSet.Unicode,SetLastError=true)]
    [return:MarshalAs(UnmanagedType.Bool)] private static extern bool CredRead(string target,uint type,uint flags,out IntPtr credential);
    [DllImport("advapi32.dll")] private static extern void CredFree(IntPtr credential);
}

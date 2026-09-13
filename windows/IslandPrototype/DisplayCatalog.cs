using System;
using System.Linq;
using System.Runtime.InteropServices;
using Forms=System.Windows.Forms;

namespace IslandPrototype;

internal sealed record IslandDisplay(string Id,string Name,Forms.Screen Screen)
{
    public static IslandDisplay[] All() => Forms.Screen.AllScreens.Select((screen,index) => {
        var info = new DisplayDevice { Size = Marshal.SizeOf<DisplayDevice>() };
        bool found = EnumDisplayDevices(screen.DeviceName,0,ref info,1);
        string id = found && !string.IsNullOrWhiteSpace(info.Id) ? info.Id : screen.DeviceName;
        string name = found && !string.IsNullOrWhiteSpace(info.Description) ? info.Description : $"Display {index+1}";
        return new IslandDisplay(id,name,screen);
    }).ToArray();
    public static IslandDisplay Resolve(string id,Forms.Screen? automatic=null)
    {
        var all=All();
        return all.FirstOrDefault(d=>d.Id==id) ?? all.FirstOrDefault(d=>d.Screen.DeviceName==automatic?.DeviceName) ?? all.FirstOrDefault(d=>d.Screen.Primary) ?? all[0];
    }
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]
    private struct DisplayDevice
    {
        public int Size;
        [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)] public string Name;
        [MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)] public string Description;
        public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)] public string Id;
        [MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)] public string Key;
    }
    [DllImport("user32.dll",CharSet=CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumDisplayDevices(string? device,uint index,ref DisplayDevice result,uint flags);
}

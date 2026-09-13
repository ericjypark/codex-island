using System;
using System.Runtime.InteropServices;
using System.Text;

namespace IslandPrototype;

internal static class Native
{
    [DllImport("dwmapi.dll")] internal static extern int DwmSetWindowAttribute(nint window, int attribute, ref int value, int size);
    internal const int ExtendedStyle = -20;
    internal const int Transparent = 0x20;
    internal const int ToolWindow = 0x80;
    internal const int NoActivate = 0x08000000;
    internal delegate nint MouseProc(int code, nint message, nint data);
    internal delegate void WindowEventProc(nint hook,uint eventType,nint window,int objectId,int childId,uint thread,uint time);

    [StructLayout(LayoutKind.Sequential)] internal struct Point { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] internal struct Rect {public int Left,Top,Right,Bottom;}
    [StructLayout(LayoutKind.Sequential)] internal struct MouseData
    {
        public Point Point;
        public uint Mouse, Flags, Time;
        public nuint Extra;
    }

    [DllImport("user32.dll")] internal static extern nint SetWindowsHookEx(int id, MouseProc callback, nint module, uint thread);
    [DllImport("user32.dll")] internal static extern bool UnhookWindowsHookEx(nint hook);
    [DllImport("user32.dll")] internal static extern nint CallNextHookEx(nint hook, int code, nint message, nint data);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] internal static extern nint GetModuleHandle(string? module);
    [DllImport("user32.dll")] internal static extern int GetWindowLong(nint window, int index);
    [DllImport("user32.dll")] internal static extern int SetWindowLong(nint window, int index, int value);
    [DllImport("user32.dll")] internal static extern bool SetWindowPos(nint window, nint after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] internal static extern bool GetCursorPos(out Point point);
    [DllImport("user32.dll")] internal static extern nint GetForegroundWindow();
    [DllImport("user32.dll")] internal static extern bool SetForegroundWindow(nint window);
    [DllImport("user32.dll")] internal static extern nint MonitorFromPoint(Point point, uint flags);
    [DllImport("shcore.dll")] internal static extern int GetDpiForMonitor(nint monitor, int kind, out uint x, out uint y);
    [DllImport("user32.dll")] internal static extern bool RegisterHotKey(nint window, int id, uint modifiers, uint key);
    [DllImport("user32.dll")] internal static extern bool UnregisterHotKey(nint window, int id);
    [DllImport("user32.dll")] internal static extern nint SetWinEventHook(uint first,uint last,nint module,WindowEventProc callback,uint process,uint thread,uint flags);
    [DllImport("user32.dll")] internal static extern bool UnhookWinEvent(nint hook);
    [DllImport("user32.dll")] internal static extern bool GetClientRect(nint window,out Rect rectangle);
    [DllImport("user32.dll")] internal static extern bool ClientToScreen(nint window,ref Point point);
    [DllImport("user32.dll")] internal static extern bool IsWindowVisible(nint window);
    [DllImport("user32.dll")] internal static extern bool IsIconic(nint window);
    [DllImport("user32.dll")] internal static extern nint GetShellWindow();
    [DllImport("user32.dll")] internal static extern nint GetDesktopWindow();
    [DllImport("user32.dll")] internal static extern uint GetWindowThreadProcessId(nint window,out uint process);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] internal static extern int GetClassName(nint window,StringBuilder name,int count);
    [DllImport("dwmapi.dll")] internal static extern int DwmGetWindowAttribute(nint window,int attribute,out int value,int size);
}

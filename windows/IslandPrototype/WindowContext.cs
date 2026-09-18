using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Threading;

namespace IslandPrototype;

internal sealed class WindowContext:IDisposable
{
    private readonly nint island;
    private readonly Dispatcher dispatcher;
    private readonly Action changed;
    private readonly Native.WindowEventProc callback;
    private readonly List<nint> hooks=new();
    private GCHandle callbackRoot;
    private bool queued,disposed;
    private nint lastForeground;
    internal bool HooksAvailable {get;}
    internal WindowContext(nint island,Dispatcher dispatcher,Action changed)
    {
        this.island=island;this.dispatcher=dispatcher;this.changed=changed;
        callback=OnWindowEvent;callbackRoot=GCHandle.Alloc(callback);
        foreach(var range in new(uint,uint)[]{(3,3),(0x16,0x17),(0x20,0x20),(0x8001,0x8003),(0x800B,0x800B),(0x8017,0x8018)}) {
            var hook=Native.SetWinEventHook(range.Item1,range.Item2,0,callback,0,0,0);
            if(hook!=0)hooks.Add(hook);
        }
        HooksAvailable=hooks.Count==6;
    }
    private void OnWindowEvent(nint hook,uint eventType,nint window,int objectId,int childId,uint thread,uint time)
    {
        if(disposed||queued)return;
        if(eventType>=0x8000&&(objectId!=0||childId!=0))return;
        if(eventType>=0x8000&&window!=island&&window!=lastForeground&&window!=Native.GetForegroundWindow())return;
        if(window==island&&eventType is not (0x8017 or 0x8018)&&eventType>=0x8000)return;
        queued=true;
        dispatcher.BeginInvoke(DispatcherPriority.Background,new Action(()=>{queued=false;if(!disposed)changed();}));
    }
    internal (bool Fullscreen,bool Cloaked) Read(Rectangle monitor)
    {
        bool cloaked=Native.DwmGetWindowAttribute(island,14,out int ownCloak,4)==0&&ownCloak!=0;
        var foreground=Native.GetForegroundWindow();lastForeground=foreground;
        if(foreground==0||foreground==island||foreground==Native.GetShellWindow()||foreground==Native.GetDesktopWindow()
            ||!Native.IsWindowVisible(foreground)||Native.IsIconic(foreground))return(false,cloaked);
        Native.GetWindowThreadProcessId(foreground,out uint process);
        if(process==Environment.ProcessId)return(false,cloaked);
        var name=new StringBuilder(256);Native.GetClassName(foreground,name,name.Capacity);
        if(name.ToString() is "Progman" or "WorkerW")return(false,cloaked);
        if(Native.DwmGetWindowAttribute(foreground,14,out int cloak,4)==0&&cloak!=0)return(false,cloaked);
        if(!Native.GetClientRect(foreground,out var client))return(false,cloaked);
        var origin=new Native.Point {X=client.Left,Y=client.Top};
        if(!Native.ClientToScreen(foreground,ref origin))return(false,cloaked);
        return(FullscreenGeometry.CoversMonitor(new Rectangle(origin.X,origin.Y,client.Right-client.Left,client.Bottom-client.Top),monitor),cloaked);
    }
    public void Dispose()
    {
        if(disposed)return;disposed=true;
        foreach(var hook in hooks)Native.UnhookWinEvent(hook);
        hooks.Clear();if(callbackRoot.IsAllocated)callbackRoot.Free();
    }
}

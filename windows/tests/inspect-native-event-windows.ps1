param([Parameter(Mandatory=$true)][string]$Snapshot)
$ErrorActionPreference='Stop'
$profile=Get-Content (Join-Path $Snapshot 'interactive-profile.json') -Raw|ConvertFrom-Json
$app=Get-Process CodexIslandPrototype|Where-Object {$_.Path -eq $profile.executable}|Select-Object -First 1
if(!$app){throw 'The intended history preview is not running.'}
Add-Type @'
using System;using System.Text;using System.Collections.Generic;using System.Runtime.InteropServices;
public static class EventWindows {
 private delegate bool EnumProc(IntPtr window,IntPtr parameter);
 [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc callback,IntPtr parameter);
 [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window,out uint process);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] private static extern int GetClassName(IntPtr window,StringBuilder name,int capacity);
 public sealed class Entry {public long Window {get;set;}public string ClassName {get;set;}}
 public static Entry[] Read(uint process) {
  var results=new List<Entry>();
  EnumWindows((window,_)=>{uint owner;GetWindowThreadProcessId(window,out owner);if(owner==process){var name=new StringBuilder(256);GetClassName(window,name,name.Capacity);results.Add(new Entry{Window=window.ToInt64(),ClassName=name.ToString()});}return true;},IntPtr.Zero);
  return results.ToArray();
 }
}
'@
[EventWindows]::Read($app.Id)|ConvertTo-Json

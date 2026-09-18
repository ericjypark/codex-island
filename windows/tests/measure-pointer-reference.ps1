$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing @'
using System;using System.Threading;using System.Windows.Forms;using System.Drawing;using System.Diagnostics;using System.Runtime.InteropServices;using System.Collections.Generic;
public static class PointerReference {
 [DllImport("user32.dll")]static extern IntPtr SetThreadDpiAwarenessContext(IntPtr h);
 [DllImport("user32.dll")]static extern int GetSystemMetrics(int n);
 [DllImport("user32.dll")]static extern void mouse_event(uint f,uint x,uint y,uint d,UIntPtr e);
 [DllImport("user32.dll")]static extern IntPtr GetDC(IntPtr h);
 [DllImport("user32.dll")]static extern int ReleaseDC(IntPtr h,IntPtr dc);
 [DllImport("gdi32.dll")]static extern uint GetPixel(IntPtr dc,int x,int y);
 static Form form;static Panel panel;static AutoResetEvent ready=new AutoResetEvent(false);
 static void Move(int x,int y){mouse_event(0x8001,(uint)(x*65535.0/(GetSystemMetrics(0)-1)),(uint)(y*65535.0/(GetSystemMetrics(1)-1)),0,UIntPtr.Zero);}
 public static double[] Run(){
  SetThreadDpiAwarenessContext(new IntPtr(-4));
  var thread=new Thread(()=>{SetThreadDpiAwarenessContext(new IntPtr(-4));form=new Form{Text="Pointer timing reference",StartPosition=FormStartPosition.Manual,Left=500,Top=850,Width=300,Height=170,TopMost=true};panel=new Panel{Dock=DockStyle.Fill,BackColor=Color.FromArgb(56,56,56)};form.Controls.Add(panel);panel.MouseDown+=(_,e)=>panel.BackColor=Color.FromArgb(198,198,198);form.Shown+=(_,e)=>ready.Set();Application.Run(form);});
  thread.SetApartmentState(ApartmentState.STA);thread.Start();if(!ready.WaitOne(5000))throw new Exception("Reference window did not open.");
  var values=new List<double>();try{
   for(int i=0;i<12;i++){
    Point point=Point.Empty;form.Invoke(new Action(()=>{panel.BackColor=Color.FromArgb(56,56,56);point=panel.PointToScreen(new Point(70,50));}));
    Move(point.X,point.Y);Thread.Sleep(300);IntPtr dc=GetDC(IntPtr.Zero);
    try{if((GetPixel(dc,point.X,point.Y)&255)>130)throw new Exception("Reference pixel did not settle.");
     var watch=Stopwatch.StartNew();mouse_event(2,0,0,0,UIntPtr.Zero);mouse_event(4,0,0,0,UIntPtr.Zero);
     while(watch.ElapsedMilliseconds<1000){if((GetPixel(dc,point.X,point.Y)&255)>150)break;Thread.Sleep(1);}values.Add(watch.Elapsed.TotalMilliseconds);
    }finally{ReleaseDC(IntPtr.Zero,dc);}Thread.Sleep(400);
   }
  }finally{form.Invoke(new Action(()=>form.Close()));thread.Join(3000);}return values.ToArray();
 }
}
'@
$values=[PointerReference]::Run();$ordered=@($values|Sort-Object)
$report=@{reference='Plain WinForms panel changing background on native mouse-down';samples=$values;medianMs=$ordered[6];maxMs=$ordered[-1];scope='Same injected click and desktop GetPixel probe as the island; includes readback and guest compositor latency'}
$report|ConvertTo-Json|Set-Content (Join-Path $PSScriptRoot '..\artifacts\responsiveness-confirmed\pointer-reference.json')
$report|ConvertTo-Json

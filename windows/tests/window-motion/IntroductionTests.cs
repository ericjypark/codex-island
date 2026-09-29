using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Automation.Provider;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

internal static class IntroductionTests
{
    private const BindingFlags Flags=BindingFlags.Instance|BindingFlags.Public|BindingFlags.NonPublic;
    [StructLayout(LayoutKind.Sequential)] private struct NativePoint {public int X,Y;}
    [StructLayout(LayoutKind.Sequential)] private struct NativeRect {public int Left,Top,Right,Bottom;}
    [DllImport("user32.dll")] private static extern nint GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(nint window);
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out NativePoint point);
    [DllImport("user32.dll")] private static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll")] private static extern void mouse_event(uint flags,uint x,uint y,uint data,nuint extra);
    [DllImport("user32.dll")] private static extern int GetWindowLong(nint window,int index);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(nint window,out NativeRect rect);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(nint window,nint after,int x,int y,int width,int height,uint flags);
    internal static nint Foreground=>GetForegroundWindow();
    private static void Move(int x,int y)=>mouse_event(0xC001,
        (uint)Math.Clamp((x-GetSystemMetrics(76))*65535.0/(GetSystemMetrics(78)-1),0,65535),
        (uint)Math.Clamp((y-GetSystemMetrics(77))*65535.0/(GetSystemMetrics(79)-1),0,65535),0,0);

    internal static async Task Run(Window window,string output,nint initialForeground)
    {
        var checks=new List<object>();int failures=0;var type=window.GetType();
        object? Field(string name)=>type.GetField(name,Flags)!.GetValue(window);
        bool Flag(string name)=>(bool)Field(name)!;
        void Call(string name,params object[] args)=>type.GetMethod(name,Flags)!.Invoke(window,args);
        void Check(string name,bool pass){checks.Add(new{name,pass});Console.WriteLine((pass?"PASS ":"FAIL ")+name);if(!pass)failures++;}
        var preferences=Field("preferences")!;var preferenceType=preferences.GetType();
        object Values()=>preferenceType.GetProperty("Value")!.GetValue(preferences)!;
        object Value(string name)=>Values().GetType().GetProperty(name)!.GetValue(Values())!;
        void Preference(string name,object value) {
            var values=Values();var next=values.GetType().GetMethod("<Clone>$")!.Invoke(values,null)!;
            next.GetType().GetProperty(name)!.SetValue(next,value);
            if(!(bool)preferenceType.GetMethod("Update")!.Invoke(preferences,new[]{next})!)throw new Exception("Could not save test preferences");
        }
        async Task Wait(Func<bool> predicate,int milliseconds=2000) {
            var timer=Stopwatch.StartNew();while(!predicate()&&timer.ElapsedMilliseconds<milliseconds)await Task.Delay(25);
            if(!predicate())throw new Exception("Timed out waiting for introduction state");
        }
        FrameworkElement Find(DependencyObject parent,string id) {
            if(parent is FrameworkElement element&&AutomationProperties.GetAutomationId(element)==id)return element;
            for(int i=0;i<VisualTreeHelper.GetChildrenCount(parent);i++) {
                try{return Find(VisualTreeHelper.GetChild(parent,i),id);}catch(InvalidOperationException){}
            }
            throw new InvalidOperationException("Missing element "+id);
        }
        void Click(Button button) {
            var peer=new ButtonAutomationPeer(button);
            ((IInvokeProvider)peer.GetPattern(PatternInterface.Invoke)).Invoke();
        }
        async Task Capture(string name) {
            double scale=VisualTreeHelper.GetDpi(window).DpiScaleX;
            GetWindowRect(new WindowInteropHelper(window).Handle,out var rect);
            var backdrop=new Window{WindowStyle=WindowStyle.None,ShowInTaskbar=false,ShowActivated=false,ResizeMode=ResizeMode.NoResize,Background=new SolidColorBrush(Color.FromRgb(38,46,62))};
            backdrop.Show();
            try {
                int width=(int)(448*scale),height=(int)(240*scale);
                SetWindowPos(new WindowInteropHelper(backdrop).Handle,0,rect.Left,rect.Top,rect.Right-rect.Left,height,0x10);
                await Task.Delay(200);
                using var bitmap=new System.Drawing.Bitmap(width,height);
                using(var graphics=System.Drawing.Graphics.FromImage(bitmap))graphics.CopyFromScreen(rect.Left+(rect.Right-rect.Left-width)/2,rect.Top,0,0,bitmap.Size);
                bitmap.Save(Path.Combine(output,name+".png"),System.Drawing.Imaging.ImageFormat.Png);
            } finally {backdrop.Close();}
        }
        GetCursorPos(out var originalPointer);
        var hwnd=new WindowInteropHelper(window).Handle;
        Directory.CreateDirectory(output);
        try {
            await Wait(()=>Flag("introductionVisible"),5000);
            await Task.Delay(450);
            Check("Normal first launch reveals the real pill and introduction",Flag("introductionVisible")&&Field("state")!.ToString()=="Peek");
            Check("Automatic introduction preserves the foreground application",Foreground==initialForeground);
            Check("Showing the guide does not prematurely mark it completed",!(bool)Value("HasSeenIntroduction"));
            var introduction=(FrameworkElement)Field("introduction")!;
            var timer=(DispatcherTimer)Field("introductionTimer")!;
            var island=(FrameworkElement)Field("Island")!;
            Check("The guide is placed directly beneath the pill",introduction.Margin.Top>=island.ActualHeight+12);
            Check("The guide exposes a polite accessible announcement",AutomationProperties.GetLiveSetting(introduction)==AutomationLiveSetting.Polite&&UIElementAutomationPeer.CreatePeerForElement(introduction)!=null);
            Check("Automatic dismissal allows eight seconds to read",timer.Interval==TimeSpan.FromSeconds(8));
            await Capture("introduction");
            var center=introduction.PointToScreen(new Point(introduction.ActualWidth/2,introduction.ActualHeight/2));
            Move((int)center.X,(int)center.Y);await Task.Delay(250);
            Check("Hovering the guide pauses dismissal",Flag("introductionVisible")&&!timer.IsEnabled);
            Check("The guide receives clicks without losing the pill",(GetWindowLong(hwnd,-20)&0x20)==0&&Field("state")!.ToString()=="Peek");
            Check("Mouse interaction with the automatic guide remains nonactivating",(GetWindowLong(hwnd,-20)&0x08000000)!=0);
            var outside=window.PointToScreen(new Point(12,window.ActualHeight+30));
            Move((int)outside.X,(int)outside.Y);await Task.Delay(250);
            Check("The surrounding transparent area remains click-through",(GetWindowLong(hwnd,-20)&0x20)!=0);
            var dismissal=Stopwatch.StartNew();await Wait(()=>!Flag("introductionVisible"),10500);await Task.Delay(800);
            Check("The unattended guide and pill return to hidden rest",Field("state")!.ToString()=="Hidden"&&!timer.IsEnabled&&dismissal.ElapsedMilliseconds>=7400);
            Check("Introduction completion is persisted",(bool)Value("HasSeenIntroduction"));
            string preferencesPath=(string)preferenceType.GetField("path",Flags)!.GetValue(preferences)!;
            var reloaded=Activator.CreateInstance(preferenceType,new object[]{preferencesPath})!;
            var saved=preferenceType.GetProperty("Value")!.GetValue(reloaded)!;
            Check("A new preferences reader retains completion",(bool)saved.GetType().GetProperty("HasSeenIntroduction")!.GetValue(saved)!);
            Call("OfferIntroduction",false);await Task.Delay(650);
            Check("A completed introduction is not automatically repeated",!Flag("introductionVisible")&&!Flag("introductionPending"));

            Preference("HasSeenIntroduction",false);Call("OfferIntroduction",false);await Wait(()=>Flag("introductionVisible"));await Task.Delay(250);
            var done=(Button)Find(introduction,"IntroductionDone");
            var clickPoint=done.PointToScreen(new Point(done.ActualWidth/2,done.ActualHeight/2));
            var beforeClick=Foreground;Move((int)clickPoint.X,(int)clickPoint.Y);await Task.Delay(150);
            mouse_event(2,0,0,0,0);mouse_event(4,0,0,0,0);await Wait(()=>!Flag("introductionVisible"));await Task.Delay(700);
            Check("A native click dismisses the guide and returns focus",Foreground==beforeClick&&Field("state")!.ToString()=="Hidden");
            Move((int)outside.X,(int)outside.Y);await Task.Delay(100);

            Call("OfferIntroduction",true);await Wait(()=>Flag("introductionVisible"));await Task.Delay(200);
            Check("Replay is available and accepts keyboard focus",introduction.IsKeyboardFocusWithin&&!timer.IsEnabled);
            Click((Button)Find(introduction,"IntroductionDone"));await Wait(()=>!Flag("introductionVisible"));await Task.Delay(700);
            Check("Got it dismisses the guide and stops its timer",!Flag("introductionPending")&&!timer.IsEnabled&&Field("state")!.ToString()=="Hidden");

            Call("OfferIntroduction",true);await Wait(()=>Flag("introductionVisible"));
            Click((Button)Find(introduction,"IntroductionConnect"));await Wait(()=>Field("settingsWindow") is Window settings&&settings.IsVisible);
            Check("Connect accounts opens the real provider settings",(string)Value("SettingsTab")=="providers"&&!Flag("introductionVisible"));
            ((Window)Field("settingsWindow")!).Close();await Task.Delay(250);

            type.GetField("sessionLocked",Flags)!.SetValue(window,true);Call("UpdateWindowContext");
            Call("OfferIntroduction",true);await Task.Delay(700);
            Check("Suppressed sessions defer the guide",!Flag("introductionVisible")&&Flag("introductionPending"));
            var beforeResume=Foreground;
            type.GetField("sessionLocked",Flags)!.SetValue(window,false);Call("UpdateWindowContext");await Wait(()=>Flag("introductionVisible"));
            Check("The deferred guide resumes without activating the window",Foreground==beforeResume&&Field("state")!.ToString()=="Peek");
            type.GetField("sessionLocked",Flags)!.SetValue(window,true);Call("UpdateWindowContext");
            Check("Suppression also hides an already visible guide",!Flag("introductionVisible")&&Flag("introductionPending")&&!timer.IsEnabled);
            type.GetField("sessionLocked",Flags)!.SetValue(window,false);Call("UpdateWindowContext");await Wait(()=>Flag("introductionVisible"));
            Call("CompleteIntroduction");Call("Dismiss",false);

            Preference("ReduceMotion",true);Call("OfferIntroduction",true);await Wait(()=>Flag("introductionVisible"));
            Check("Reduced motion shows a settled pill and readable guide",!Flag("shellMoving")&&introduction.Opacity==1);
            await Capture("introduction-reduced-motion");
            var key=new KeyEventArgs(Keyboard.PrimaryDevice,PresentationSource.FromVisual(window),Environment.TickCount,Key.Escape){RoutedEvent=Keyboard.KeyDownEvent};
            introduction.RaiseEvent(key);await Task.Delay(250);
            Check("Escape dismisses the keyboard-accessible guide",!Flag("introductionVisible")&&!timer.IsEnabled);

            Preference("AlwaysShowUsage",true);Call("OfferIntroduction",true);await Wait(()=>Flag("introductionVisible"));
            Click((Button)Find(introduction,"IntroductionDone"));await Wait(()=>!Flag("introductionVisible"));
            Check("Dismissing introduction respects Keep pill visible",Field("state")!.ToString()=="Peek");
            Preference("AlwaysShowUsage",false);
            Call("OfferIntroduction",true);await Wait(()=>Flag("introductionVisible"));
            var stateType=type.GetNestedType("IslandState",BindingFlags.NonPublic)!;
            Call("SetState",Enum.Parse(stateType,"Expanded"),true);await Task.Delay(600);
            Check("Opening the actual pill completes introduction",!Flag("introductionVisible")&&Field("state")!.ToString()=="Expanded"&&!timer.IsEnabled);
            Call("Dismiss",false);
        } finally {
            Call("StopIntroduction");
            type.GetField("sessionLocked",Flags)!.SetValue(window,false);
            Move(originalPointer.X,originalPointer.Y);
            if(initialForeground!=0)SetForegroundWindow(initialForeground);
            File.WriteAllText(Path.Combine(output,"introduction-results.json"),JsonSerializer.Serialize(new {build=type.Assembly.ManifestModule.ModuleVersionId,dpi=VisualTreeHelper.GetDpi(window).DpiScaleX,failures,checks,fullscreen=Flag("fullscreen"),state=Field("state")!.ToString(),seen=Value("HasSeenIntroduction")},new JsonSerializerOptions{WriteIndented=true}));
        }
        if(failures>0)throw new Exception(failures+" introduction checks failed");
    }
}

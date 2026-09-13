using System;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using IslandPrototype;

internal static class ResetCreditUiTests
{
    [DllImport("user32.dll")]private static extern bool SetCursorPos(int x,int y);
    [DllImport("user32.dll")]private static extern bool GetCursorPos(out NativePoint point);
    [DllImport("user32.dll")]private static extern IntPtr GetDC(IntPtr window);
    [DllImport("user32.dll")]private static extern int ReleaseDC(IntPtr window,IntPtr dc);
    [DllImport("gdi32.dll")]private static extern bool BitBlt(IntPtr destination,int x,int y,int width,int height,IntPtr source,int sourceX,int sourceY,uint flags);
    [DllImport("dwmapi.dll")]private static extern int DwmFlush();
    [StructLayout(LayoutKind.Sequential)]private struct NativePoint{public int X,Y;}
    internal static async Task Run(string output,Action<string,bool> check)
    {
        GetCursorPos(out var original);string language=Localizer.Language;
        DateTimeOffset now=DateTimeOffset.Now;
        var client=new Client {Credits=new(5,[new("day5","available",now.AddDays(5)),new("day2","available",now.AddDays(2)),new("used","redeemed",now.AddDays(1)),new("day3","available",now.AddDays(3)),new("expired","available",now.AddDays(-1)),new("day4","available",now.AddDays(4))])};
        using var feed=new UsageFeed(new LiveUsageCoordinator(client));feed.Select(["claude","codex"]);await feed.RefreshAsync(true);
        var surface=new IslandVisual {Width=800,Height=226,Expanded=true,ContentOpacity=1,LogoOpacity=0,Preferences=new IslandPreferences{LeftProvider="claude",RightProvider="codex"},Feed=feed};
        var window=new Window {Width=800,Height=226,Left=110,Top=170,WindowStyle=WindowStyle.None,AllowsTransparency=true,Background=Brushes.Transparent,ShowInTaskbar=false,Topmost=true,Content=surface,Title="CodexIsland reset credits test"};
        window.Show();window.Activate();
        void Move(Point point){var screen=surface.PointToScreen(point);SetCursorPos((int)screen.X,(int)screen.Y);}
        async Task Settle(){surface.InvalidateVisual();await Task.Delay(250);}
        async Task Capture(string name) {
            await Settle();Marshal.ThrowExceptionForHR(DwmFlush());
            Point corner=surface.PointToScreen(new Point()),end=surface.PointToScreen(new Point(800,226));
            using var bitmap=new System.Drawing.Bitmap((int)(end.X-corner.X),(int)(end.Y-corner.Y));
            using(var graphics=System.Drawing.Graphics.FromImage(bitmap)) {
                IntPtr source=GetDC(IntPtr.Zero),destination=graphics.GetHdc();
                try {if(!BitBlt(destination,0,0,bitmap.Width,bitmap.Height,source,(int)corner.X,(int)corner.Y,0x40CC0020))throw new Exception("Native reset capture failed.");}
                finally{graphics.ReleaseHdc(destination);ReleaseDC(IntPtr.Zero,source);}
            }
            bitmap.Save(Path.Combine(output,name+".png"));
        }
        try {
            Move(new Point(400,210));await Settle();
            var badge=surface.AccessibleTargets.Single(t=>t.Help=="5 Codex resets available");
            check("Live reset badge uses the available count without a sample label",badge.Bounds.Width>50&&surface.AccessibleTargets.All(t=>!t.Help.Contains("sample")));
            Move(new Point(badge.Bounds.Left+5,badge.Bounds.Top+5));await Settle();
            var rows=surface.AccessibleTargets.Where(t=>t.Help.StartsWith("Codex reset expires ")).ToArray();
            check("Native pointer hover opens the expiration panel",surface.ResetPopoverProgress==1&&rows.Length==3);
            check("Expiration rows are ordered and exclude used/expired credits",rows.Select(t=>t.Help).SequenceEqual(new[]{2,3,4}.Select(days=>"Codex reset expires "+now.AddDays(days).LocalDateTime.ToString("MMM d, yyyy",Localizer.Culture))));
            check("The panel matches the Mac width and downward anchor",Math.Abs(rows[0].Bounds.Width-198)<.01&&Math.Abs(rows[0].Bounds.Top-badge.Bounds.Top-34)<.01);
            await Capture("reset-credits-open-windows");
            Move(new Point(badge.Bounds.Right-10,badge.Bounds.Bottom+2));await Task.Delay(25);
            Move(new Point(rows[0].Bounds.Left+10,rows[0].Bounds.Top+10));await Settle();
            check("Crossing the badge-to-panel gap preserves the panel",surface.ResetPopoverProgress==1);
            Move(new Point(400,210));await Settle();
            check("Leaving the panel closes it after the grace interval",surface.ResetPopoverProgress==0);
            surface.FocusTarget(badge.Help);await Settle();
            check("Keyboard focus exposes the same expiration details",surface.IsKeyboardFocusWithin&&surface.ResetPopoverProgress==1);
            check("Dismiss closes the details before dismissing the island",surface.DismissResetPopover());await Settle();
            check("Dismissal leaves the island expanded",surface.Expanded&&surface.ResetPopoverProgress==0);
            surface.FocusNext(false);Keyboard.ClearFocus();
            surface.LowPower=true;surface.ReduceMotion=true;
            badge.Action();await Settle();
            check("Reduced motion reveals the complete panel without a transition",surface.ResetPopoverProgress==1);
            surface.DismissResetPopover(true);surface.ReduceMotion=false;surface.LowPower=false;
            Localizer.Language="zh-Hans";await Settle();
            var chinese=surface.AccessibleTargets.Single(t=>t.Help.Contains("Codex")&&t.Help.Contains("重置可用"));chinese.Action();
            await Capture("reset-credits-chinese-windows");
            check("Reset availability and dates are localized",surface.AccessibleTargets.Count(t=>t.Help.Contains("重置到期日期")&&t.Help.Contains("年"))==3);
            surface.DismissResetPopover(true);Localizer.Language="en";
            surface.Preferences=surface.Preferences with{LeftProvider="codex",RightProvider="claude"};await Settle();
            surface.AccessibleTargets.Single(t=>t.Help=="5 Codex resets available").Action();await Capture("reset-credits-left-windows");
            check("The left-provider panel stays inside the island",surface.AccessibleTargets.Where(t=>t.Help.StartsWith("Codex reset expires ")).All(t=>t.Bounds.Left>=8&&t.Bounds.Right<=800));
            client.Credits=new(0,[]);await feed.RefreshAsync(true);await Settle();
            check("A zero-credit refresh removes an open panel and badge",surface.ResetPopoverProgress==0&&surface.AccessibleTargets.All(t=>!t.Help.Contains("Codex reset")));
            client.Credits=new(2,null);await feed.RefreshAsync(true);await Settle();
            check("Count-only data does not invent expiration details",surface.AccessibleTargets.All(t=>!t.Help.Contains("Codex reset")));
            client.Credits=new(1,[new("one","available",now.AddDays(1))]);await feed.RefreshAsync(true);await Settle();
            check("A single live credit uses the singular label",surface.AccessibleTargets.Any(t=>t.Help=="1 Codex reset available"));
            surface.Preferences=surface.Preferences with{LeftProvider="claude",RightProvider=null};await Settle();
            check("Hiding Codex also hides its credit badge",surface.AccessibleTargets.All(t=>!t.Help.Contains("Codex reset")));
        }finally{window.Close();Localizer.Language=language;SetCursorPos(original.X,original.Y);}
    }
    private sealed class Client:IUsageClient
    {
        internal CodexResetCredits? Credits;
        public Task<UsageResult> FetchAsync(string provider,CancellationToken cancellation)=>Task.FromResult(new UsageResult(UsageStatus.Ready,[new("5h",17,DateTimeOffset.Now.AddHours(2)),new("week",0,DateTimeOffset.Now.AddDays(3))],"pro",provider,ResetCredits:provider=="codex"?Credits:null));
    }
}
